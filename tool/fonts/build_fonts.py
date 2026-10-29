# EduX mobil 3.9 (dizayn v3 «Koshin»): Commissioner (sarlavha, raqam) va Onest (matn) — o'zgaruvchan woff2 dan statik TTF
# (lotin + kirill to'plamlari birlashtiriladi va uz/ru/en uchun qisqartiriladi — APK hajmi).
# Manbalar: backend resources/fonts (commissioner-*), backend node_modules/@fontsource-variable/onest/files (onest-*).
# Ishga tushirish: EDUX=../edux python3 tool/fonts/build_fonts.py assets/fonts  (fonttools, brotli)
import io
import os
import sys

from fontTools import merge, subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

EDUX = os.environ.get('EDUX', '../edux')
SOURCES = {
    'commissioner': f'{EDUX}/resources/fonts',
    'onest': f'{EDUX}/node_modules/@fontsource-variable/onest/files',
}
OUT = sys.argv[1]
TMP = os.environ.get('TMPDIR', '/tmp')
# lotin (uz/en, o'zbek ʻ U+02BB), kirill (ru, uz-kirill: Ў Қ Ғ Ҳ), tinish belgilari, valyuta, strelkalar
UNI = list(range(0x20, 0x7F)) + list(range(0xA0, 0x180)) + [0x18F, 0x259, 0x2BB, 0x2BC, 0x2C6, 0x2DA, 0x2DC] + list(range(0x300, 0x305)) + \
    list(range(0x400, 0x4B4)) + list(range(0x4B6, 0x4BC)) + list(range(0x4D8, 0x4DA)) + list(range(0x4E8, 0x4EA)) + \
    list(range(0x2010, 0x2028)) + list(range(0x2030, 0x203B)) + \
    [0x2044, 0x20AC, 0x20BD, 0x2116, 0x2122, 0x2190, 0x2191, 0x2192, 0x2193, 0x2212, 0x2026, 0x00D7, 0x2248, 0x2260, 0x2264, 0x2265, 0x221E]


def instance(family, weight):
    parts = []
    for part in ['latin', 'latin-ext', 'cyrillic', 'cyrillic-ext']:
        font = TTFont(f'{SOURCES[family]}/{family}-{part}-wght-normal.woff2')
        font.flavor = None
        static = instancer.instantiateVariableFont(font, {'wght': weight}, updateFontNames=False)
        buffer = io.BytesIO()
        static.save(buffer)
        path = f'{TMP}/_{family}_{part}_{weight}.ttf'
        with open(path, 'wb') as handle:
            handle.write(buffer.getvalue())
        parts.append(path)
    return merge.Merger().merge(parts)


def shrink(font, path):
    options = subset.Options()
    options.layout_features = ['*']
    options.name_IDs = ['*']
    options.notdef_outline = True
    options.glyph_names = False
    options.hinting = False
    options.desubroutinize = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=UNI)
    subsetter.subset(font)
    font.save(path)
    print(path, os.path.getsize(path))


if __name__ == '__main__':
    for family, name, weights in [('commissioner', 'Commissioner', [400, 600, 700, 800]), ('onest', 'Onest', [400, 500, 600, 700, 800])]:
        for weight in weights:
            shrink(instance(family, weight), f'{OUT}/{name}-{weight}.ttf')
