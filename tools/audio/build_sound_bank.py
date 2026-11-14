"""v27 sound bank: physical / mechanical / playful sound design for EpicShalban (dev tool, deterministic).

Replaces the v24 fully-procedural bank (one template re-pitched per robot, sine-beep voices, near-duplicate variants,
FFmpeg's experimental Vorbis encoder). Architecture (GameAudio, bank.json schema, families, profiles, tiers,
cooldowns, loops) is unchanged; only the samples and their mastering change.

Sources
  art/audio/source_library/v18_samurai_sourced/*   real recorded material derived from the user's original source
  art/audio/source_library/v18_common_sourced/*    files (v18 segmentation, restored from git 14f4661917)
  -> used as the PHYSICAL base layer (whooshes, spring bounces, impacts, snaps, shouts, mechanical UI clicks,
     charge crackle, jet flight, the authentic Wilhelm scream).
Design layers (numpy) give every robot its own voice on top of that base:
  tin     Rastabot   light, loose, rattly tin: hollow can partials + bolt rattle tails, relaxed lazy pitch drop
  hopper  Kengurobot spring-heavy, elastic: long dispersive "boing" twangs, extra bounce, quick upward energy
  heavy   Sumobot    deep, weighty: base pitched down, sub thump, cast-iron body, slow heavy hydraulics
  rocket  Chronobot  clockwork: escapement tick-tocks, ratchets, winding, small brass bell partials
  samurai Samurobot  steel & lacquer: the original sourced samurai material + blade-ring shimmer (inharmonic steel),
                     lacquered-armour clacks and tight crisp springs (no stock "Asian" instruments)
Rewards / UI: mechanical clicks from the sourced UI set; rewards are wind-up music-box tines (vintage toy universe).

Mastering: 44.1 kHz mono 16-bit WAV (Godot imports as QOA). Every clip is loudness-normalised (BS.1770 K-weighted,
one-shot measure over the active part) to its family target; variations in a family are kept within +-0.75 LU; peak
ceiling -1 dBFS via a look-ahead limiter; no clipping; tails faded; durations capped per family; near-duplicate
variations (spectral fingerprint corr > .985) are regenerated.
usage: python -B -I tools/audio/build_sound_bank.py
"""
from pathlib import Path
import json, math, sys, hashlib, shutil
import numpy as np
from scipy.signal import butter, sosfilt, resample_poly
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).parent))
from audio_metrics import decode, loudness, features  # noqa

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "art/audio/source_library"
OUT = ROOT / "game/assets/audio"
SR = 44100
ROBOTS = ["tin", "hopper", "heavy", "rocket", "samurai"]
EVENTS = ["launch", "spring", "body", "head", "limb", "voice", "head_launch", "rolling"]
VARIANTS = {"launch": 6, "spring": 8, "body": 8, "head": 6, "limb": 6, "voice": 6, "head_launch": 5, "rolling": 1}
TARGET = {"launch": -15.0, "spring": -17.0, "body": -15.0, "head": -15.0, "limb": -14.0, "voice": -16.0,
          "head_launch": -14.5, "rolling": -22.0,
          "click": -23.0, "back": -23.5, "browse": -25.0, "confirm": -21.0, "module_install": -20.0,
          "module_remove": -20.5, "countdown": -20.0, "go": -17.5, "coin": -19.0, "purchase": -18.0, "unlock": -18.0,
          "star": -18.0, "all_stars": -16.5, "record": -16.5, "victory": -16.0, "defeat": -17.5, "energy": -20.0,
          "flight": -21.0, "wilhelm": -15.0}
MAXDUR = {"launch": .9, "spring": .6, "body": .7, "head": .6, "limb": .8, "voice": .65, "head_launch": 1.25,
          "click": .25, "back": .3, "browse": .22, "confirm": .35, "module_install": .7, "module_remove": .7,
          "countdown": .45, "go": .6, "coin": .55, "purchase": .8, "unlock": .8, "star": .8, "all_stars": 1.4,
          "record": 1.4, "victory": 1.8, "defeat": 1.5, "energy": .7, "wilhelm": 1.4}


# ------------------------------------------------------------------------------------------------ dsp helpers
def sos(kind, f, order=2):
    nyq = SR / 2
    if kind == "band":
        lo, hi = max(20, f[0]) / nyq, min(f[1], nyq * .95) / nyq
        return butter(order, [lo, max(hi, lo * 1.05)], btype="band", output="sos")
    return butter(order, min(max(f, 20), nyq * .95) / nyq, btype=kind, output="sos")


def hp(x, f, o=2): return sosfilt(sos("high", f, o), x)
def lp(x, f, o=2): return sosfilt(sos("low", f, o), x)
def bp(x, lo, hi, o=2): return sosfilt(sos("band", (lo, hi), o), x)


def T(d): return np.arange(int(d * SR)) / SR


def env_exp(t, tau, atk=.001):
    return (1 - np.exp(-t / max(atk, 1e-5))) * np.exp(-t / max(tau, 1e-4))


def pad(x, n): return np.pad(x, (0, max(0, n - len(x))))[:n] if n else x


def mix(*parts, at=None):
    """mix(signal, offset_seconds) pairs or plain signals; length = longest."""
    items = []
    for p in parts:
        items.append(p if isinstance(p, tuple) else (p, 0.0))
    n = max(int(o * SR) + len(s) for s, o in items)
    y = np.zeros(n)
    for s, o in items:
        i = int(o * SR); y[i:i + len(s)] += s
    return y


