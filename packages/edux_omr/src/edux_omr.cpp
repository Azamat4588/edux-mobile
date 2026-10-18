// EduX javob varaqasini telefonda o'qish. Tavsif: edux_omr.h.
//
// Tashqi kutubxona yo'q (OpenCV ham): ArUco belgilarini topish, gomografiya, yorug'likni tekislash va
// doirachalarni o'qish shu faylda. QR uchun quirc (ISC), JPEG/PNG uchun stb (public domain).
// Qoidalar serverdagi omr-service/omr/scanner.py bilan bir xil — ikki o'quvchi bir xil natija beradi.

#include "edux_omr.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

extern "C" {
#include "quirc/quirc.h"
}

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#include "stb/stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO
#include "stb/stb_image_write.h"

namespace {

// ---------------------------------------------------------------- varaqa o'lchamlari (layout.py)
constexpr int kLayoutVersion = 1;
constexpr double kA4W = 210.0, kA4H = 297.0;
constexpr double kMarkerSize = 12.0;
constexpr double kMarkerCenters[4][2] = {{15.0, 15.0}, {195.0, 15.0}, {195.0, 282.0}, {15.0, 282.0}};
constexpr double kBubbleR = 2.1;
constexpr int kIdDigits = 6;
constexpr double kIdX0 = 24.0, kIdY0 = 52.0, kIdPitchX = 6.0, kIdPitchY = 5.2;
constexpr int kRowsPerColumn = 30, kMaxColumns = 3, kMaxQuestions = kRowsPerColumn * kMaxColumns;
constexpr double kAnsY0 = 112.0, kAnsPitchY = 5.5, kAnsX0 = 36.0, kAnsColumnStep = 56.0, kAnsPitchX = 7.5;
constexpr double kQrX = 158.0, kQrY = 32.0, kQrSide = 26.0;

// Doiracha qoraligi (0 — oq qog'oz, 1 — to'liq qora): server bilan bir xil chegaralar.
constexpr double kFillThreshold = 0.38;
constexpr double kEmptyThreshold = 0.20;
constexpr double kSampleRadiusFactor = 0.70;

// To'g'rilangan varaqa aniqligi (piksel / mm). Server 8 ishlatadi; telefon kadri ~6 px/mm beradi.
constexpr double kScanPxPerMm = 6.0;
constexpr double kPreviewPxPerMm = 3.0;
constexpr int kUploadMaxSide = 2000;

// ArUco DICT_4X4_50, id 0..3: ichki 4x4 bit (1 = oq), qatorma-qator, belgining asl holatida.
constexpr uint16_t kMarkerCodes[4] = {0b1011010100110010, 0b0000111110011010, 0b0011001100101101,
                                      0b1001100101000110};

// ---------------------------------------------------------------- asosiy turlar
struct Pt {
    double x = 0, y = 0;
};

struct Gray {
    int w = 0, h = 0;
    std::vector<uint8_t> d;
    Gray() = default;
    Gray(int width, int height, uint8_t fill = 0) : w(width), h(height), d(size_t(width) * height, fill) {}
    uint8_t at(int x, int y) const { return d[size_t(y) * w + x]; }
    uint8_t& at(int x, int y) { return d[size_t(y) * w + x]; }
};

struct Flt {
    int w = 0, h = 0;
    std::vector<float> d;
    Flt(int width, int height) : w(width), h(height), d(size_t(width) * height, 0.f) {}
    float at(int x, int y) const { return d[size_t(y) * w + x]; }
};

Gray from_buffer(const uint8_t* src, int w, int h, int stride) {
    Gray g(w, h);
    for (int y = 0; y < h; ++y) std::memcpy(&g.d[size_t(y) * w], src + size_t(y) * stride, size_t(w));
    return g;
}

inline double bilinear(const Gray& g, double x, double y, double outside = 255.0) {
    if (x < 0 || y < 0 || x > g.w - 1 || y > g.h - 1) return outside;
    int x0 = int(x), y0 = int(y);
    int x1 = std::min(x0 + 1, g.w - 1), y1 = std::min(y0 + 1, g.h - 1);
    double fx = x - x0, fy = y - y0;
    double a = g.at(x0, y0) + (g.at(x1, y0) - g.at(x0, y0)) * fx;
    double b = g.at(x0, y1) + (g.at(x1, y1) - g.at(x0, y1)) * fx;
    return a + (b - a) * fy;
}

// Kichraytirish: avval butun karrali blok o'rtachasi, keyin bilinear (sifatli va tez).
Gray downscale(const Gray& src, double scale) {
    if (scale >= 0.999) return src;
    int k = std::max(1, int(std::floor(1.0 / scale)));
    Gray mid = src;
    if (k > 1) {
        int mw = src.w / k, mh = src.h / k;
        mid = Gray(mw, mh);
        for (int y = 0; y < mh; ++y) {
            for (int x = 0; x < mw; ++x) {
                unsigned sum = 0;
                for (int dy = 0; dy < k; ++dy) {
                    const uint8_t* row = &src.d[size_t(y * k + dy) * src.w + size_t(x) * k];
                    for (int dx = 0; dx < k; ++dx) sum += row[dx];
                }
                mid.at(x, y) = uint8_t(sum / unsigned(k * k));
            }
        }
    }
    int tw = std::max(1, int(std::lround(src.w * scale))), th = std::max(1, int(std::lround(src.h * scale)));
    if (tw == mid.w && th == mid.h) return mid;
    Gray out(tw, th);
    double sx = double(mid.w) / tw, sy = double(mid.h) / th;
    for (int y = 0; y < th; ++y)
        for (int x = 0; x < tw; ++x)
            out.at(x, y) = uint8_t(std::lround(bilinear(mid, std::min((x + 0.5) * sx - 0.5, mid.w - 1.0),
                                                         std::min((y + 0.5) * sy - 0.5, mid.h - 1.0), 255.0)));
    return out;
}

// ---------------------------------------------------------------- gomografiya
struct Homography {
    double m[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
    Pt map(Pt p) const {
        double w = m[6] * p.x + m[7] * p.y + m[8];
        if (std::fabs(w) < 1e-12) w = 1e-12;
        return {(m[0] * p.x + m[1] * p.y + m[2]) / w, (m[3] * p.x + m[4] * p.y + m[5]) / w};
    }
};

bool solve(std::vector<double>& a, std::vector<double>& b, int n) {
    for (int col = 0; col < n; ++col) {
        int pivot = col;
        for (int r = col + 1; r < n; ++r)
            if (std::fabs(a[r * n + col]) > std::fabs(a[pivot * n + col])) pivot = r;
        if (std::fabs(a[pivot * n + col]) < 1e-12) return false;
        if (pivot != col) {
            for (int c = 0; c < n; ++c) std::swap(a[col * n + c], a[pivot * n + c]);
            std::swap(b[col], b[pivot]);
        }
        for (int r = 0; r < n; ++r) {
            if (r == col) continue;
            double f = a[r * n + col] / a[col * n + col];
            if (f == 0) continue;
            for (int c = col; c < n; ++c) a[r * n + c] -= f * a[col * n + c];
            b[r] -= f * b[col];
        }
    }
    for (int i = 0; i < n; ++i) b[i] /= a[i * n + i];
    return true;
}

// Hartley normallashtirish: nuqtalar markazga va o'rtacha sqrt(2) masofaga keltiriladi.
void normalizer(const std::vector<Pt>& pts, double t[9]) {
    double cx = 0, cy = 0;
    for (auto& p : pts) cx += p.x, cy += p.y;
    cx /= pts.size(), cy /= pts.size();
    double dist = 0;
    for (auto& p : pts) dist += std::hypot(p.x - cx, p.y - cy);
    dist /= pts.size();
    double s = dist > 1e-12 ? std::sqrt(2.0) / dist : 1.0;
    double v[9] = {s, 0, -s * cx, 0, s, -s * cy, 0, 0, 1};
    std::memcpy(t, v, sizeof v);
}

void mat_mul(const double a[9], const double b[9], double out[9]) {
    double r[9];
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j) r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
    std::memcpy(out, r, sizeof r);
}

bool mat_inv(const double a[9], double out[9]) {
    double det = a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6]);
    if (std::fabs(det) < 1e-15) return false;
    double r[9] = {(a[4] * a[8] - a[5] * a[7]) / det, (a[2] * a[7] - a[1] * a[8]) / det, (a[1] * a[5] - a[2] * a[4]) / det,
                   (a[5] * a[6] - a[3] * a[8]) / det, (a[0] * a[8] - a[2] * a[6]) / det, (a[2] * a[3] - a[0] * a[5]) / det,
                   (a[3] * a[7] - a[4] * a[6]) / det, (a[1] * a[6] - a[0] * a[7]) / det, (a[0] * a[4] - a[1] * a[3]) / det};
    std::memcpy(out, r, sizeof r);
    return true;
}

