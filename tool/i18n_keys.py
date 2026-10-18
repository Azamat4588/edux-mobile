"""Ilovadagi tarjima kalitlarini yig'adi va lug'atlarda yo'qlarini chiqaradi.

    python3 tool/i18n_keys.py            # yo'q kalitlar ro'yxati
    python3 tool/i18n_keys.py --json     # JSON ko'rinishida
Kalitlar: tr('...') chaqiriqlari va *Labels / paymentMethods / kun-oy nomlari ro'yxatlaridagi matnlar.
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
STR = r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")"""

def unescape(s):
    return s.replace("\\'", "'").replace('\\"', '"').replace('\\$', '$').replace('\\n', '\n').replace('\\\\', '\\')

keys = set()
for path in (root / 'lib').rglob('*.dart'):
    text = path.read_text(encoding='utf-8')
    for m in re.finditer(r"\btr\(\s*" + STR, text):
        keys.add(unescape(m.group(1) if m.group(1) is not None else m.group(2)))
    # Yorliq lug'atlari va ro'yxatlar
    for block in re.finditer(r"(?:Labels|paymentMethods|labels|_weekdays|_months)\s*=\s*(?:<[^>]*>)?\s*[\[{](.*?)[\]}];", text, re.S):
        for m in re.finditer(r":\s*" + STR + r"|^\s*" + STR + r"\s*,", block.group(1), re.M):
            value = next((g for g in m.groups() if g is not None), None)
            if value: keys.add(unescape(value))
        if '_weekdays' in block.group(0) or '_months' in block.group(0):
            for m in re.finditer(STR, block.group(1)):
                keys.add(unescape(m.group(1) if m.group(1) is not None else m.group(2)))

ru = json.loads((root / 'assets/i18n/ru.json').read_text(encoding='utf-8'))
en = json.loads((root / 'assets/i18n/en.json').read_text(encoding='utf-8'))
missing = sorted(k for k in keys if k not in ru or k not in en)
if '--json' in sys.argv:
    print(json.dumps(missing, ensure_ascii=False, indent=0))
else:
    print(f"{len(keys)} ta kalit, lug'atda yo'q: {len(missing)}")
    for k in missing: print(' -', repr(k))
sys.exit(1 if missing else 0)
