// Sinov vositasi: rasmni o'qiydi va JSON chiqaradi. Kompyuterda yig'iladi (tool/test.sh).
//   omr_cli read <rasm> [savollar variantlar] [preview.jpg]
//   omr_cli detect <rasm> [work_max_side]
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

#include "../src/edux_omr.h"

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: omr_cli read|detect <image> ...\n");
        return 2;
    }
    std::ifstream in(argv[2], std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (std::strcmp(argv[1], "detect") == 0) {
        // Faqat kulrang PGM (P5) qabul qilinadi: kamera Y tekisligiga o'xshash
        int w, h, maxv, offset = 0;
        if (std::sscanf(reinterpret_cast<const char*>(bytes.data()), "P5 %d %d %d%n", &w, &h, &maxv, &offset) != 3) return 3;
        char* json = omr_detect(bytes.data() + offset + 1, w, h, w, argc > 3 ? std::atoi(argv[3]) : 800);
        std::puts(json);
        omr_free(json);
        return 0;
    }
    if (std::strcmp(argv[1], "readpgm") == 0) {
        int w, h, maxv, offset = 0;
        if (std::sscanf(reinterpret_cast<const char*>(bytes.data()), "P5 %d %d %d%n", &w, &h, &maxv, &offset) != 3) return 3;
        uint8_t* preview = nullptr;
        int preview_len = 0;
        char* json = omr_read_gray(bytes.data() + offset + 1, w, h, w, 0, 0, &preview, &preview_len, nullptr, nullptr);
        std::puts(json);
        omr_free(json);
        omr_free(preview);
        return 0;
    }
    uint8_t *preview = nullptr, *upload = nullptr;
    int preview_len = 0, upload_len = 0;
    char* json = omr_read_encoded(bytes.data(), int(bytes.size()), argc > 3 ? std::atoi(argv[3]) : 0,
                                  argc > 4 ? std::atoi(argv[4]) : 0, &preview, &preview_len, &upload, &upload_len);
    std::puts(json);
    if (argc > 5 && preview) std::ofstream(argv[5], std::ios::binary).write(reinterpret_cast<char*>(preview), preview_len);
    omr_free(json);
    omr_free(preview);
    omr_free(upload);
    return 0;
}