// src -> dst o'zgartirish (kamida 4 nuqta, eng kichik kvadratlar).
bool find_homography(const std::vector<Pt>& src, const std::vector<Pt>& dst, Homography& out) {
    if (src.size() < 4 || src.size() != dst.size()) return false;
    double ts[9], td[9];
    normalizer(src, ts);
    normalizer(dst, td);
    std::vector<double> ata(64, 0.0), atb(8, 0.0);
    for (size_t i = 0; i < src.size(); ++i) {
        double x = ts[0] * src[i].x + ts[2], y = ts[4] * src[i].y + ts[5];
        double u = td[0] * dst[i].x + td[2], v = td[4] * dst[i].y + td[5];
        double r1[8] = {x, y, 1, 0, 0, 0, -u * x, -u * y};
        double r2[8] = {0, 0, 0, x, y, 1, -v * x, -v * y};
        for (int a = 0; a < 8; ++a) {
            for (int b = 0; b < 8; ++b) ata[a * 8 + b] += r1[a] * r1[b] + r2[a] * r2[b];
            atb[a] += r1[a] * u + r2[a] * v;
        }
    }
    if (!solve(ata, atb, 8)) return false;
    double hn[9] = {atb[0], atb[1], atb[2], atb[3], atb[4], atb[5], atb[6], atb[7], 1.0};
    double tdi[9], tmp[9];
    if (!mat_inv(td, tdi)) return false;
    mat_mul(tdi, hn, tmp);
    mat_mul(tmp, ts, out.m);
    if (std::fabs(out.m[8]) > 1e-12)
        for (double& v : out.m) v /= out.m[8];
    return true;
}

// ---------------------------------------------------------------- belgilarni topish
struct Marker {
    int id = -1;
    Pt corners[4];  // belgining asl holatida: yuqori-chap, yuqori-o'ng, pastki-o'ng, pastki-chap
    Pt center;
    double side = 0;      // o'rtacha tomon uzunligi (piksel)
    double contrast = 0;  // oq va qora kataklar farqi
    double white = 0;     // oq kataklar yorug'ligi
    int errors = 0;
};

double cross(Pt o, Pt a, Pt b) { return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x); }

std::vector<Pt> convex_hull(std::vector<Pt> pts) {
    std::sort(pts.begin(), pts.end(), [](Pt a, Pt b) { return a.x < b.x || (a.x == b.x && a.y < b.y); });
    pts.erase(std::unique(pts.begin(), pts.end(), [](Pt a, Pt b) { return a.x == b.x && a.y == b.y; }), pts.end());
    if (pts.size() < 3) return pts;
    std::vector<Pt> hull(2 * pts.size());
    size_t k = 0;
    for (size_t i = 0; i < pts.size(); ++i) {
        while (k >= 2 && cross(hull[k - 2], hull[k - 1], pts[i]) <= 0) --k;
        hull[k++] = pts[i];
    }
    for (size_t i = pts.size() - 1, t = k + 1; i > 0; --i) {
        while (k >= t && cross(hull[k - 2], hull[k - 1], pts[i - 1]) <= 0) --k;
        hull[k++] = pts[i - 1];
    }
    hull.resize(k - 1);
    return hull;
}

double polygon_area(const std::vector<Pt>& p) {
    double a = 0;
    for (size_t i = 0; i < p.size(); ++i) {
        const Pt& u = p[i];
        const Pt& v = p[(i + 1) % p.size()];
        a += u.x * v.y - v.x * u.y;
    }
    return a / 2;
}

double dist_to_line(Pt p, Pt a, Pt b) {
    double len = std::hypot(b.x - a.x, b.y - a.y);
    return len < 1e-9 ? std::hypot(p.x - a.x, p.y - a.y) : std::fabs(cross(a, b, p)) / len;
}

// Qavariq qobiqdan to'rtburchak: eng uzoq ikki nuqta (diagonal), so'ng har tomondan eng uzoq nuqta.
bool hull_to_quad(const std::vector<Pt>& hull, Pt quad[4]) {
    if (hull.size() < 4) return false;
    Pt c{0, 0};
    for (auto& p : hull) c.x += p.x, c.y += p.y;
    c.x /= hull.size(), c.y /= hull.size();
    size_t a = 0;
    double best = -1;
    for (size_t i = 0; i < hull.size(); ++i) {
        double d = std::hypot(hull[i].x - c.x, hull[i].y - c.y);
        if (d > best) best = d, a = i;
    }
    size_t b = a;
    best = -1;
    for (size_t i = 0; i < hull.size(); ++i) {
        double d = std::hypot(hull[i].x - hull[a].x, hull[i].y - hull[a].y);
        if (d > best) best = d, b = i;
    }
    if (a == b) return false;
    size_t left = a, right = a;
    double bestLeft = 0, bestRight = 0;
    for (size_t i = 0; i < hull.size(); ++i) {
        double s = cross(hull[a], hull[b], hull[i]);
        if (s > bestLeft) bestLeft = s, left = i;
        if (-s > bestRight) bestRight = -s, right = i;
    }
    if (left == a || right == a) return false;
    // Tartib: a, (bir tomoni), b, (ikkinchi tomoni) — qobiq bo'ylab soat yo'nalishida
    quad[0] = hull[a];
    quad[1] = hull[right];
    quad[2] = hull[b];
    quad[3] = hull[left];
    std::vector<Pt> q(quad, quad + 4);
    if (polygon_area(q) < 0) std::swap(quad[1], quad[3]);  // tasvirda (y pastga) soat yo'nalishi: maydon > 0
    return true;
}

