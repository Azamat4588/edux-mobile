"""Telefon o'quvchisini (C++) serverdagi o'quvchi (Python/OpenCV) va haqiqiy javoblar bilan solishtiradi.

    python3 tool/compare.py <omr_cli> <omr-service papkasi> [soni]

Sun'iy "telefon rasmlari" omr-service/tests/synth.py bilan yasaladi: perspektiva, burilish, soya, xiralik,
shovqin, JPEG siqish; "qattiq" rejimda — kuchliroq.
"""
import json, subprocess, sys, tempfile, os, time
import numpy as np

cli, service = sys.argv[1], sys.argv[2]
count = int(sys.argv[3]) if len(sys.argv) > 3 else 40
sys.path.insert(0, service)
sys.path.insert(0, os.path.join(service, "tests"))
from omr.layout import SheetSpec  # noqa: E402
from omr.scanner import scan_image  # noqa: E402
import synth  # noqa: E402

specs = [SheetSpec(30, 4), SheetSpec(45, 5), SheetSpec(90, 4), SheetSpec(12, 3)]
stats = {k: {"sheets": 0, "read": 0, "q": 0, "dark_ok": 0, "wrong": 0, "faint_marked": 0, "code_ok": 0, "review": 0,
             "auto_wrong": 0, "ms": 0.0} for k in ("device", "server")}
agree = both_auto = 0
tmp = tempfile.mkdtemp()
for i in range(count):
    rng = np.random.default_rng(1000 + i)
    spec = specs[i % len(specs)]
    harsh = i % 3 == 2
    truth = synth.make_truth(rng, spec)
    photo = synth.make_photo(rng, spec, truth, code_in_qr=(i % 2 == 0), harsh=harsh)
    path = os.path.join(tmp, f"{i}.jpg")
    open(path, "wb").write(photo)
    t = time.time()
    server = scan_image(photo)
    server_ms = (time.time() - t) * 1000
    device = json.loads(subprocess.check_output([cli, "read", path]).decode())
    results = {"device": device, "server": server}
    for name, r in results.items():
        s = stats[name]
        s["sheets"] += 1
        s["ms"] += device.get("ms", 0) if name == "device" else server_ms
        if not r.get("ok"):
            print(f"#{i} {name}: {r.get('error')} harsh={harsh}")
            continue
        s["read"] += 1
        s["review"] += bool(r["needs_review"])
        s["code_ok"] += r.get("student_code") == truth["student_code"]
        sheet_wrong = 0
        for q in range(spec.questions):
            got = set(r["answers"][q])
            dark = set(truth["dark"][q])
            faint = set(truth["faint"][q])
            s["q"] += 1
            s["dark_ok"] += got >= dark
            s["faint_marked"] += bool(got & faint)
            if got != dark:
                s["wrong"] += 1
                sheet_wrong += 1
        if not r["needs_review"] and (sheet_wrong or r.get("student_code") != truth["student_code"]):
            s["auto_wrong"] += 1
            print(f"#{i} {name}: AUTO-GRADED WRONG ({sheet_wrong} questions) harsh={harsh}")
    if device.get("ok") and server.get("ok"):
        if device["answers"] == server["answers"] and device.get("student_code") == server.get("student_code"):
            agree += 1
        if not device["needs_review"] and not server["needs_review"]:
            both_auto += 1

for name, s in stats.items():
    q = max(1, s["q"])
    print(f"{name:7} read {s['read']}/{s['sheets']}  dark-found {s['dark_ok']/q:.4f}  answer-exact {(q-s['wrong'])/q:.4f}  "
          f"faint-as-mark {s['faint_marked']}  code-ok {s['code_ok']}  needs-review {s['review']}  auto-wrong {s['auto_wrong']}  "
          f"avg {s['ms']/max(1,s['sheets']):.0f} ms")
print(f"identical answers+code: {agree}/{count}; both auto-graded: {both_auto}")
