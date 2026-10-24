# EduX mobil: Golos Text va Literata (backend resources/fonts woff2, o'zgaruvchan) -> statik TTF (merge + subset).
# Ishga tushirish: EDUX_FONTS=../edux/resources/fonts python3 tool/fonts/build_fonts.py assets/fonts  (fonttools, brotli)
import sys, os, io
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import merge, subset

SRC=os.environ.get('EDUX_FONTS', '../edux/resources/fonts')  # backend resources/fonts
OUT=sys.argv[1]
# lotin (uz/en), kirill (ru, uz-kirill), tinish belgilari, valyuta, strelkalar
UNI = list(range(0x20,0x7F))+list(range(0xA0,0x180))+[0x18F,0x259,0x2BB,0x2BC,0x2C6,0x2DA,0x2DC]+list(range(0x300,0x305))+\
      list(range(0x400,0x4B4))+list(range(0x4B6,0x4BC))+list(range(0x4D8,0x4DA))+list(range(0x4E8,0x4EA))+\
      list(range(0x2010,0x2028))+list(range(0x2030,0x203B))+[0x2044,0x20AC,0x20BD,0x2116,0x2122,0x2190,0x2191,0x2192,0x2193,0x2212,0x2026,0x00D7,0x2248,0x2260,0x2264,0x2265,0x221E]

def instance(family, weight):
    parts=[]
    for sub in ['latin','latin-ext','cyrillic','cyrillic-ext']:
        f=TTFont(f'{SRC}/{family}-{sub}-wght-normal.woff2')
        f.flavor=None
        axes={a.axisTag:(a.minValue,a.defaultValue,a.maxValue) for a in f['fvar'].axes}
        loc={'wght':weight}
        for tag,(mn,df,mx) in axes.items():
            if tag!='wght': loc[tag]=df
        st=instancer.instantiateVariableFont(f, loc, updateFontNames=False)
        buf=io.BytesIO(); st.save(buf); buf.seek(0)
        p=f'/tmp/_{family}_{sub}_{weight}.ttf'
        open(p,'wb').write(buf.getvalue()); parts.append(p)
    m=merge.Merger()
    font=m.merge(parts)
    return font

def sub(font, path):
    opts=subset.Options(); opts.layout_features=['*']; opts.name_IDs=['*']; opts.notdef_outline=True; opts.glyph_names=False
    opts.hinting=False; opts.desubroutinize=True
    s=subset.Subsetter(opts); s.populate(unicodes=UNI); s.subset(font)
    font.save(path); print(path, os.path.getsize(path))

if __name__=='__main__':
    for family,name,weights in [('golos','GolosText',[400,500,600,700]),('literata','Literata',[500,600,700])]:
        for w in weights:
            sub(instance(family,w), f'{OUT}/{name}-{w}.ttf')
    # mavjud shriftlar ham shu to'plamga qisqartiriladi
    for fam in ['Onest','Manrope','Nunito']:
        for w in [400,600,800]:
            p=f'{OUT}/{fam}-{w}.ttf'
            if os.path.exists(p): sub(TTFont(p), p)