// To'rtburchak tomonlariga yaqin chegara nuqtalaridan to'g'ri chiziqlar o'tkazib, burchaklarni aniqlashtiradi.
void refine_quad(const std::vector<Pt>& boundary, Pt quad[4]) {
    struct Line {
        double nx, ny, c;
        bool ok;
    };
    Line lines[4];
    for (int e = 0; e < 4; ++e) {
        Pt a = quad[e], b = quad[(e + 1) % 4];
        double len = std::hypot(b.x - a.x, b.y - a.y);
        double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
        int n = 0;
        for (const Pt& p : boundary) {
            double t = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / (len * len);
            if (t < 0.12 || t > 0.88) continue;  // burchak atrofi chiziqqa kirmaydi
            if (dist_to_line(p, a, b) > std::max(1.5, len * 0.06)) continue;
            sx += p.x, sy += p.y, sxx += p.x * p.x, syy += p.y * p.y, sxy += p.x * p.y, ++n;
        }
        if (n < 4) {
            lines[e].ok = false;
            continue;
        }
        double mx = sx / n, my = sy / n;
        double cxx = sxx / n - mx * mx, cyy = syy / n - my * my, cxy = sxy / n - mx * my;
        // Kovariatsiyaning eng kichik xos vektori — chiziq normali
        double theta = 0.5 * std::atan2(2 * cxy, cxx - cyy);
        double dx = std::cos(theta), dy = std::sin(theta);
        lines[e] = {-dy, dx, -(-dy * mx + dx * my), true};
    }
    Pt refined[4];
    for (int i = 0; i < 4; ++i) {
        const Line& l1 = lines[(i + 3) % 4];
        const Line& l2 = lines[i];
        if (!l1.ok || !l2.ok) return;
        double det = l1.nx * l2.ny - l2.nx * l1.ny;
        if (std::fabs(det) < 1e-9) return;
        Pt p{(-l1.c * l2.ny + l2.c * l1.ny) / det, (-l1.nx * l2.c + l2.nx * l1.c) / det};
        if (std::hypot(p.x - quad[i].x, p.y - quad[i].y) > 4.0) return;  // ishonchsiz — eski burchak qoladi
        refined[i] = p;
    }
    for (int i = 0; i < 4; ++i) quad[i] = refined[i];
}

// To'rtburchak ichidagi 6x6 katakni o'qib, belgini tanib oladi.
bool decode_marker(const Gray& g, const Pt quad[4], Marker& out) {
    static const Pt unit[4] = {{0, 0}, {6, 0}, {6, 6}, {0, 6}};
    double best_score = 1e9;
    bool found = false;
    for (int start = 0; start < 4; ++start) {
        std::vector<Pt> src(unit, unit + 4), dst;
        for (int i = 0; i < 4; ++i) dst.push_back(quad[(start + i) % 4]);
        Homography h;
        if (!find_homography(src, dst, h)) return false;
        double cell[6][6];
        double lo = 255, hi = 0;
        for (int r = 0; r < 6; ++r) {
            for (int c = 0; c < 6; ++c) {
                double sum = 0;
                for (int sy = -1; sy <= 1; ++sy)
                    for (int sx = -1; sx <= 1; ++sx) {
                        Pt p = h.map({c + 0.5 + sx * 0.22, r + 0.5 + sy * 0.22});
                        sum += bilinear(g, p.x, p.y);
                    }
                cell[r][c] = sum / 9;
                lo = std::min(lo, cell[r][c]);
                hi = std::max(hi, cell[r][c]);
            }
        }
        if (hi - lo < 30) return false;
        double thr = (lo + hi) / 2;
        int border_errors = 0;
        for (int i = 0; i < 6; ++i) {
            border_errors += cell[0][i] > thr;
            border_errors += cell[5][i] > thr;
            if (i > 0 && i < 5) border_errors += (cell[i][0] > thr) + (cell[i][5] > thr);
        }
        if (border_errors > 2) return false;  // bu burchakdan boshlash chegarani o'zgartirmaydi
        uint16_t code = 0;
        double white_sum = 0;
        int white_n = 0;
        for (int r = 0; r < 4; ++r)
            for (int c = 0; c < 4; ++c) {
                bool white = cell[r + 1][c + 1] > thr;
                code = uint16_t((code << 1) | (white ? 1 : 0));
                if (white) white_sum += cell[r + 1][c + 1], ++white_n;
            }
        for (int id = 0; id < 4; ++id) {
            int dist = __builtin_popcount(unsigned(code ^ kMarkerCodes[id]));
            if (dist > 1) continue;
            double score = dist * 10 + border_errors;
            if (score < best_score) {
                best_score = score;
                found = true;
                out.id = id;
                out.errors = dist + border_errors;
                out.contrast = hi - lo;
                out.white = white_n ? white_sum / white_n : hi;
                for (int i = 0; i < 4; ++i) out.corners[i] = quad[(start + i) % 4];
            }
        }
    }
    if (!found) return false;
    out.center = {0, 0};
    double side = 0;
    for (int i = 0; i < 4; ++i) {
        out.center.x += out.corners[i].x / 4, out.center.y += out.corners[i].y / 4;
        side += std::hypot(out.corners[(i + 1) % 4].x - out.corners[i].x, out.corners[(i + 1) % 4].y - out.corners[i].y) / 4;
    }
    out.side = side;
    return true;
}