def pitch(x, ratio):
    """resampling pitch shift (changes duration like a tape: natural for impacts / mechanisms)."""
    if abs(ratio - 1) < 1e-3:
        return x
    up, down = int(round(1000 / ratio)), 1000
    g = math.gcd(up, down)
    return resample_poly(x, up // g, down // g)


def norm_peak(x, p=1.0):
    m = np.abs(x).max()
    return x * (p / m) if m > 0 else x


def soft_sat(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def room(x, size=.08, mix_=.18, damp=4500, rng=None):
    """tiny toy-room: decaying filtered-noise impulse response (keeps impacts physical without washing them out)."""
    rng = rng or np.random.default_rng(1)
    t = T(size * 3)
    ir = rng.standard_normal(len(t)) * np.exp(-t / size)
    ir = lp(ir, damp); ir[0] = 0
    ir /= np.sqrt((ir ** 2).sum()) + 1e-9
    wet = np.convolve(x, ir)[:len(x) + len(t) // 2]
    return mix(x * (1 - mix_ * .3), wet * mix_)


# ------------------------------------------------------------------------------------------------ source library
_cache = {}


def src(family, idx):
    """sourced clip (mono, SR). family = folder/event (e.g. 'samurai/body', 'common/click')."""
    key = (family, idx)
    if key in _cache:
        return _cache[key].copy()
    folder = LIB / ("v18_samurai_sourced" if family.startswith("samurai/") else "v18_common_sourced")
    ev = family.split("/")[1]; files = sorted(f for f in folder.glob(ev + "_*.ogg") if f.stem[len(ev) + 1:].isdigit())
    p = files[idx % len(files)]
    x, sr = decode(p)
    x = x.mean(axis=1) if x.ndim > 1 else x
    if sr != SR:
        g = math.gcd(SR, sr); x = resample_poly(x, SR // g, sr // g)
    x = hp(x, 25)
    _cache[key] = x
    return x.copy()


def src_count(family):
    folder = LIB / ("v18_samurai_sourced" if family.startswith("samurai/") else "v18_common_sourced")
    ev = family.split("/")[1]; return len([f for f in folder.glob(ev + "_*.ogg") if f.stem[len(ev) + 1:].isdigit()])


def first_event(x, min_gap=.06, rel=.3):
    """keep only the first hit of a clip that contains several (cut just before the next strong onset)."""
    e = np.abs(x); w = int(.004 * SR)
    env = np.convolve(e, np.ones(w) / w, "same")
    pk = env.max() + 1e-9
    on = int(np.argmax(env > pk * .1))
    start = on + int(min_gap * SR)
    low = np.where(env[start:] < pk * rel * .5)[0]
    if len(low):
        j0 = start + low[0]
        high = np.where(env[j0:] > pk * rel)[0]
        if len(high):
            i = j0 + high[0]
            cut = max(on + int(.03 * SR), i - int(.008 * SR))
            y = x[:cut].copy()
            f = min(len(y) // 4, int(.012 * SR)); y[-f:] *= np.linspace(1, 0, f)
            return y[on:] if on < len(y) else y
    return x[on:]


def trim(x, maxdur, floor_db=-48, fade=.03):
    e = np.abs(x)
    pk = e.max() + 1e-9
    act = np.where(e > pk * 10 ** (floor_db / 20))[0]
    if len(act):
        x = x[max(0, act[0] - int(.002 * SR)):act[-1] + 1]
    n = min(len(x), int(maxdur * SR))
    x = x[:n].copy()
    f = min(int(fade * SR), n // 3)
    if f > 1:
        x[-f:] *= np.linspace(1, 0, f) ** 2
    a = min(int(.0015 * SR), n // 8)
    if a > 1:
        x[:a] *= np.linspace(0, 1, a)
    return x


# ------------------------------------------------------------------------------------------------ design layers
def modal(freqs, amps, decays, dur, rng=None, jitter=0.0):
    t = T(dur); y = np.zeros(len(t))
    rng = rng or np.random.default_rng(0)
    for f, a, d in zip(freqs, amps, decays):
        if f >= SR * .45:
            continue
        f *= 1 + rng.uniform(-jitter, jitter)
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * env_exp(t, d, .0006)
    return y


def tin_can(f0, dur, rng):
    """hollow thin-walled can: dense inharmonic cluster, short, a little buzzy."""
    ratios = [1, 1.58, 2.14, 2.71, 3.32, 4.18, 5.4]
    return modal([f0 * r for r in ratios], [1, .8, .7, .55, .45, .3, .2], [.09, .07, .06, .05, .04, .03, .02], dur, rng, .02)


def cast_iron(f0, dur, rng):
    ratios = [1, 2.32, 4.25, 6.63]
    return modal([f0 * r for r in ratios], [1, .45, .25, .12], [.22, .12, .07, .04], dur, rng, .01)


def brass_bell(f0, dur, rng):
    ratios = [.5, 1, 1.19, 1.56, 2.0, 2.66, 3.01]   # hum, prime, minor third, fifth, octave...
    return modal([f0 * r for r in ratios], [.35, 1, .55, .4, .5, .25, .18], [.6, .45, .3, .25, .2, .12, .1], dur, rng, .004)


def steel_ring(f0, dur, rng):
    """blade / tsuba ring: few high inharmonic partials with long decays and slight beating."""
    ratios = [1, 1.004, 2.76, 2.77, 5.40, 8.93]
    return modal([f0 * r for r in ratios], [.6, .5, .45, .35, .2, .1], [.55, .5, .32, .3, .18, .1], dur, rng, .002)


def music_tine(f, dur, amp=1.0, rng=None):
    """music-box comb tine (clamped bar partials) + the tiny pin pluck."""
    rng = rng or np.random.default_rng(0)
    y = modal([f, f * 2.756, f * 5.404, f * 8.933], [1, .3, .12, .05], [.55, .12, .05, .025], dur, rng)
    t = T(.006); pluck = np.random.default_rng(int(f)).standard_normal(len(t)) * np.exp(-t / .0015) * .15
    return amp * mix(y, hp(pluck, 3000))


def noise(d, rng): return rng.standard_normal(int(d * SR))


def burst(d, lo, hi, tau, rng, atk=.0005):
    t = T(d); return bp(noise(d, rng), lo, hi) * env_exp(t, tau, atk)


def rattle(n, spread, lo, hi, rng, decay=.012, tail_bias=1.6):
    """loose bolts / tin rattle: n micro-impacts scattered (denser at the start), each a tiny resonant click."""
    y = np.zeros(int((spread + .05) * SR))
    for k in range(n):
        u = rng.random() ** tail_bias
        i = int(u * spread * SR)
        f = rng.uniform(lo, hi)
        t = T(.03)
        c = np.sin(2 * np.pi * f * t) * np.exp(-t / decay) * (1 - u * .7) * rng.uniform(.4, 1)
        c += bp(rng.standard_normal(len(t)), f * .7, f * 1.6) * np.exp(-t / (decay * .4)) * .5
        y[i:i + len(c)] += c[:len(y) - i]
    return y


def boing(f0, f1, dur, wob, rng, harm=.35):
    """cartoon spring twang: exponential glide + wobble vibrato + a dispersive chirp onset."""
    t = T(dur)
    f = f1 + (f0 - f1) * np.exp(-t / (dur * .35))
    f = f * (1 + wob * np.sin(2 * np.pi * (9 + rng.uniform(-1, 1)) * t) * np.exp(-t / (dur * .6)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = (np.sin(ph) + harm * np.sin(2 * ph + .7) + harm * .4 * np.sin(3 * ph)) * env_exp(t, dur * .38, .002)
    # spring "chirp": the dispersive tick that real springs make
    ct = T(.06)
    chirp = np.sin(2 * np.pi * (5200 * np.exp(-ct / .012) + 900) * ct) * np.exp(-ct / .02) * .35
    return mix(y, chirp)


def thump(f0, f1, tau, dur, rng=None):
    t = T(dur)
    f = f1 + (f0 - f1) * np.exp(-t / (tau * .5))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(t, tau, .0015)


def tick(f, rng, amp=1.0, wood=False):
    t = T(.035)
    c = bp(rng.standard_normal(len(t)), f * .6, f * 1.8) * np.exp(-t / .0035)
    tone = np.sin(2 * np.pi * f * t) * np.exp(-t / (.012 if wood else .006)) * (.8 if wood else .5)
    return amp * (c + tone)


def ratchet(n, rate, f, rng, accel=0.0):
    y = np.zeros(int((n / rate + .06) * SR))
    tpos = 0.0
    for k in range(n):
        c = tick(f * rng.uniform(.95, 1.05), rng, rng.uniform(.6, 1))
        i = int(tpos * SR); y[i:i + len(c)] += c[:len(y) - i]
        tpos += 1 / (rate * (1 + accel * k / max(n, 1)))
    return y


def tick_tock(n, rate, f_hi, f_lo, rng):
    y = np.zeros(int((n / rate + .05) * SR))
    for k in range(n):
        c = tick(f_hi if k % 2 == 0 else f_lo, rng, 1.0 if k % 2 == 0 else .8, wood=True)
        i = int(k / rate * SR); y[i:i + len(c)] += c[:len(y) - i]
    return y


def whoosh(dur, lo, hi, rng, peak_at=.35, sweep=1.0):
    t = T(dur)
    env = np.where(t < dur * peak_at, (t / (dur * peak_at)) ** 1.6, np.exp(-(t - dur * peak_at) / (dur * .22)))
    n = noise(dur, rng)
    seg = int(.01 * SR); out = np.zeros(len(n))
    for i in range(0, len(n), seg):
        u = i / len(n)
        c = lo + (hi - lo) * (u / peak_at if u < peak_at else max(0, 1 - (u - peak_at) * sweep))
        c = max(c, lo)
        out[i:i + seg] = bp(n[max(0, i - 2 * seg):i + seg], c * .5, c * 1.8)[-len(n[i:i + seg]):]
    return out * env


def wood_clack(rng, f=1350):
    """two hard lacquered plates meeting (armour clack) - a short hollow knock, not an instrument."""
    t = T(.08)
    y = modal([f, f * 1.83, f * 2.9], [1, .5, .25], [.02, .012, .008], .08, rng, .03)
    y += bp(rng.standard_normal(len(t)), 900, 5200) * np.exp(-t / .004) * .7
    return y


def hydraulic(dur, f, rng):
    t = T(dur)
    hiss = bp(noise(dur, rng), 1800, 6000) * np.exp(-t / (dur * .3)) * .5
    groan = np.sin(2 * np.pi * np.cumsum(f * (1 - .25 * t / dur)) / SR) * env_exp(t, dur * .4, .02) * .6
    return hiss + lp(soft_sat(groan * 2, 2), 900)


# --- robot "voices": formant-synth mechanical vocal grunts (no sine beeps)
VOWELS = {"a": (730, 1090, 2440), "o": (570, 840, 2410), "u": (300, 870, 2240), "e": (530, 1840, 2480),
          "i": (390, 1990, 2550), "uh": (520, 1190, 2390), "m": (280, 1000, 2200)}


def formant_voice(contour, vowels, dur, rng, rough=.15, robot=.4, ring=55.0, breath=.08):
    """contour: (f_start, f_mid, f_end) Hz; vowels: sequence of keys morphing over time."""
    t = T(dur)
    u = t / dur
    f0 = np.interp(u, [0, .35, 1], contour) * (1 + .012 * np.sin(2 * np.pi * 5.5 * t))
    f0 *= 1 + rough * .03 * rng.standard_normal(len(t)).cumsum() / np.sqrt(np.arange(1, len(t) + 1))
    ph = np.cumsum(f0) / SR
    src_ = (2 * (ph % 1) - 1)                              # bright sawtooth glottis
    src_ = lp(src_, 5000) + breath * noise(dur, rng)
    keys = [VOWELS[v] for v in vowels]
    out = np.zeros(len(t))
    seg = int(.008 * SR)
    for i in range(0, len(t), seg):
        k = i / len(t) * (len(keys) - 1)
        a, b = keys[int(k)], keys[min(int(k) + 1, len(keys) - 1)]
        fr = k - int(k)
        fs = [a[j] * (1 - fr) + b[j] * fr for j in range(3)]
        chunk = src_[max(0, i - 4 * seg):i + seg]
        y = sum(bp(chunk, f * .82, f * 1.2) * g for f, g in zip(fs, (1, .7, .35)))
        out[i:i + seg] = y[-len(out[i:i + seg]):]
    env = np.clip(u / .06, 0, 1) * np.clip((1 - u) / .25, 0, 1) ** .8
    out *= env
    if robot > 0:   # mechanical ring-mod + light comb: robot, not human
        out = out * (1 - robot) + out * np.sin(2 * np.pi * ring * t) * robot
        d = int(SR / 180)
        out[d:] += out[:-d] * .35
    return out


# ------------------------------------------------------------------------------------------------ mastering
def limiter(x, ceil_db=-1.0, look=.002, release=.06):
    from scipy.ndimage import maximum_filter1d, minimum_filter1d
    from scipy.signal import lfilter
    ceil = 10 ** (ceil_db / 20)
    a = np.abs(x)
    w = max(1, int(look * SR))
    g1 = 1 / np.maximum(1.0, maximum_filter1d(a, size=2 * w + 1) / ceil)    # look-ahead gain (never too little)
    g1 = minimum_filter1d(g1, size=int(.01 * SR) | 1)                        # short hold
    r = math.exp(-1 / (release * SR))
    g2 = lfilter([1 - r], [1, -r], g1, zi=[g1[0] * r])[0]                    # smooth release
    g = np.minimum(g1, g2)                                                   # smoothing can only reduce gain further
    return np.clip(x * g, -ceil, ceil)


def master(x, family, loop=False):
    x = hp(x, 32)
    x = lp(x, 16500)
    if not loop:
        x = trim(x, MAXDUR.get(family, 1.5))
    x = norm_peak(x, .5)
    tgt = TARGET[family]
    for _ in range(3):
        l = loudness(x[:, None], SR)
        x = x * 10 ** ((tgt - l) / 20)
        x = limiter(x, -1.0)
    return x


def write_wav(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))


def fingerprint(x):
    return features(x[:, None], SR)["fp"]


# ------------------------------------------------------------------------------------------------ robot recipes
PROFILE = {   # per robot: base pitch of the sourced layers, signature parameters
    "tin": dict(p=1.12, can=640, rattle=(18, .22), bounce=(520, 260), lazy=.92),
    "hopper": dict(p=1.06, can=520, rattle=(6, .1), bounce=(380, 150), lazy=1.0),
    "heavy": dict(p=.72, can=150, rattle=(4, .08), bounce=(150, 70), lazy=1.0),
    "rocket": dict(p=1.0, can=880, rattle=(8, .12), bounce=(420, 220), lazy=1.0),
    "samurai": dict(p=1.0, can=1100, rattle=(5, .08), bounce=(460, 240), lazy=1.0),
}


def R(robot, event, i, attempt):
    return np.random.default_rng(int(hashlib.md5(f"{robot}/{event}/{i}/{attempt}".encode()).hexdigest()[:8], 16))


def launch(robot, i, k, rng):
    """flick launch: sourced whoosh base + the robot's identity on the take-off."""
    P = PROFILE[robot]
    w = trim(src("samurai/launch", i * 2 + (1 if robot in ("hopper", "rocket") else 0)), 1.0)
    w = pitch(w, P["p"] * rng.uniform(.97, 1.03))
    if robot == "tin":
        sig = mix(rattle(16, .35, 1800, 5200, rng) * .45, tin_can(P["can"] * rng.uniform(.95, 1.05), .3, rng) * .5)
        return mix(w * .9, (sig, .02))
    if robot == "hopper":
        b = boing(rng.uniform(300, 360), rng.uniform(620, 760), .45, .05, rng) * .55     # upward "sproing"
        return mix(w * .85, (b, 0.0))
    if robot == "heavy":
        return mix(lp(w, rng.uniform(2200, 3800)) * .9, thump(rng.uniform(80, 115), rng.uniform(34, 48), rng.uniform(.12, .22), .45) * 1.1,
                   (hydraulic(rng.uniform(.25, .45), rng.uniform(85, 135), rng) * rng.uniform(.25, .45), rng.uniform(.0, .08)))
    if robot == "rocket":
        return mix(w * .8, ratchet(6, 34, 3100, rng, accel=.6) * .5, (brass_bell(rng.uniform(1300, 1500), .5, rng) * .18, .06))
    # samurai: authentic sourced whoosh + a short blade ring as he leaves the hand
    return mix(w, (steel_ring(rng.uniform(2300, 2700), .55, rng) * .22, .05), (wood_clack(rng) * .35, 0.0))


def spring(robot, i, k, rng):
    """feet landing on the springs: frequent -> short, punchy, never harsh."""
    P = PROFILE[robot]
    s = first_event(src("samurai/spring", i), min_gap=.05, rel=.45) if robot != "hopper" else src("samurai/spring", i)
    s = trim(pitch(s, P["p"] * rng.uniform(.96, 1.04)), .45)
    if robot == "tin":
        return mix(s * .7, boing(P["bounce"][0] * rng.uniform(.9, 1.1), P["bounce"][1], .28, .07, rng) * .35,
                   (rattle(*P["rattle"], 2200, 6000, rng) * .3, .015))
    if robot == "hopper":
        return mix(s * .6, boing(rng.uniform(330, 420), rng.uniform(120, 170), .5 + .1 * k, .09, rng) * .7)
    if robot == "heavy":
        return mix(lp(s, rng.uniform(1800, 3200)) * rng.uniform(.55, .85),
                   thump(rng.uniform(100, 140), rng.uniform(40, 55), rng.uniform(.08, .15), .35) * rng.uniform(.9, 1.2),
                   (hydraulic(rng.uniform(.15, .3), rng.uniform(70, 110), rng) * rng.uniform(.15, .35), rng.uniform(0, .03)),
                   (boing(rng.uniform(130, 175), rng.uniform(60, 85), rng.uniform(.22, .38), rng.uniform(.02, .06), rng) * rng.uniform(.2, .4), rng.uniform(0, .02)))
    if robot == "rocket":
        n_t = 2 + (i % 3)
        return mix(s * .75, (tick_tock(n_t, rng.uniform(11, 18), rng.uniform(3300, 3900), rng.uniform(2400, 2900), rng) * .45, rng.uniform(.01, .04)),
                   boing(rng.uniform(380, 470), rng.uniform(230, 290), rng.uniform(.18, .28), .04, rng) * .2)
    # samurai: the sourced coil bounce itself (2-3 tight rebounds), crisp, with a faint lacquer clack
    s2 = trim(pitch(src("samurai/spring", i), rng.uniform(.97, 1.03)), .3)
    return mix(s2 * .9, wood_clack(rng, rng.uniform(1500, 1800)) * .22)


def body(robot, i, k, rng):
    """torso / arm hit."""
    P = PROFILE[robot]
    b = first_event(src("samurai/body", i), rel=.4)
    b = trim(pitch(b, P["p"] * rng.uniform(.95, 1.05)), .6)
    if robot == "tin":
        return mix(b * .6, tin_can(P["can"] * rng.uniform(.9, 1.1), .35, rng) * .6, (rattle(22, .4, 1500, 5500, rng) * .35, .02))
    if robot == "hopper":
        return mix(b * rng.uniform(.6, .85), (boing(rng.uniform(220, 330), rng.uniform(90, 140), rng.uniform(.22, .4), rng.uniform(.06, .14), rng)
                                              * rng.uniform(.3, .5), rng.uniform(0, .025)))
    if robot == "heavy":
        return mix(lp(b, 2800) * .85, cast_iron(rng.uniform(95, 120), .45, rng) * .55, thump(110, 40, .12, .4) * .9)
    if robot == "rocket":
        return mix(b * .7, (ratchet(5, 60, 4200, rng) * .4, .01), (brass_bell(rng.uniform(1700, 2000), .35, rng) * .12, 0.0))
    return mix(b * .9, wood_clack(rng, rng.uniform(1100, 1400)) * .45, (steel_ring(rng.uniform(3000, 3600), .4, rng) * .1, .005))


def head(robot, i, k, rng):
    """head bonk."""
    P = PROFILE[robot]
    h = first_event(src("samurai/head", i if i < 7 else i - 3), rel=.4)
    h = trim(pitch(h, P["p"] * rng.uniform(.95, 1.05)), .5)
    if robot == "tin":
        return mix(h * .55, tin_can(P["can"] * 1.3 * rng.uniform(.95, 1.05), .4, rng) * .75)
    if robot == "hopper":
        return mix(h * .7, modal([420, 1060, 1900], [1, .4, .2], [.08, .05, .03], .3, rng) * .5,
                   (boing(500, 260, .25, .08, rng) * .25, .02))
    if robot == "heavy":
        return mix(lp(h, 2200) * .8, cast_iron(rng.uniform(140, 170), .45, rng) * .5, thump(160, 55, .09, .3) * .6)
    if robot == "rocket":
        return mix(h * .55, brass_bell(rng.uniform(820, 980), .55, rng) * .55)        # a clock "dong"
    return mix(h * .8, steel_ring(rng.uniform(1900, 2300), .5, rng) * .3, wood_clack(rng) * .3)


def limb(robot, i, k, rng):
    """limb torn off."""
    P = PROFILE[robot]
    l = first_event(src("samurai/limb", i + 1), rel=.4)
    l = trim(pitch(l, P["p"] * rng.uniform(.96, 1.04)), .55)
    sproing = boing(rng.uniform(700, 900), rng.uniform(200, 260), .5, .12, rng) * .35   # the arm's spring lets go
    if robot == "tin":
        return mix(l * .7, sproing * .6, (rattle(30, .6, 1200, 6000, rng, tail_bias=1.2) * .5, .02))
    if robot == "hopper":
        return mix(l * .6, boing(rng.uniform(900, 1100), 140, .65, .16, rng) * .7)
    if robot == "heavy":
        return mix(lp(l, 2500) * .8, cast_iron(rng.uniform(70, 90), .55, rng) * .55, thump(90, 35, .15, .5), (sproing * .3, .03))
    if robot == "rocket":
        gears = rattle(26, .55, 2500, 7000, rng, decay=.02) * .45
        return mix(l * .6, sproing * .5, (gears, .02), (ratchet(10, 45, 3800, rng, accel=-.5) * .35, .0))
    return mix(l * .85, (steel_ring(rng.uniform(2600, 3200), .6, rng) * .25, .0), sproing * .4)


def voice(robot, i, k, rng):
    """occasional vocal reaction on a big hit / full charge (cooldown 8 s): mechanical, characterful, short."""
    if robot == "samurai":
        # the original sourced samurai shouts, given a light lacquered-mask resonance (mechanical, not a gag)
        v = trim(src("samurai/voice", [0, 2, 4, 6, 8, 10][i]), .6)
        t = T(len(v) / SR)
        return mix(v * .85 + bp(v, 900, 2600) * .25 * np.sin(2 * np.pi * 70 * t))
    if robot == "tin":         # relaxed, lazy "whoa-oh" sliding down: unbothered
        shapes = [["o", "a", "o"], ["a", "o", "u"], ["e", "a", "o"], ["uh", "o"], ["o", "u", "o"], ["a", "e", "o"]]
        contours = [(175, 160, 110), (150, 180, 120), (185, 150, 105), (160, 172, 140), (170, 140, 115), (140, 165, 100)]
        c = tuple(f * rng.uniform(.95, 1.05) for f in contours[i % 6])
        return lp(formant_voice(c, shapes[i % 6], rng.uniform(.38, .58), rng, rough=.2, robot=.2, ring=48), 4200)
    if robot == "hopper":      # bright energetic "hup!/yip!"
        c = (rng.uniform(300, 340), rng.uniform(420, 470), rng.uniform(380, 430))
        return lp(formant_voice(c, ["uh", "e", "i"], rng.uniform(.22, .3), rng, rough=.1, robot=.22, ring=80), 5200)
    if robot == "heavy":       # deep "HMMPH!"
        shapes = [["m", "uh", "o"], ["uh", "o"], ["o", "m"], ["m", "a", "uh"], ["u", "o"], ["uh", "a"]]
        contours = [(95, 115, 84), (110, 100, 78), (88, 120, 96), (100, 112, 70), (92, 92, 86), (105, 125, 90)]
        c = tuple(f * rng.uniform(.95, 1.05) for f in contours[i % 6])
        return lp(formant_voice(c, shapes[i % 6], rng.uniform(.32, .52), rng, rough=.3, robot=.22, ring=33), 2600) * 1.2
    # rocket: precise, clipped two-beat exclamations ("ah-HA!", "tut-TUT", "oh-HO") on the clock's tick
    shapes = [(["a"], ["a"]), (["uh"], ["u"]), (["o"], ["o"]), (["e"], ["a"]), (["a"], ["i"]), (["o"], ["a"])]
    v1, v2 = shapes[i % len(shapes)]
    base = rng.uniform(190, 235)
    s1 = formant_voice((base, base * 1.05, base), v1, rng.uniform(.1, .14), rng, rough=.05, robot=.5, ring=110)
    s2 = formant_voice((base * 1.2, base * rng.uniform(1.3, 1.45), base * rng.uniform(1.0, 1.25)), v2, rng.uniform(.16, .24), rng, rough=.05, robot=.5, ring=110)
    gap = rng.uniform(.11, .16)
    return mix(s1 * .8, (s2, gap), (tick(3400, rng, .45), .0), (tick(2600, rng, .35), gap))


def head_launch(robot, i, k, rng):
    """the jet head fires."""
    P = PROFILE[robot]
    j = trim(src("samurai/head_launch", i + 1), 1.2)
    j = pitch(j, P["p"] * rng.uniform(.97, 1.03))
    if robot == "tin":
        return mix(j * .85, rattle(24, .5, 1800, 6000, rng) * .35, tin_can(700, .4, rng) * .35)
    if robot == "hopper":
        return mix(j * .8, boing(rng.uniform(260, 300), rng.uniform(900, 1100), .5, .08, rng) * .4)
    if robot == "heavy":
        return mix(lp(j, 3200) * .9, thump(80, 38, .3, .8) * .9)
    if robot == "rocket":     # alarm-clock bell burst as the clock head takes off
        t = T(.45)
        bell = brass_bell(1500, .45, rng) * (1 + .6 * np.sign(np.sin(2 * np.pi * 22 * t))) * .22
        return mix(j * .8, bell)
    return mix(j * .9, (steel_ring(rng.uniform(2200, 2600), .8, rng) * .25, .04))


def rolling(robot, rng):
    """head rolling loop (seamless): sourced rolling texture re-voiced per robot."""
    base = src("samurai/rolling", 0)
    base = pitch(base, PROFILE[robot]["p"])[:int(3.0 * SR)]
    t = T(len(base) / SR)
    if robot == "tin":
        layer = rattle(70, len(t) / SR - .05, 2000, 6000, rng, tail_bias=1.0) * .25
    elif robot == "rocket":
        layer = tick_tock(int(len(t) / SR * 8), 8, 3800, 2900, rng) * .3
    elif robot == "heavy":
        layer = lp(noise(len(t) / SR, rng), 160) * .6
    elif robot == "hopper":
        layer = boing(220, 160, len(t) / SR, .2, rng) * .05
    else:
        layer = np.zeros(len(t))
    y = mix(base, layer)[:len(base)]
    k = int(.15 * SR)   # crossfade the ends for a seamless loop
    fade = np.linspace(0, 1, k)
    y = np.concatenate([y[-k:] * (1 - fade) + y[:k] * fade, y[k:-k]])
    return y


# ------------------------------------------------------------------------------------------------ common recipes
NOTE = lambda n: 440 * 2 ** ((n - 69) / 12)   # midi -> Hz


def tune(notes, step, dur, rng, amp=1.0, spread=0.0):
    y = mix(*[(music_tine(NOTE(n), max(.35, dur - j * step), amp * (1 - spread * j), rng), j * step) for j, n in enumerate(notes)])
    return y


def mech_click(i, pitch_r=1.0, which="click"):
    x = first_event(src("common/" + which, i), min_gap=.02, rel=.5)
    return pitch(x, pitch_r)


def common(name, i, n, rng):
    k = i / max(1, n - 1)
    if name == "click":
        return trim(mech_click(i, rng.uniform(.98, 1.04)), .2)
    if name == "back":
        return trim(mech_click(i, .82 * rng.uniform(.98, 1.02), "back"), .25)
    if name == "browse":
        return trim(lp(mech_click(i, 1.15 * rng.uniform(.98, 1.02), "browse"), 7000), .2)
    if name == "confirm":
        return mix(trim(mech_click(i, 1.05, "confirm"), .2), (music_tine(NOTE(84 + [0, 2, 4][i % 3]), .3, .35, rng), .015))
    if name == "module_install":   # ratchet in, latch clicks shut
        return mix(ratchet(5, 28, 2600, rng, accel=.5) * .6, (mech_click(i, .9, "confirm") * .9, .2), (wood_clack(rng, 1600) * .5, .21))
    if name == "module_remove":    # latch pops, part slides out
        return mix(mech_click(i, .85, "back") * .9, (burst(.25, 600, 3000, .08, rng) * .25, .03), (ratchet(4, 22, 2000, rng, accel=-.4) * .45, .08))
    if name == "countdown":        # wind-up key turns: one tick per count
        return mix(tick(2900 + 300 * i, rng, 1.0, wood=True), (tick(2200 + 200 * i, rng, .6, wood=True), .07),
                   (music_tine(NOTE(76 + 2 * i), .3, .25, rng), .0))
    if name == "go":               # spring released: twang + bright tine pair
        pairs = [(88, 95), (86, 93), (91, 98)]
        a_, b_ = pairs[i % 3]
        return mix(boing(rng.uniform(450, 560), rng.uniform(1050, 1350), .35, .05, rng) * .5, music_tine(NOTE(a_), .45, .6, rng),
                   (music_tine(NOTE(b_), .4, .45, rng), rng.uniform(.04, .07)))
    if name == "coin":             # toy-bank coin: little metallic drop + two rising tines
        return mix(modal([3100, 4700, 6900], [1, .5, .3], [.05, .03, .02], .1, rng) * .4,
                   (tune([(88, 95), (91, 96), (86, 93), (89, 98)][i % 4], rng.uniform(.06, .085), .45, rng, .8), .015))
    if name == "purchase":         # cash-register ka-ching on a wind-up mechanism
        bell, top = [(91, 96), (89, 98), (93, 100)][i % 3]
        return mix(ratchet(3 + i, rng.uniform(32, 46), 2400, rng) * .5, (wood_clack(rng, 1700) * .5, .1),
                   (brass_bell(NOTE(bell), .6, rng) * .35, .12), (tune([top], .0, .5, rng, .5), .14))
    if name == "unlock":           # key turns, latch springs open, a small rising flourish
        return mix(ratchet(3, 18, 1900, rng) * .6, (mech_click(i, .8, "confirm"), .17),
                   (tune([79 + i % 2, 83 + i % 2, 86 + i % 2], .06, .55, rng, .7), .2))
    if name == "star":
        base = [84, 88, 91, 96]
        return mix(tune([b + (i % 3) for b in base], .055, .6, rng, .75), (rattle(10, .35, 6000, 9000, rng, decay=.004) * .08, .1))
    if name == "all_stars":
        seq = [79, 84, 88, 91, 96, 100]
        return mix(tune([s + (i % 2) * 2 for s in seq], .07, 1.0, rng, .8),
                   (rattle(24, .7, 6000, 9500, rng, decay=.005) * .1, .2), (brass_bell(NOTE(84), .9, rng) * .12, .42))
    if name == "record":           # new personal record: music-box fanfare with a final bell
        seq = [[72, 76, 79, 84, 79, 84], [74, 79, 83, 86, 83, 88], [72, 79, 76, 81, 84, 88]][i % 3]
        return mix(tune(seq, rng.uniform(.085, .105), .9, rng, .8), (brass_bell(NOTE(seq[-1]), 1.0, rng) * .25, .55))
    if name == "victory":
        seq = [72, 72, 79, 84, 88, 91]
        rh = [0, .09, .2, .32, .44, .6]
        y = mix(*[(music_tine(NOTE(s + i % 2), 1.0 if j == 5 else .45, .8, rng), rh[j]) for j, s in enumerate(seq)])
        return mix(y, (brass_bell(NOTE(84 + i % 2), 1.1, rng) * .3, .6), (boing(400, 900, .3, .04, rng) * .15, 0.0))
    if name == "defeat":           # the wind-up toy runs down: tines slow and sag, a sad spring droop
        notes = [[79, 76, 72, 67], [77, 74, 70, 65], [76, 75, 71, 64]][i % 3]
        y = np.zeros(1)
        tpos = 0.0
        parts = []
        for j, nn in enumerate(notes):
            parts.append((music_tine(NOTE(nn) * (1 - .015 * j), .5, .7, rng), tpos))
            tpos += .13 + .06 * j
        y = mix(*parts)
        return mix(y, (boing(300, 120, .6, .12, rng) * .25, tpos - .05), (ratchet(5, 12, 1800, rng, accel=-.6) * .25, .0))
    if name == "energy":           # charge crackle (sourced) - tiered tick or release
        x = trim(src("common/energy", i), .6)
        x = pitch(x, .9 + .25 * k)
        return mix(x, (music_tine(NOTE(84 + 5 * k), .25, .15 + .25 * k, rng), .0)) if k > .5 else x
    raise KeyError(name)


COMMON_N = {"click": 3, "back": 3, "browse": 3, "confirm": 3, "module_install": 3, "module_remove": 3, "countdown": 3,
            "go": 3, "coin": 4, "purchase": 3, "unlock": 3, "star": 4, "all_stars": 3, "record": 3, "victory": 3,
            "defeat": 3, "energy": 7}
RECIPES = {"launch": launch, "spring": spring, "body": body, "head": head, "limb": limb, "voice": voice, "head_launch": head_launch}


def build_family(key, n, make, family_name, loop=False):
    clips, fps, report = [], [], []
    for i in range(n):
        for attempt in range(6):
            rng = R(key, family_name, i, attempt)
            x = master(make(i, attempt, rng), family_name, loop)
            fp = fingerprint(x)
            sim = max([float(np.corrcoef(fp, f)[0, 1]) for f in fps], default=0)
            if sim < .985 or attempt == 5:
                break
        fps.append(fp); clips.append(x); report.append({"i": i, "sim_to_previous": round(sim, 4), "attempts": attempt + 1})
    return clips, report


def main():
    old_files = [p for p in OUT.rglob("*") if p.suffix in (".ogg", ".wav") or p.name.endswith((".ogg.import", ".wav.import"))]
    # wilhelm: the authentic scream (restored from git 14f4661917, originally 'Wilhelm_Scream.ogg.ogx')
    wil, wsr = decode(LIB / "v18_common_sourced/wilhelm_01.ogg")
    wil = wil.mean(axis=1) if wil.ndim > 1 else wil
    g = math.gcd(SR, wsr); wil = resample_poly(wil, SR // g, wsr // g)
    banks, report = {}, {}
    written = []

    def emit(prefix, event, clips, loop=False):
        fam = f"{prefix}/{event}"
        entries = []
        # tier: ascending perceived brightness/energy (the game picks tiers <= intensity+.3)
        order = sorted(range(len(clips)), key=lambda j: features(clips[j][:, None], SR)["centroid"] * (1 + len(clips[j]) / SR))
        for rank, j in enumerate(order):
            path = OUT / prefix / f"{event}_{rank + 1:02d}.wav"
            write_wav(path, clips[j]); written.append(path)
            entries.append({"path": f"res://assets/audio/{prefix}/{event}_{rank + 1:02d}.wav",
                            "energy": round(float(np.sqrt(np.mean(clips[j] ** 2))), 4), "duration": round(len(clips[j]) / SR, 3),
                            "loop": loop, "tier": round(rank / max(1, len(clips) - 1), 4)})
        banks[fam] = entries

    for robot in ROBOTS:
        for ev in EVENTS:
            if ev == "rolling":
                rng = R(robot, ev, 0, 0)
                emit(robot, ev, [master(rolling(robot, rng), "rolling", loop=True)], loop=True)
                continue
            n = VARIANTS[ev]
            clips, rep = build_family(robot, n, lambda i, a, rng, ev=ev, robot=robot: RECIPES[ev](robot, i, i / max(1, n - 1), rng), ev)
            emit(robot, ev, clips); report[f"{robot}/{ev}"] = rep
    for name, n in COMMON_N.items():
        clips, rep = build_family("common", n, lambda i, a, rng, name=name, n=n: common(name, i, n, rng), name)
        emit("common", name, clips); report[f"common/{name}"] = rep
    # flight loop: sourced jet flight, seamless
    fl, fsr = decode(LIB / "v18_common_sourced/flight_01.ogg")
    fl = fl.mean(axis=1) if fl.ndim > 1 else fl
    g = math.gcd(SR, fsr); fl = resample_poly(fl, SR // g, fsr // g)[:int(3.0 * SR)]
    k = int(.15 * SR); fade = np.linspace(0, 1, k)
    fl = np.concatenate([fl[-k:] * (1 - fade) + fl[:k] * fade, fl[k:-k]])
    emit("common", "flight", [master(fl, "flight", loop=True)], loop=True)
    emit("common", "wilhelm", [master(wil, "wilhelm")])

    # families owned by other builders (build_anomaly_sounds.py, v37 build_robot_sound_sets.py) are carried over
    # unchanged, and their files are kept
    try:
        old_banks = json.loads((OUT / "bank.json").read_text(encoding="utf-8")).get("banks", {})
    except (OSError, ValueError):
        old_banks = {}
    for fam, entries in old_banks.items():
        is_ui_v38 = any("/ui_v38/" in e.get("path", "") for e in entries)   # v38 UI set replaces the v27 common UI
        if is_ui_v38 or (fam not in banks and (fam.startswith("common/anomaly_") or "_v37/" in fam or fam.startswith("v39/") or fam.startswith("v40/"))):
            banks[fam] = entries
            written += [OUT / e["path"].replace("res://assets/audio/", "") for e in entries]
    profiles = {r: {e: f"{r}/{e}" for e in EVENTS} for r in ROBOTS}
    manifest = {"profiles": profiles, "banks": banks,
                "wilhelm_height_m": 30.0, "wilhelm_rearm_m": 20.0, "wilhelm_probability": 0.07,
                "voice_probability": .18, "missing_robot_banks": [], "music_excluded": True,
                "audio_version": "v27_sourced_physical_redesign", "sample_format": "wav16_mono_44100_qoa_import",
                "loudness_targets_lufs": TARGET,
                "sources": {"library": "art/audio/source_library (restored from git 14f4661917, v18 segmentation of the user's source files)",
                            "wilhelm": "art/audio/source_library/v18_common_sourced/wilhelm_01.ogg (authentic Wilhelm_Scream.ogg.ogx)"}}
    (OUT / "bank.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    # only now remove the previous bank's samples that this build did not rewrite (no dangling references)
    keep = {p.resolve() for p in written}
    for p in old_files:
        base = p.with_suffix("") if p.name.endswith(".import") else p
        if p.exists() and base.resolve() not in keep:
            p.unlink()
    (ROOT / "reports").mkdir(exist_ok=True)
    (ROOT / "reports/v27_audio_build.json").write_text(json.dumps(report, indent=1), encoding="utf8")
    print("families", len(banks), "clips", sum(len(v) for v in banks.values()), "bytes", sum(p.stat().st_size for p in written))


if __name__ == "__main__":
    main()
