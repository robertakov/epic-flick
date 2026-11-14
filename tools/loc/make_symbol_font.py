"""v34: tiny self-made glyph font for the UI arrows that neither Impact / Roboto nor the Noto CJK subsets contain:
U+21BB (clockwise open circle arrow) and U+21BA (counter-clockwise). Drawn procedurally (own work, no licence
constraints) -> game/assets/fonts/epic_symbols.ttf, used as the last UI font fallback (L.fallback_fonts()).
"""
import math, os
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "fonts", "epic_symbols.ttf")
EM, ADV = 1000, 860
CX, CY, R_OUT, R_IN = 430, 330, 330, 215


def arrow(mirror):
    pen = TTGlyphPen(None)
    a0, a1 = math.radians(100), math.radians(100 + 290)   # open at the top-left, ends at the top-right
    steps = 36
    outer = [(CX + R_OUT * math.cos(a0 + (a1 - a0) * i / steps), CY + R_OUT * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]
    inner = [(CX + R_IN * math.cos(a0 + (a1 - a0) * i / steps), CY + R_IN * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]
    # arrowhead at the a0 end, pointing along the clockwise direction of travel
    mid_r = (R_OUT + R_IN) / 2
    tip_a = a0 - math.radians(38)
    tip = (CX + mid_r * math.cos(tip_a), CY + mid_r * math.sin(tip_a))
    head_out = (CX + (R_OUT + 95) * math.cos(a0), CY + (R_OUT + 95) * math.sin(a0))
    head_in = (CX + (R_IN - 95) * math.cos(a0), CY + (R_IN - 95) * math.sin(a0))
    pts = [head_out, tip, head_in] + inner + outer[::-1]
    if mirror:
        pts = [(2 * CX - x, y) for x, y in pts]
        pts = pts[::-1]
    pts = [(int(round(x)), int(round(y))) for x, y in pts]
    # TrueType outer contours run clockwise
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if area > 0:
        pts = pts[::-1]
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()
    return pen.glyph()


def main():
    fb = FontBuilder(EM, isTTF=True)
    names = [".notdef", "cw", "ccw"]
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({0x21BB: "cw", 0x21BA: "ccw"})
    empty = TTGlyphPen(None).glyph()
    fb.setupGlyf({".notdef": empty, "cw": arrow(False), "ccw": arrow(True)})
    fb.setupHorizontalMetrics({n: (ADV, 0) for n in names})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "EpicSymbols", "styleName": "Regular"})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupPost()
    fb.save(OUT)
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