// Moslashuvchan chegaralash (mahalliy o'rtachadan to'qroq — "qora") va bog'langan qora sohalardan belgilar.
void find_candidates(const Gray& g, int window, std::vector<Marker>& markers) {
    const int w = g.w, h = g.h;
    std::vector<uint32_t> integral(size_t(w + 1) * (h + 1), 0);
    for (int y = 0; y < h; ++y) {
        uint32_t row = 0;
        for (int x = 0; x < w; ++x) {
            row += g.at(x, y);
            integral[size_t(y + 1) * (w + 1) + x + 1] = integral[size_t(y) * (w + 1) + x + 1] + row;
        }
    }
    const int half = window / 2;
    std::vector<uint8_t> dark(size_t(w) * h, 0);
    for (int y = 0; y < h; ++y) {
        int y0 = std::max(0, y - half), y1 = std::min(h, y + half + 1);
        for (int x = 0; x < w; ++x) {
            int x0 = std::max(0, x - half), x1 = std::min(w, x + half + 1);
            uint32_t sum = integral[size_t(y1) * (w + 1) + x1] - integral[size_t(y0) * (w + 1) + x1] -
                           integral[size_t(y1) * (w + 1) + x0] + integral[size_t(y0) * (w + 1) + x0];
            int area = (x1 - x0) * (y1 - y0);
            dark[size_t(y) * w + x] = uint32_t(g.at(x, y) * area + 7 * area) < sum;  // mean - 7 dan to'q
        }
    }

    const int min_side = 8;
    const int max_side = std::min(w, h) / 3;
    std::vector<int> stack;
    std::vector<Pt> boundary;
    std::vector<uint8_t> seen(size_t(w) * h, 0);
    for (int sy = 0; sy < h; ++sy) {
        for (int sx = 0; sx < w; ++sx) {
            size_t sidx = size_t(sy) * w + sx;
            if (!dark[sidx] || seen[sidx]) continue;
            stack.clear();
            boundary.clear();
            stack.push_back(int(sidx));
            seen[sidx] = 1;
            int minx = sx, maxx = sx, miny = sy, maxy = sy, count = 0;
            bool too_big = false;
            while (!stack.empty()) {
                int idx = stack.back();
                stack.pop_back();
                int x = idx % w, y = idx / w;
                ++count;
                minx = std::min(minx, x), maxx = std::max(maxx, x), miny = std::min(miny, y), maxy = std::max(maxy, y);
                if (maxx - minx > max_side || maxy - miny > max_side) too_big = true;
                bool edge = false;
                const int nx[4] = {x - 1, x + 1, x, x};
                const int ny[4] = {y, y, y - 1, y + 1};
                for (int k = 0; k < 4; ++k) {
                    if (nx[k] < 0 || ny[k] < 0 || nx[k] >= w || ny[k] >= h) {
                        edge = true;
                        continue;
                    }
                    size_t n = size_t(ny[k]) * w + nx[k];
                    if (!dark[n]) {
                        edge = true;
                        continue;
                    }
                    if (!seen[n]) seen[n] = 1, stack.push_back(int(n));
                }
                if (edge && !too_big) boundary.push_back({double(x), double(y)});
            }
            int bw = maxx - minx + 1, bh = maxy - miny + 1;
            if (too_big || bw < min_side || bh < min_side) continue;
            double aspect = double(bw) / bh;
            if (aspect < 0.33 || aspect > 3.0) continue;
            double fill = double(count) / (double(bw) * bh);
            if (fill < 0.25) continue;
            std::vector<Pt> hull = convex_hull(boundary);
            Pt quad[4];
            if (!hull_to_quad(hull, quad)) continue;
            std::vector<Pt> q(quad, quad + 4);
            double qa = polygon_area(q), ha = std::fabs(polygon_area(hull));
            if (qa <= 0 || ha <= 0 || qa / ha < 0.85) continue;  // to'rtburchakka o'xshamaydi
            double sides[4];
            for (int i = 0; i < 4; ++i) sides[i] = std::hypot(quad[(i + 1) % 4].x - quad[i].x, quad[(i + 1) % 4].y - quad[i].y);
            double smin = *std::min_element(sides, sides + 4), smax = *std::max_element(sides, sides + 4);
            if (smin < min_side * 0.8 || smin / smax < 0.3) continue;
            // Belgining tashqi chegarasi: chegara nuqtalari piksel markazida, haqiqiy chekka yarim piksel tashqarida.
            refine_quad(boundary, quad);
            Pt c{(quad[0].x + quad[2].x) / 2, (quad[0].y + quad[2].y) / 2};
            for (Pt& p : quad) {
                double dx = p.x - c.x, dy = p.y - c.y, len = std::hypot(dx, dy);
                if (len > 1e-6) p.x += dx / len * 0.7, p.y += dy / len * 0.7;
            }
            Marker m;
            if (decode_marker(g, quad, m)) markers.push_back(m);
        }
    }
}

std::vector<Marker> detect_markers(const Gray& g) {
    std::vector<Marker> all;
    int min_side = std::min(g.w, g.h);
    int windows[2] = {std::max(15, (min_side / 18) | 1), std::max(31, (min_side / 7) | 1)};
    for (int win : windows) find_candidates(g, win, all);
    // Har id dan eng yaxshisi
    std::vector<Marker> best(4);
    for (const Marker& m : all) {
        Marker& b = best[m.id];
        if (b.id < 0 || m.errors < b.errors || (m.errors == b.errors && m.side > b.side)) b = m;
    }
    std::vector<Marker> out;
    for (const Marker& m : best)
        if (m.id >= 0) out.push_back(m);
    // Bir-biriga juda yaqin yoki o'lchami boshqalardan keskin farq qiladigan (begona) belgilarni olib tashlash
    if (out.size() >= 2) {
        std::vector<double> sides;
        for (auto& m : out) sides.push_back(m.side);
        std::sort(sides.begin(), sides.end());
        double median = sides[sides.size() / 2];
        out.erase(std::remove_if(out.begin(), out.end(),
                                 [&](const Marker& m) { return m.side < median * 0.45 || m.side > median * 2.2; }),
                  out.end());
    }
    return out;
}

void marker_corners_mm(int id, Pt out[4]) {
    double cx = kMarkerCenters[id][0], cy = kMarkerCenters[id][1], h = kMarkerSize / 2;
    out[0] = {cx - h, cy - h};
    out[1] = {cx + h, cy - h};
    out[2] = {cx + h, cy + h};
    out[3] = {cx - h, cy + h};
}

// Varaqa (mm) -> rasm (piksel) o'zgartirishi; `scale` — markerlar topilgan rasmdan kirish rasmiga ko'paytiruvchi.
bool sheet_homography(const std::vector<Marker>& markers, double scale, Homography& h) {
    if (markers.size() < 3) return false;
    std::vector<Pt> src, dst;
    for (const Marker& m : markers) {
        Pt mm[4];
        marker_corners_mm(m.id, mm);
        for (int i = 0; i < 4; ++i) {
            src.push_back(mm[i]);
            dst.push_back({(m.corners[i].x + 0.5) * scale - 0.5, (m.corners[i].y + 0.5) * scale - 0.5});
        }
    }
    if (!find_homography(src, dst, h)) return false;
    // Tekshiruv: har belgi markazi ko'zda tutilgan joyga tushishi kerak (aks holda begona belgi aralashgan)
    for (const Marker& m : markers) {
        Pt p = h.map({kMarkerCenters[m.id][0], kMarkerCenters[m.id][1]});
        double err = std::hypot(p.x - m.center.x * scale, p.y - m.center.y * scale);
        if (err > std::max(3.0, m.side * scale * 0.35)) return false;
    }
    return true;
}

// Varaqa markazidagi 1 mm necha piksel ekanligi (kirish rasmida).
double px_per_mm(const Homography& h) {
    Pt c = h.map({kA4W / 2, kA4H / 2});
    Pt cx = h.map({kA4W / 2 + 1, kA4H / 2});
    Pt cy = h.map({kA4W / 2, kA4H / 2 + 1});
    return std::sqrt(std::fabs((cx.x - c.x) * (cy.y - c.y) - (cx.y - c.y) * (cy.x - c.x)));
}

// Aniqlik: belgi chekkasini kesib o'tuvchi kesimlarda qo'shni piksellarning eng katta farqi / kontrast.
// To'liq o'lchamdagi kadrda o'lchanadi (kichraytirilgan rasmda xiralik ko'rinmaydi). 0..1, ~0.35 dan yuqori — aniq.
double edge_sharpness(const Gray& full, const std::vector<Marker>& markers, double scale) {
    double total = 0;
    int n = 0;
    for (const Marker& m : markers) {
        Pt c{m.center.x * scale, m.center.y * scale};
        for (int e = 0; e < 4; ++e) {
            Pt a{m.corners[e].x * scale, m.corners[e].y * scale};
            Pt b{m.corners[(e + 1) % 4].x * scale, m.corners[(e + 1) % 4].y * scale};
            for (double t : {0.3, 0.5, 0.7}) {
                Pt p{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t};
                double dx = p.x - c.x, dy = p.y - c.y;
                // tomonga perpendikulyar, tashqariga
                double ex = b.x - a.x, ey = b.y - a.y, len = std::hypot(ex, ey);
                if (len < 1e-6) continue;
                double nx = ey / len, ny = -ex / len;
                if (nx * dx + ny * dy < 0) nx = -nx, ny = -ny;
                double lo = 255, hi = 0, step = 0, prev = -1;
                for (int k = -8; k <= 8; ++k) {
                    double v = bilinear(full, p.x + nx * k, p.y + ny * k);
                    lo = std::min(lo, v), hi = std::max(hi, v);
                    if (prev >= 0) step = std::max(step, std::fabs(v - prev));
                    prev = v;
                }
                if (hi - lo < 25) continue;
                total += step / (hi - lo);
                ++n;
            }
        }
    }
    return n ? total / n : 0.0;
}

