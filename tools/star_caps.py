"""Hard design caps for campaign Star Challenges (shared by every star generator / refiner).

Mirrors StarChallenges.MAX_HEIGHT_CAP_M / SPEED_CAP_KMH in game/scripts/campaign/star_challenges.gd; the game
rejects stars.json values above them on load. Load with runpy (tools are run with `python -I`):
    caps = runpy.run_path(str(Path(__file__).with_name('star_caps.py')))
"""

MAX_HEIGHT_CAP_M = 30     # MAX_HEIGHT_M.m: 30 m above the local ground is already difficult
SPEED_CAP_KMH = 100       # SPEED_TARGET.kmh
HARD_CAPS = {'MAX_HEIGHT_M': ('m', MAX_HEIGHT_CAP_M), 'SPEED_TARGET': ('kmh', SPEED_CAP_KMH)}


def within_caps(ch):
    cap = HARD_CAPS.get(ch.get('type'))
    return cap is None or float(ch.get(cap[0], 0)) <= cap[1]


def clamp(ch):
    """Returns the challenge with any capped parameter lowered to its cap (copy)."""
    c = dict(ch)
    cap = HARD_CAPS.get(c.get('type'))
    if cap and float(c.get(cap[0], 0)) > cap[1]:
        c[cap[0]] = cap[1]
    return c


def speed_for_round(r, rounds=100):
    """Gentle rise 80 -> 100 km/h over the campaign, multiples of 5, never above the cap."""
    v = 80 + 20 * (r - 1) / max(rounds - 1, 1)
    return int(min(SPEED_CAP_KMH, 5 * round(v / 5)))


def height_for_round(r, first=41, last=100):
    """MAX_HEIGHT_M appears from r41: 24 m rising to the 30 m cap by the last rounds."""
    v = 24 + 6 * (r - first) / max(last - first, 1)
    return int(min(MAX_HEIGHT_CAP_M, max(1, round(v))))
