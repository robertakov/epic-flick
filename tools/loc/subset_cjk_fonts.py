"""v34: bundle CJK glyph fallbacks. Subsets Noto Sans SC / JP / KR (SIL Open Font License 1.1) to exactly the
characters used by game/locale/strings.json (+ ASCII, digits, common punctuation, language endonyms) and writes
game/assets/fonts/noto_sans_{sc,jp,kr}_subset.otf. Re-run after adding / changing translations:
    python tools/loc/build_strings.py && python tools/loc/subset_cjk_fonts.py [noto_dir]
(needs fontTools). The localization audit test fails if a used glyph is missing from every bundled font.
"""
import json, os, sys
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_DIR = sys.argv[1] if len(sys.argv) > 1 else r"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\shareplay\resources"
OUT_DIR = os.path.join(ROOT, "game", "assets", "fonts")
FONTS = {"sc": "notosanssc-regular.otf", "jp": "notosansjp-regular.otf", "kr": "notosanskr-regular.otf"}
ENDONYMS = "Русский English Español Português (Brasil) Français Deutsch Italiano Polski Türkçe Українська 中文（简体） 日本語 한국어"


def is_cjk(ch):
    o = ord(ch)
    return (0x2E80 <= o <= 0x9FFF or 0xAC00 <= o <= 0xD7AF or 0x1100 <= o <= 0x11FF or 0x3130 <= o <= 0x318F
            or 0xF900 <= o <= 0xFAFF or 0xFF00 <= o <= 0xFFEF or 0x3000 <= o <= 0x303F)


def main():
    data = json.load(open(os.path.join(ROOT, "game", "locale", "strings.json"), encoding="utf-8"))
    chars = set(ENDONYMS)
    for row in data["strings"].values():
        for text in row.values():
            chars.update(text)
    cjk = sorted(c for c in chars if is_cjk(c))
    base = [chr(c) for c in range(0x20, 0x7F)] + list("·•—–…«»“”„‘’★☆✓↻↺▶◀●○×≤≥%")
    text = "".join(sorted(set(cjk + base)))
    os.makedirs(OUT_DIR, exist_ok=True)
    for tag, fn in FONTS.items():
        src = os.path.join(SRC_DIR, fn)
        out = os.path.join(OUT_DIR, f"noto_sans_{tag}_subset.otf")
        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.name_languages = ["*"]
        opts.notdef_outline = True
        opts.drop_tables += ["DSIG"]
        font = TTFont(src)
        sub = subset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        font.save(out)
        have = set(chr(c) for c in TTFont(out).getBestCmap())
        missing = [c for c in cjk if c not in have]
        print(f"{tag}: {os.path.getsize(out) // 1024} KB, {len(have)} glyph codes, CJK used {len(cjk)}, missing here {len(missing)}")
    print("OFL: see game/assets/fonts/OFL_NOTICE.txt")


if __name__ == "__main__":
    main()