// ---------------------------------------------------------------- JSON
struct Json {
    std::string s;
    void raw(const char* v) { s += v; }
    void num(double v, int digits = 3) {
        char buf[48];
        if (!std::isfinite(v)) v = 0;
        std::snprintf(buf, sizeof buf, "%.*f", digits, v);
        s += buf;
    }
    void integer(long long v) { s += std::to_string(v); }
    void str(const std::string& v) {
        s += '"';
        for (char ch : v) {
            if (ch == '"' || ch == '\\') s += '\\', s += ch;
            else if (static_cast<unsigned char>(ch) < 0x20) s += ' ';
            else s += ch;
        }
        s += '"';
    }
    char* release() {
        char* out = static_cast<char*>(std::malloc(s.size() + 1));
        if (out) std::memcpy(out, s.c_str(), s.size() + 1);
        return out;
    }
};

double now_ms() {
    using namespace std::chrono;
    return duration<double, std::milli>(steady_clock::now().time_since_epoch()).count();
}

// ---------------------------------------------------------------- jonli aniqlash
char* detect(const Gray& full, int work_max_side) {
    double t0 = now_ms();
    work_max_side = std::max(320, std::min(work_max_side, 1600));
    double s = std::min(1.0, double(work_max_side) / std::max(full.w, full.h));
    Gray work = downscale(full, s);
    double scale = double(full.w) / work.w;
    std::vector<Marker> markers = detect_markers(work);
    Json j;
    j.raw("{\"found\":");
    j.integer(long(markers.size()));
    j.raw(",\"markers\":[");
    double brightness = 0;
    for (size_t i = 0; i < markers.size(); ++i) {
        if (i) j.raw(",");
        j.raw("{\"id\":");
        j.integer(markers[i].id);
        j.raw(",\"x\":");
        j.num(markers[i].center.x * scale, 1);
        j.raw(",\"y\":");
        j.num(markers[i].center.y * scale, 1);
        j.raw(",\"side\":");
        j.num(markers[i].side * scale, 1);
        j.raw("}");
        brightness += markers[i].white / markers.size();
    }
    j.raw("],\"quad\":");
    Homography h;
    if (sheet_homography(markers, scale, h)) {
        const Pt corners[4] = {{0, 0}, {kA4W, 0}, {kA4W, kA4H}, {0, kA4H}};
        j.raw("[");
        for (int i = 0; i < 4; ++i) {
            Pt p = h.map(corners[i]);
            if (i) j.raw(",");
            j.raw("[");
            j.num(p.x, 1);
            j.raw(",");
            j.num(p.y, 1);
            j.raw("]");
        }
        j.raw("],\"px_per_mm\":");
        j.num(px_per_mm(h), 2);
    } else {
        j.raw("null,\"px_per_mm\":0");
    }
    j.raw(",\"sharpness\":");
    j.num(markers.empty() ? 0.0 : edge_sharpness(full, markers, scale), 3);
    j.raw(",\"brightness\":");
    j.num(brightness, 0);
    j.raw(",\"ms\":");
    j.num(now_ms() - t0, 1);
    j.raw("}");
    return j.release();
}

// ---------------------------------------------------------------- to'liq o'qish
Gray warp(const Gray& src, const Homography& h, double px_per_mm) {
    int w = int(kA4W * px_per_mm), hh = int(kA4H * px_per_mm);
    Gray out(w, hh);
    const double* m = h.m;
    const double step = 1.0 / px_per_mm;
    for (int y = 0; y < hh; ++y) {
        double my = (y + 0.5) * step, mx = 0.5 * step;
        // Qator bo'ylab surat va maxraj chiziqli o'zgaradi: har pikselda faqat bitta bo'lish
        double nx = m[0] * mx + m[1] * my + m[2], ny = m[3] * mx + m[4] * my + m[5], dz = m[6] * mx + m[7] * my + m[8];
        const double sx = m[0] * step, sy = m[3] * step, sz = m[6] * step;
        uint8_t* row = &out.d[size_t(y) * w];
        for (int x = 0; x < w; ++x) {
            double inv = 1.0 / dz;
            row[x] = uint8_t(std::lround(bilinear(src, nx * inv, ny * inv, 255.0)));
            nx += sx, ny += sy, dz += sz;
        }
    }
    return out;
}

// Kulrang morfologik kengaytirish/toraytirish kvadrat yadro bilan (ajraladigan: avval qator, keyin ustun).
// Server ellips yadro ishlatadi; fon yorug'ligini baholash uchun farqi sezilmaydi, tezligi esa ~10 marta yuqori.
Gray morph(const Gray& g, int radius, bool dilate) {
    Gray tmp(g.w, g.h), out(g.w, g.h);
    auto pick = [dilate](int a, int b) { return dilate ? std::max(a, b) : std::min(a, b); };
    for (int y = 0; y < g.h; ++y)
        for (int x = 0; x < g.w; ++x) {
            int v = g.at(x, y);
            for (int xx = std::max(0, x - radius); xx <= std::min(g.w - 1, x + radius); ++xx) v = pick(v, g.at(xx, y));
            tmp.at(x, y) = uint8_t(v);
        }
    for (int y = 0; y < g.h; ++y)
        for (int x = 0; x < g.w; ++x) {
            int v = tmp.at(x, y);
            for (int yy = std::max(0, y - radius); yy <= std::min(g.h - 1, y + radius); ++yy) v = pick(v, tmp.at(x, yy));
            out.at(x, y) = uint8_t(v);
        }
    return out;
}

Flt gaussian(const Gray& g, double sigma) {
    int r = std::max(1, int(std::ceil(sigma * 3)));
    std::vector<double> k(r * 2 + 1);
    double sum = 0;
    for (int i = -r; i <= r; ++i) sum += k[i + r] = std::exp(-(i * i) / (2 * sigma * sigma));
    for (double& v : k) v /= sum;
    Flt tmp(g.w, g.h), out(g.w, g.h);
    for (int y = 0; y < g.h; ++y)
        for (int x = 0; x < g.w; ++x) {
            double v = 0;
            for (int i = -r; i <= r; ++i) v += k[i + r] * g.at(std::clamp(x + i, 0, g.w - 1), y);
            tmp.d[size_t(y) * g.w + x] = float(v);
        }
    for (int y = 0; y < g.h; ++y)
        for (int x = 0; x < g.w; ++x) {
            double v = 0;
            for (int i = -r; i <= r; ++i) v += k[i + r] * tmp.at(x, std::clamp(y + i, 0, g.h - 1));
            out.d[size_t(y) * g.w + x] = float(v);
        }
    return out;
}

// Soya va notekis yorug'likni olib tashlaydi: natija 0..1, 1 = qog'oz (scanner.py: _flatten_illumination).
Flt flatten_illumination(const Gray& warped) {
    Gray small = downscale(warped, 0.25);
    // Server: 8 px/mm dagi varaqaning 1/4 qismida 21 piksellik yadro va sigma=5. Shu mm o'lchamlarida:
    double small_px_per_mm = kScanPxPerMm * small.w / warped.w;
    int radius = std::max(2, int(std::lround(5.25 * small_px_per_mm)));  // 21 px yadro / 2 px/mm = 10.5 mm diametr
    Gray closed = morph(morph(small, radius, true), radius, false);
    Flt bg = gaussian(closed, 2.5 * small_px_per_mm);
    Flt flat(warped.w, warped.h);
    double sx = double(small.w) / warped.w, sy = double(small.h) / warped.h;
    for (int y = 0; y < warped.h; ++y) {
        double fy = std::clamp((y + 0.5) * sy - 0.5, 0.0, small.h - 1.0);
        int y0 = int(fy), y1 = std::min(y0 + 1, small.h - 1);
        double ty = fy - y0;
        for (int x = 0; x < warped.w; ++x) {
            double fx = std::clamp((x + 0.5) * sx - 0.5, 0.0, small.w - 1.0);
            int x0 = int(fx), x1 = std::min(x0 + 1, small.w - 1);
            double tx = fx - x0;
            double a = bg.at(x0, y0) + (bg.at(x1, y0) - bg.at(x0, y0)) * tx;
            double b = bg.at(x0, y1) + (bg.at(x1, y1) - bg.at(x0, y1)) * tx;
            double back = std::max(1.0, a + (b - a) * ty);
            flat.d[size_t(y) * warped.w + x] = float(std::clamp(warped.at(x, y) / back, 0.0, 1.0));
        }
    }
    return flat;
}

struct Sampler {
    const Flt& flat;
    int radius;
    explicit Sampler(const Flt& f) : flat(f), radius(int(std::lround(kBubbleR * kSampleRadiusFactor * kScanPxPerMm))) {}
    double darkness(double mx, double my) const {
        int cx = int(std::lround(mx * kScanPxPerMm)), cy = int(std::lround(my * kScanPxPerMm));
        double sum = 0;
        int n = 0;
        for (int dy = -radius; dy <= radius; ++dy)
            for (int dx = -radius; dx <= radius; ++dx) {
                if (dx * dx + dy * dy > radius * radius) continue;
                int x = cx + dx, y = cy + dy;
                if (x < 0 || y < 0 || x >= flat.w || y >= flat.h) continue;
                sum += flat.at(x, y);
                ++n;
            }
        return n ? 1.0 - sum / n : 0.0;
    }
};

void answer_center(int question, int option, double& x, double& y) {
    int column = question / kRowsPerColumn, row = question % kRowsPerColumn;
    x = kAnsX0 + column * kAnsColumnStep + option * kAnsPitchX;
    y = kAnsY0 + row * kAnsPitchY;
}

struct QrPayload {
    bool ok = false;
    int exam_id = 0, variant = 0, questions = 0, options = 0;
    std::string student_code;
};

QrPayload parse_payload(const std::string& text) {
    QrPayload p;
    std::vector<std::string> parts;
    size_t start = 0;
    std::string t = text;
    while (!t.empty() && std::isspace(static_cast<unsigned char>(t.back()))) t.pop_back();
    while (true) {
        size_t pos = t.find(';', start);
        parts.push_back(t.substr(start, pos == std::string::npos ? std::string::npos : pos - start));
        if (pos == std::string::npos) break;
        start = pos + 1;
    }
    if (parts.size() != 6 || parts[0] != "EDU" + std::to_string(kLayoutVersion)) return p;
    auto to_int = [](const std::string& s, int& out) {
        if (s.empty() || s.size() > 9) return false;
        for (char c : s)
            if (c < '0' || c > '9') return false;
        out = std::atoi(s.c_str());
        return true;
    };
    if (!to_int(parts[1], p.exam_id) || !to_int(parts[2], p.variant) || !to_int(parts[3], p.questions) ||
        !to_int(parts[4], p.options))
        return p;
    if (p.questions < 1 || p.questions > kMaxQuestions || p.options < 2 || p.options > 5) return p;
    p.student_code = parts[5];
    p.ok = true;
    return p;
}

bool quirc_try(const Gray& img, QrPayload& out) {
    struct quirc* q = quirc_new();
    if (!q) return false;
    bool ok = false;
    if (quirc_resize(q, img.w, img.h) >= 0) {
        int w = 0, h = 0;
        uint8_t* buf = quirc_begin(q, &w, &h);
        std::memcpy(buf, img.d.data(), size_t(w) * h);
        quirc_end(q);
        int count = quirc_count(q);
        for (int i = 0; i < count && !ok; ++i) {
            struct quirc_code code;
            struct quirc_data data;
            quirc_extract(q, i, &code);
            quirc_decode_error_t err = quirc_decode(&code, &data);
            if (err == QUIRC_ERROR_DATA_ECC) {
                quirc_flip(&code);
                err = quirc_decode(&code, &data);
            }
            if (err) continue;
            QrPayload p = parse_payload(std::string(reinterpret_cast<const char*>(data.payload), size_t(data.payload_len)));
            if (p.ok) out = p, ok = true;
        }
    }
    quirc_destroy(q);
    return ok;
}

Gray crop(const Gray& g, int x0, int y0, int x1, int y1) {
    x0 = std::clamp(x0, 0, g.w), x1 = std::clamp(x1, 0, g.w), y0 = std::clamp(y0, 0, g.h), y1 = std::clamp(y1, 0, g.h);
    Gray out(std::max(1, x1 - x0), std::max(1, y1 - y0), 255);
    for (int y = y0; y < y1; ++y) std::memcpy(&out.d[size_t(y - y0) * out.w], &g.d[size_t(y) * g.w + x0], size_t(x1 - x0));
    return out;
}

Gray upscale2(const Gray& g) {
    Gray out(g.w * 2, g.h * 2);
    for (int y = 0; y < out.h; ++y)
        for (int x = 0; x < out.w; ++x)
            out.at(x, y) = uint8_t(std::lround(bilinear(g, std::clamp((x + 0.5) / 2 - 0.5, 0.0, g.w - 1.0),
                                                          std::clamp((y + 0.5) / 2 - 0.5, 0.0, g.h - 1.0))));
    return out;
}


// Keskinlashtirish (unsharp mask): xiraroq kadrdagi QR modullarini ajratadi.
Gray sharpen(const Gray& g, double sigma, double amount) {
    Flt blur = gaussian(g, sigma);
    Gray out(g.w, g.h);
    for (size_t i = 0; i < g.d.size(); ++i)
        out.d[i] = uint8_t(std::clamp(g.d[i] + amount * (g.d[i] - blur.d[i]), 0.0, 255.0));
    return out;
}

// QR ning joyi va o'lchami varaqada ma'lum: to'g'rilangan rasmda modul to'rini to'g'ridan-to'g'ri o'qib,
// faqat xatolarni tuzatish va dekodlashni quirc ga topshiramiz. Xira yoki siqilgan kadrda quirc ning o'z
// qidiruvidan ancha ishonchli. `box` — QR qutisi (piksel), `s` — px/mm.
bool grid_decode(const Gray& img, int bx0, int by0, int bx1, int by1, QrPayload& out) {
    bx0 = std::clamp(bx0, 0, img.w - 1), bx1 = std::clamp(bx1, 1, img.w), by0 = std::clamp(by0, 0, img.h - 1), by1 = std::clamp(by1, 1, img.h);
    std::vector<uint8_t> vals;
    for (int y = by0; y < by1; y += 2)
        for (int x = bx0; x < bx1; x += 2) vals.push_back(img.at(x, y));
    if (vals.size() < 100) return false;
    std::sort(vals.begin(), vals.end());
    double lo = vals[vals.size() * 3 / 100], hi = vals[vals.size() * 97 / 100];
    if (hi - lo < 30) return false;
    const double thr = (lo + hi) / 2;
    // Qora piksellar chegarasi: QR ning tashqi chegarasi (qidiruv kvadratlari tashqi cheti)
    int x0 = bx1, x1 = bx0, y0 = by1, y1 = by0;
    for (int y = by0; y < by1; ++y) {
        int dark = 0, first = -1, last = -1;
        for (int x = bx0; x < bx1; ++x)
            if (img.at(x, y) < thr) {
                ++dark;
                if (first < 0) first = x;
                last = x;
            }
        if (dark >= 3) y0 = std::min(y0, y), y1 = std::max(y1, y), x0 = std::min(x0, first), x1 = std::max(x1, last);
    }
    if (x1 - x0 < 40 || y1 - y0 < 40) return false;
    for (int size = 21; size <= 41; size += 4) {
        double cw = double(x1 - x0 + 1) / size, ch = double(y1 - y0 + 1) / size;
        if (cw < 2.5) break;
        for (double shift : {0.0, -0.08, 0.08}) {
            auto* code = new quirc_code();
            std::memset(code, 0, sizeof(quirc_code));
            code->size = size;
            for (int r = 0; r < size; ++r)
                for (int c = 0; c < size; ++c) {
                    double cx = x0 + (c + 0.5 + shift) * cw, cy = y0 + (r + 0.5 + shift) * ch, sum = 0;
                    for (int dy = -1; dy <= 1; ++dy)
                        for (int dx = -1; dx <= 1; ++dx) sum += bilinear(img, cx + dx * cw * 0.18, cy + dy * ch * 0.18);
                    if (sum / 9 < thr) {
                        int i = r * size + c;
                        code->cell_bitmap[i >> 3] |= uint8_t(1 << (i & 7));
                    }
                }
            quirc_data* data = new quirc_data();
            quirc_decode_error_t err = quirc_decode(code, data);
            bool ok = false;
            if (!err) {
                QrPayload p = parse_payload(std::string(reinterpret_cast<const char*>(data->payload), size_t(data->payload_len)));
                if (p.ok) out = p, ok = true;
            }
            delete data;
            delete code;
            if (ok) return true;
        }
    }
    return false;
}

// QR joyi kirish rasmidan to'g'ridan-to'g'ri 12 px/mm da olinadi (6 px/mm li varaqadan aniqroq).
QrPayload read_qr(const Gray& full, const Homography& h, const Gray& warped) {
    const double pad = 4.0, s = 12.0;
    int side = int((kQrSide + 2 * pad) * s);
    Gray region(side, side);
    for (int y = 0; y < side; ++y)
        for (int x = 0; x < side; ++x) {
            Pt p = h.map({kQrX - pad + (x + 0.5) / s, kQrY - pad + (y + 0.5) / s});
            region.at(x, y) = uint8_t(std::lround(bilinear(full, p.x, p.y, 255.0)));
        }
    QrPayload out;
    const int q0 = int(pad * s), q1 = int((pad + kQrSide) * s);
    if (grid_decode(region, q0, q0, q1, q1, out)) return out;
    if (quirc_try(region, out)) return out;
    // Kadr biroz xira bo'lsa: kuchayib boruvchi keskinlashtirish (sigma — 12 px/mm dagi pikselda)
    const double variants[3][2] = {{3.0, 1.5}, {2.0, 2.5}, {4.0, 3.0}};
    for (const auto& v : variants)
        if (quirc_try(sharpen(region, v[0], v[1]), out)) return out;
    // QR joyi biroz siljigan bo'lsa: varaqaning yuqori o'ng qismi
    Gray top = crop(warped, int(kA4W * kScanPxPerMm / 2), 0, warped.w, int(80 * kScanPxPerMm));
    if (quirc_try(top, out)) return out;
    quirc_try(upscale2(top), out);
    return out;
}

// stb_image_write: JPEG ni xotiraga yozish
void write_to_vector(void* context, void* data, int size) {
    auto* v = static_cast<std::vector<uint8_t>*>(context);
    auto* p = static_cast<uint8_t*>(data);
    v->insert(v->end(), p, p + size);
}

void encode_jpeg(const Gray& g, int quality, uint8_t** out, int* out_len) {
    if (!out || !out_len) return;
    *out = nullptr;
    *out_len = 0;
    std::vector<uint8_t> bytes;
    bytes.reserve(size_t(g.w) * g.h / 6);
    if (!stbi_write_jpg_to_func(write_to_vector, &bytes, g.w, g.h, 1, g.d.data(), quality)) return;
    *out = static_cast<uint8_t*>(std::malloc(bytes.size()));
    if (!*out) return;
    std::memcpy(*out, bytes.data(), bytes.size());
    *out_len = int(bytes.size());
}

char* error_json(const char* code, int markers_found, double ms) {
    Json j;
    j.raw("{\"ok\":false,\"error\":");
    j.str(code);
    j.raw(",\"markers_found\":");
    j.integer(markers_found);
    j.raw(",\"ms\":");
    j.num(ms, 1);
    j.raw("}");
    return j.release();
}

char* read_sheet(const Gray& full, int hint_questions, int hint_options, uint8_t** preview, int* preview_len,
                 uint8_t** upload, int* upload_len) {
    double t0 = now_ms();
    if (preview) *preview = nullptr, *preview_len = 0;
    if (upload) *upload = nullptr, *upload_len = 0;
    if (std::min(full.w, full.h) < 300) return error_json("bad_image", 0, now_ms() - t0);

    // Serverga yuboriladigan kadr (o'qib bo'lmasa ham — tahlil uchun foydali emas, shuning uchun faqat muvaffaqiyatda)
    double s = std::min(1.0, 1280.0 / std::max(full.w, full.h));
    Gray work = downscale(full, s);
    double scale = double(full.w) / work.w;
    std::vector<Marker> markers = detect_markers(work);
    Homography h;
    if (!sheet_homography(markers, scale, h)) return error_json("markers_not_found", int(markers.size()), now_ms() - t0);

    Gray warped = warp(full, h, kScanPxPerMm);
    QrPayload qr = read_qr(full, h, warped);
    int questions = qr.ok ? qr.questions : hint_questions;
    int options = qr.ok ? qr.options : (hint_options ? hint_options : 4);
    if (!qr.ok && (questions < 1 || questions > kMaxQuestions || options < 2 || options > 5))
        return error_json("qr_not_read", int(markers.size()), now_ms() - t0);

    Flt flat = flatten_illumination(warped);
    Sampler sampler(flat);

    Json flags;
    int flag_count = 0;
    auto add_flag = [&](const char* body) {
        if (flag_count++) flags.raw(",");
        flags.raw(body);
    };

    Json answers, darkness;
    answers.raw("[");
    darkness.raw("[");
    for (int qn = 0; qn < questions; ++qn) {
        if (qn) answers.raw(","), darkness.raw(",");
        answers.raw("[");
        darkness.raw("[");
        std::vector<int> marked, doubtful;
        for (int o = 0; o < options; ++o) {
            double x, y;
            answer_center(qn, o, x, y);
            double v = sampler.darkness(x, y);
            if (o) darkness.raw(",");
            darkness.num(v, 3);
            if (v >= kFillThreshold) marked.push_back(o);
            else if (v >= kEmptyThreshold) doubtful.push_back(o);
        }
        for (size_t i = 0; i < marked.size(); ++i) {
            if (i) answers.raw(",");
            answers.integer(marked[i]);
        }
        answers.raw("]");
        darkness.raw("]");
        const std::vector<int>* list = nullptr;
        const char* type = nullptr;
        if (!doubtful.empty()) list = &doubtful, type = "uncertain";
        else if (marked.size() > 1) list = &marked, type = "multiple";
        if (type) {
            Json f;
            f.raw("{\"question\":");
            f.integer(qn + 1);
            f.raw(",\"type\":\"");
            f.raw(type);
            f.raw("\",\"options\":[");
            for (size_t i = 0; i < list->size(); ++i) {
                if (i) f.raw(",");
                f.integer((*list)[i]);
            }
            f.raw("]}");
            add_flag(f.s.c_str());
        }
    }
    answers.raw("]");
    darkness.raw("]");

    std::string code;
    const char* source = nullptr;
    if (qr.ok && !qr.student_code.empty()) {
        code = qr.student_code, source = "qr";
    } else {
        bool ok = true;
        for (int col = 0; col < kIdDigits && ok; ++col) {
            int mark = -1, marks = 0, doubts = 0;
            for (int digit = 0; digit < 10; ++digit) {
                double v = sampler.darkness(kIdX0 + col * kIdPitchX, kIdY0 + digit * kIdPitchY);
                if (v >= kFillThreshold) mark = digit, ++marks;
                else if (v >= kEmptyThreshold) ++doubts;
            }
            if (marks != 1 || doubts) ok = false;
            else code += char('0' + mark);
        }
        if (ok) source = "bubbles";
        else code.clear();
    }
    if (code.empty()) add_flag("{\"question\":null,\"type\":\"student_code_unreadable\"}");
    if (!qr.ok) add_flag("{\"question\":null,\"type\":\"qr_not_read\"}");
    if (markers.size() < 4) add_flag("{\"question\":null,\"type\":\"marker_missing\"}");
    double density = px_per_mm(h);
    if (density < 3.0) add_flag("{\"question\":null,\"type\":\"low_resolution\"}");

    double sharp = edge_sharpness(full, markers, scale);

    Json j;
    j.raw("{\"ok\":true,\"layout_version\":");
    j.integer(kLayoutVersion);
    j.raw(",\"exam_id\":");
    if (qr.ok) j.integer(qr.exam_id); else j.raw("null");
    j.raw(",\"variant\":");
    if (qr.ok) j.integer(qr.variant); else j.raw("null");
    j.raw(",\"questions\":");
    j.integer(questions);
    j.raw(",\"options\":");
    j.integer(options);
    j.raw(",\"student_code\":");
    if (code.empty()) j.raw("null"); else j.str(code);
    j.raw(",\"student_code_source\":");
    if (source) j.str(source); else j.raw("null");
    j.raw(",\"answers\":");
    j.raw(answers.s.c_str());
    j.raw(",\"darkness\":");
    j.raw(darkness.s.c_str());
    j.raw(",\"flags\":[");
    j.raw(flags.s.c_str());
    j.raw("],\"needs_review\":");
    j.raw(flag_count ? "true" : "false");
    j.raw(",\"markers_found\":");
    j.integer(long(markers.size()));
    j.raw(",\"px_per_mm\":");
    j.num(density, 2);
    j.raw(",\"sharpness\":");
    j.num(sharp, 3);
    j.raw(",\"preview_px_per_mm\":");
    j.num(kPreviewPxPerMm, 1);

    if (preview) encode_jpeg(downscale(warped, kPreviewPxPerMm / kScanPxPerMm), 82, preview, preview_len);
    if (upload) {
        double us = std::min(1.0, double(kUploadMaxSide) / std::max(full.w, full.h));
        encode_jpeg(us < 1.0 ? downscale(full, us) : full, 88, upload, upload_len);
    }
    j.raw(",\"ms\":");
    j.num(now_ms() - t0, 1);
    j.raw("}");
    return j.release();
}

}  // namespace

extern "C" {

OMR_EXPORT char* omr_detect(const uint8_t* gray, int width, int height, int stride, int work_max_side) {
    if (!gray || width < 32 || height < 32 || stride < width) return error_json("bad_image", 0, 0);
    return detect(from_buffer(gray, width, height, stride), work_max_side);
}

OMR_EXPORT char* omr_read_gray(const uint8_t* gray, int width, int height, int stride, int questions, int options,
                               uint8_t** preview_jpeg, int* preview_len, uint8_t** upload_jpeg, int* upload_len) {
    if (!gray || width < 32 || height < 32 || stride < width) return error_json("bad_image", 0, 0);
    return read_sheet(from_buffer(gray, width, height, stride), questions, options, preview_jpeg, preview_len,
                      upload_jpeg, upload_len);
}

OMR_EXPORT char* omr_read_encoded(const uint8_t* data, int length, int questions, int options,
                                  uint8_t** preview_jpeg, int* preview_len, uint8_t** upload_jpeg, int* upload_len) {
    int w = 0, h = 0, channels = 0;
    uint8_t* pixels = data && length > 0 ? stbi_load_from_memory(data, length, &w, &h, &channels, 1) : nullptr;
    if (!pixels) return error_json("bad_image", 0, 0);
    Gray g(w, h);
    std::memcpy(g.d.data(), pixels, size_t(w) * h);
    stbi_image_free(pixels);
    return read_sheet(g, questions, options, preview_jpeg, preview_len, upload_jpeg, upload_len);
}

OMR_EXPORT int omr_encode_jpeg(const uint8_t* gray, int width, int height, int stride, int max_side, int quality,
                               uint8_t** jpeg, int* jpeg_len) {
    if (!gray || !jpeg || !jpeg_len || width < 1 || height < 1 || stride < width) return 0;
    Gray g = from_buffer(gray, width, height, stride);
    double s = max_side > 0 ? std::min(1.0, double(max_side) / std::max(width, height)) : 1.0;
    encode_jpeg(s < 1.0 ? downscale(g, s) : g, std::clamp(quality, 30, 100), jpeg, jpeg_len);
    return *jpeg_len;
}

OMR_EXPORT void omr_free(void* pointer) { std::free(pointer); }

OMR_EXPORT int omr_layout_version(void) { return kLayoutVersion; }

}  // extern "C"
