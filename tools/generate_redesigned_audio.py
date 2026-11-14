#!/usr/bin/env python3
"""
Procedural Cartoon-Mechanical Audio Synthesizer for EpicShalban.
Generates a complete, cohesive, original Ogg Vorbis sound library from scratch
covering Common UI/Rewards/Physics and all 5 Playable Robot Personalities:
  - tin     (Растабот):   light, playful, hollow tin-drum / kalimba-marimba bounce
  - hopper  (Кенгуробот): ultra-elastic dual-coil pogo spring & pneumatic pop
  - heavy   (Сумобот):    deep, weighty cast-iron & taiko sub-bass hydraulic impacts
  - rocket  (Хронобот):   precision clockwork escapement ratchets & brass bell harmonics
  - samurai (Самуробот):  crisp laminated-steel katana ring & taut bamboo-armor snap
"""
import io
import json
import math
import pathlib
import shutil
import av
import numpy as np
from scipy.signal import butter, lfilter

SR = 32000
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "game" / "assets" / "audio"
RAW_AUDIO_DIR = ROOT / "Audio"


def make_t(duration: float) -> np.ndarray:
    return np.linspace(0.0, duration, int(round(duration * SR)), endpoint=False, dtype=np.float64)


def env_adsr(n: int, atk_s: float, dec_s: float, sus_level: float, rel_s: float) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / SR
    dur = n / SR
    env = np.ones(n, dtype=np.float64) * sus_level
    atk_n = max(1, int(atk_s * SR))
    dec_n = max(1, int(dec_s * SR))
    rel_n = max(1, int(rel_s * SR))
    # Attack
    a_end = min(n, atk_n)
    env[:a_end] = np.linspace(0.0, 1.0, a_end) ** 0.7
    # Decay
    d_end = min(n, a_end + dec_n)
    if d_end > a_end:
        env[a_end:d_end] = 1.0 - (1.0 - sus_level) * (1.0 - np.exp(-3.0 * np.linspace(0.0, 1.0, d_end - a_end)))
    # Release
    r_start = max(0, n - rel_n)
    if r_start < n:
        env[r_start:] *= np.exp(-4.5 * np.linspace(0.0, 1.0, n - r_start))
    env[-min(n, 64):] *= np.linspace(1.0, 0.0, min(n, 64))
    return env


def exp_decay(t: np.ndarray, tau: float, atk_s: float = 0.003) -> np.ndarray:
    atk = 1.0 - np.exp(-t / max(atk_s, 0.0004))
    return atk * np.exp(-t / max(tau, 0.002))


def bandpass(x: np.ndarray, lo_hz: float, hi_hz: float, order: int = 2) -> np.ndarray:
    nyq = 0.5 * SR
    lo = max(20.0, min(lo_hz, nyq * 0.92)) / nyq
    hi = max(lo + 0.02, min(hi_hz, nyq * 0.96)) / nyq
    b, a = butter(order, [lo, hi], btype="band")
    return lfilter(b, a, x)


def lowpass(x: np.ndarray, cutoff_hz: float, order: int = 2) -> np.ndarray:
    nyq = 0.5 * SR
    c = max(30.0, min(cutoff_hz, nyq * 0.95)) / nyq
    b, a = butter(order, c, btype="low")
    return lfilter(b, a, x)


def highpass(x: np.ndarray, cutoff_hz: float, order: int = 2) -> np.ndarray:
    nyq = 0.5 * SR
    c = max(20.0, min(cutoff_hz, nyq * 0.90)) / nyq
    b, a = butter(order, c, btype="high")
    return lfilter(b, a, x)


def pitch_sweep(t: np.ndarray, f0: float, f1: float, curve: float = 1.0) -> np.ndarray:
    dur = max(float(t[-1]) if len(t) else 0.001, 0.001)
    u = (t / dur) ** curve
    inst_f = f0 + (f1 - f0) * u
    phase = 2.0 * np.pi * np.cumsum(inst_f) / SR
    return np.sin(phase)


def modal_cluster(t: np.ndarray, base_freq: float, ratios: list[float], amps: list[float], decays: list[float], fm_amt: float = 0.0) -> np.ndarray:
    out = np.zeros_like(t)
    for r, a, d in zip(ratios, amps, decays):
        f = base_freq * r
        if f >= SR * 0.44:
            continue
        mod = fm_amt * np.sin(2.0 * np.pi * (f * 1.414) * t) * np.exp(-t / (d * 0.35)) if fm_amt > 0.0 else 0.0
        out += a * np.sin(2.0 * np.pi * f * t + mod) * exp_decay(t, d, 0.0015)
    return out


def master_clip(left: np.ndarray, right: np.ndarray, target_rms: float = 0.105, max_peak: float = 0.68, loop: bool = False) -> tuple[np.ndarray, float]:
    # Highpass @ 32 Hz to remove DC / sub-rumble, lowpass @ 11.5 kHz for warm non-harsh top end
    l = lowpass(highpass(left, 32.0, 2), 11500.0, 2)
    r = lowpass(highpass(right, 32.0, 2), 11500.0, 2)
    if loop:
        k = min(int(0.12 * SR), len(l) // 6)
        fade = np.linspace(0.0, 1.0, k)
        l = np.r_[l[-k:] * (1.0 - fade) + l[:k] * fade, l[k:-k]]
        r = np.r_[r[-k:] * (1.0 - fade) + r[:k] * fade, r[k:-k]]
    else:
        fi = min(int(0.003 * SR), len(l) // 8)
        fo = min(int(0.018 * SR), len(l) // 5)
        if fi > 1:
            w_in = np.linspace(0.0, 1.0, fi)
            l[:fi] *= w_in
            r[:fi] *= w_in
        if fo > 1:
            w_out = np.linspace(1.0, 0.0, fo) ** 1.5
            l[-fo:] *= w_out
            r[-fo:] *= w_out

    # Warm soft saturation
    l = np.tanh(l * 1.25) / 1.25
    r = np.tanh(r * 1.25) / 1.25

    mono = 0.5 * (l + r)
    rms = float(np.sqrt(np.mean(mono * mono)))
    peak = float(max(np.max(np.abs(l)), np.max(np.abs(r)), 1e-6))
    gain = min(max_peak / peak, target_rms / max(rms, 1e-4))
    l = (l * gain).astype(np.float32)
    r = (r * gain).astype(np.float32)
    final_mono = 0.5 * (l + r)
    final_rms = float(np.sqrt(np.mean(final_mono * final_mono)))
    return np.stack([l, r], axis=0), final_rms


def write_ogg(path: pathlib.Path, stereo: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    buf = io.BytesIO()
    container = av.open(buf, mode="w", format="ogg")
    stream = container.add_stream("vorbis", rate=SR)
    stream.codec_context.options = {"strict": "-2"}
    stream.layout = "stereo"
    stream.bit_rate = 96000
    # Feed in chunks of 1024 samples so Vorbis framing is clean
    total = stereo.shape[1]
    pos = 0
    chunk = 1024
    while pos < total:
        sub = np.ascontiguousarray(stereo[:, pos:min(total, pos + chunk)], dtype=np.float32)
        frame = av.AudioFrame.from_ndarray(sub, format="fltp", layout="stereo")
        frame.sample_rate = SR
        for pkt in stream.encode(frame):
            container.mux(pkt)
        pos += chunk
    for pkt in stream.encode(None):
        container.mux(pkt)
    container.close()
    path.write_bytes(buf.getvalue())


# ==============================================================================
# ROBOT PERSONALITY DEFINITIONS
# ==============================================================================
ROBOT_SPECS = {
    "tin": {
        # Растабот: light, playful, hollow tin-drum / kalimba-marimba bounce
        "base_hz": 240.0,
        "modal_ratios": [1.0, 2.02, 2.96, 4.18, 5.45],
        "modal_amps": [1.0, 0.68, 0.45, 0.25, 0.14],
        "modal_decays": [0.16, 0.12, 0.09, 0.06, 0.04],
        "fm": 0.65,
        "spring_f0": 195.0,
        "spring_f1": 640.0,
        "spring_boing": 7.5,
        "sub_weight": 0.42,
        "voice_f0": 370.0,
        "rattle_band": (1400.0, 4200.0),
    },
    "hopper": {
        # Кенгуробот: springier, more elastic jump/landing pogo character
        "base_hz": 215.0,
        "modal_ratios": [1.0, 1.78, 2.84, 3.92, 5.10],
        "modal_amps": [0.95, 0.75, 0.50, 0.30, 0.16],
        "modal_decays": [0.19, 0.15, 0.11, 0.08, 0.05],
        "fm": 0.45,
        "spring_f0": 155.0,
        "spring_f1": 820.0,
        "spring_boing": 11.5,
        "sub_weight": 0.52,
        "voice_f0": 420.0,
        "rattle_band": (1100.0, 3600.0),
    },
    "heavy": {
        # Сумобот: heavier, deeper, meatier impacts and hydraulic landings
        "base_hz": 122.0,
        "modal_ratios": [1.0, 1.52, 2.28, 3.15, 4.08],
        "modal_amps": [1.20, 0.80, 0.42, 0.22, 0.10],
        "modal_decays": [0.24, 0.18, 0.12, 0.08, 0.05],
        "fm": 0.35,
        "spring_f0": 92.0,
        "spring_f1": 340.0,
        "spring_boing": 5.2,
        "sub_weight": 1.15,
        "voice_f0": 190.0,
        "rattle_band": (600.0, 2200.0),
    },
    "rocket": {
        # Хронобот: precision clockwork / chrono-mechanical brass & gear character
        "base_hz": 285.0,
        "modal_ratios": [1.0, 1.50, 2.41, 3.14, 4.62],
        "modal_amps": [0.95, 0.72, 0.55, 0.38, 0.22],
        "modal_decays": [0.22, 0.18, 0.14, 0.10, 0.07],
        "fm": 0.55,
        "spring_f0": 230.0,
        "spring_f1": 740.0,
        "spring_boing": 9.0,
        "sub_weight": 0.55,
        "voice_f0": 460.0,
        "rattle_band": (2000.0, 5800.0),
    },
    "samurai": {
        # Самуробот: sharper, crisper, laminated-steel & bamboo-armor mechanical accent
        "base_hz": 255.0,
        "modal_ratios": [1.0, 1.62, 2.76, 4.12, 5.85],
        "modal_amps": [1.0, 0.74, 0.52, 0.34, 0.20],
        "modal_decays": [0.18, 0.14, 0.11, 0.08, 0.06],
        "fm": 0.75,
        "spring_f0": 185.0,
        "spring_f1": 690.0,
        "spring_boing": 8.2,
        "sub_weight": 0.68,
        "voice_f0": 280.0,
        "rattle_band": (1800.0, 5200.0),
    },
}


def synth_robot_launch(robot_id: str, idx: int, total: int, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    tier = idx / max(1, total - 1)
    dur = 0.52 + 0.18 * tier
    t = make_t(dur)
    # 1. Elastic catapult snap + sub punch
    f_start = spec["base_hz"] * (1.25 + 0.25 * tier) * rng.uniform(0.96, 1.04)
    f_end = spec["base_hz"] * 0.42
    thump = pitch_sweep(t, f_start, f_end, 0.45) * exp_decay(t, 0.09 + 0.04 * tier, 0.0015) * (0.7 + 0.35 * spec["sub_weight"])
    # 2. Rising mechanical launch whoosh / spring-piston release
    sweep_f0 = spec["spring_f0"] * rng.uniform(0.94, 1.06)
    sweep_f1 = spec["spring_f1"] * (0.85 + 0.35 * tier)
    coil = pitch_sweep(t, sweep_f0, sweep_f1, 0.65) * exp_decay(t, 0.22 + 0.08 * tier, 0.008) * 0.48
    # 3. Character modal body ring
    body = modal_cluster(t, spec["base_hz"] * (0.95 + 0.15 * tier), spec["modal_ratios"], spec["modal_amps"], spec["modal_decays"], spec["fm"]) * 0.42
    # 4. Air rush + gear ratchet micro-pulses
    noise = rng.standard_normal(len(t))
    whoosh_env = np.sin(np.pi * np.clip(t / (dur * 0.75), 0.0, 1.0)) ** 1.4 * np.exp(-t / (dur * 0.45))
    whoosh = bandpass(noise, 450.0 + 250.0 * tier, 2800.0 + 1200.0 * tier) * whoosh_env * (0.32 + 0.18 * tier)
    # Subtle stereo width via 1.8ms Haas delay + complementary detune
    sig_l = thump + coil + body + whoosh
    sig_r = thump + np.roll(coil, 32) * 0.96 + np.roll(body, 48) * 0.96 - whoosh * 0.85
    target_rms = 0.082 + 0.058 * tier
    return master_clip(sig_l, sig_r, target_rms=target_rms)


def synth_robot_spring(robot_id: str, idx: int, total: int, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    tier = idx / max(1, total - 1)
    dur = 0.38 + 0.18 * tier
    t = make_t(dur)
    f0 = spec["spring_f0"] * (0.92 + 0.22 * tier) * rng.uniform(0.95, 1.05)
    f1 = spec["spring_f1"] * (0.82 + 0.32 * tier) * rng.uniform(0.95, 1.05)
    boing_rate = spec["spring_boing"] * (0.9 + 0.25 * tier)
    # Dispersive spring chirp with elastic pitch vibrato
    u = (t / dur) ** 0.52
    vib = 1.0 + 0.14 * np.sin(2.0 * np.pi * boing_rate * t) * np.exp(-t / 0.22)
    inst_f = (f0 + (f1 - f0) * u) * vib
    phase = 2.0 * np.pi * np.cumsum(inst_f) / SR
    spring_wave = (np.sin(phase) + 0.42 * np.sin(2.0 * phase + 0.5) + 0.18 * np.sin(3.03 * phase)) * exp_decay(t, 0.15 + 0.08 * tier, 0.002)
    # Foot touchdown cushioned thump
    foot_thump = pitch_sweep(t, 160.0 + 60.0 * tier, 52.0, 0.35) * exp_decay(t, 0.055, 0.001) * (0.65 * spec["sub_weight"])
    # Pneumatic / mechanical valve puff
    puff = bandpass(rng.standard_normal(len(t)), spec["rattle_band"][0], spec["rattle_band"][1]) * exp_decay(t, 0.045 + 0.02 * tier, 0.002) * 0.22
    sig_l = spring_wave * 0.65 + foot_thump + puff
    sig_r = np.roll(spring_wave, 28) * 0.65 + foot_thump + np.roll(puff, 18)
    target_rms = 0.072 + 0.052 * tier
    return master_clip(sig_l, sig_r, target_rms=target_rms)


def synth_robot_body(robot_id: str, idx: int, total: int, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    tier = idx / max(1, total - 1)
    dur = 0.40 + 0.24 * tier
    t = make_t(dur)
    # 1. Punchy sub-bass body slam
    sub_f0 = (135.0 + 55.0 * tier) * (0.85 if robot_id == "heavy" else 1.05) * rng.uniform(0.95, 1.05)
    sub = pitch_sweep(t, sub_f0, 42.0, 0.38) * exp_decay(t, 0.08 + 0.05 * tier, 0.001) * (0.85 * spec["sub_weight"])
    # 2. Chassis modal resonance
    chassis_hz = spec["base_hz"] * (0.90 + 0.20 * tier) * rng.uniform(0.94, 1.06)
    chassis = modal_cluster(t, chassis_hz, spec["modal_ratios"], spec["modal_amps"], spec["modal_decays"], spec["fm"] * (0.8 + 0.5 * tier)) * 0.68
    # 3. Secondary mechanical rattle / bolt clatter (stronger at higher impact tiers)
    rattle = np.zeros_like(t)
    n_clacks = 2 + int(4 * tier)
    for k in range(n_clacks):
        delay_s = 0.018 + k * rng.uniform(0.022, 0.045)
        offset = int(delay_s * SR)
        if offset < len(t) - 64:
            sub_t = t[:len(t) - offset]
            clack_f = chassis_hz * rng.uniform(1.4, 2.8)
            rattle[offset:] += (0.28 / (k + 1.2)) * np.sin(2.0 * np.pi * clack_f * sub_t) * exp_decay(sub_t, 0.035, 0.001)
    grit = bandpass(rng.standard_normal(len(t)), 280.0, 2600.0) * exp_decay(t, 0.04 + 0.03 * tier, 0.001) * (0.28 + 0.20 * tier)
    sig_l = sub + chassis + rattle + grit
    sig_r = sub + np.roll(chassis, 36) + np.roll(rattle, 52) * 0.92 + grit * 0.9
    target_rms = 0.088 + 0.062 * tier
    return master_clip(sig_l, sig_r, target_rms=target_rms)


def synth_robot_head(robot_id: str, idx: int, total: int, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    tier = idx / max(1, total - 1)
    dur = 0.36 + 0.18 * tier
    t = make_t(dur)
    # Hollow cranium / dome bonk: higher fundamental + distinct hollow woodblock/helmet bell overtones
    dome_hz = (spec["base_hz"] * 1.58 + 45.0 * tier) * rng.uniform(0.95, 1.05)
    dome_ratios = [1.0, 1.56, 2.32, 3.48]
    dome_amps = [1.0, 0.72, 0.40, 0.20]
    dome_decays = [0.14 + 0.05 * tier, 0.10, 0.07, 0.04]
    bonk = modal_cluster(t, dome_hz, dome_ratios, dome_amps, dome_decays, 0.45) * 0.78
    knock = pitch_sweep(t, dome_hz * 1.8, dome_hz * 0.75, 0.3) * exp_decay(t, 0.025, 0.0008) * 0.55
    # Playful cartoon spring wobble after hard head bonk
    wobble = np.sin(2.0 * np.pi * (dome_hz * 1.15) * t + 3.5 * np.sin(2.0 * np.pi * 14.0 * t)) * exp_decay(t, 0.12 + 0.06 * tier, 0.01) * (0.22 + 0.20 * tier)
    sig_l = bonk + knock + wobble
    sig_r = np.roll(bonk, 24) + knock + np.roll(wobble, 44)
    target_rms = 0.085 + 0.060 * tier
    return master_clip(sig_l, sig_r, target_rms=target_rms)


def synth_robot_limb(robot_id: str, idx: int, total: int, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    tier = idx / max(1, total - 1)
    dur = 0.44 + 0.16 * tier
    t = make_t(dur)
    # 1. Socket pop / shear snap
    pop_f0 = (spec["base_hz"] * 2.1) * rng.uniform(0.94, 1.06)
    pop = pitch_sweep(t, pop_f0, pop_f0 * 0.32, 0.4) * exp_decay(t, 0.045, 0.001) * 0.85
    # 2. Uncoupling spring zing (descending + ascending scatter)
    zing = pitch_sweep(t, spec["spring_f1"] * 0.8, spec["spring_f0"] * 1.1, 0.55) * exp_decay(t, 0.14, 0.003) * 0.52
    # 3. Tumbling detached part clatter
    clatter = np.zeros_like(t)
    for k in range(4):
        off = int((0.03 + k * rng.uniform(0.055, 0.085)) * SR)
        if off < len(t) - 64:
            st = t[:len(t) - off]
            cf = spec["base_hz"] * rng.uniform(1.3, 2.7)
            clatter[off:] += (0.42 / (k + 1.0)) * modal_cluster(st, cf, [1.0, 1.85, 2.9], [1.0, 0.5, 0.25], [0.06, 0.04, 0.025], 0.3)
    sig_l = pop + zing + clatter
    sig_r = pop + np.roll(zing, 36) + np.roll(clatter, 48) * 0.92
    target_rms = 0.086 + 0.048 * tier
    return master_clip(sig_l, sig_r, target_rms=target_rms)


def synth_robot_voice(robot_id: str, idx: int, total: int, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    tier = idx / max(1, total - 1)
    dur = 0.38 + 0.16 * tier
    t = make_t(dur)
    f0 = spec["voice_f0"] * rng.uniform(0.94, 1.06)
    # Expressive cartoon synth-bot vocalization contour (two-syllable robotic chirp/emote)
    split = int(len(t) * rng.uniform(0.42, 0.56))
    t1 = t[:split]
    t2 = t[split:] - t[split]
    c1 = pitch_sweep(t1, f0 * 0.88, f0 * (1.18 + 0.15 * tier), 0.7)
    c2 = pitch_sweep(t2, f0 * (1.22 + 0.20 * tier), f0 * (0.92 + 0.35 * tier), 0.6)
    carrier = np.r_[c1, c2]
    # Harmonic richness + formant filtering so it sounds like a charming robot voice
    harm = carrier + 0.55 * np.sin(2.0 * np.arcsin(np.clip(carrier, -1.0, 1.0))) + 0.30 * np.cos(3.0 * np.arccos(np.clip(carrier, -1.0, 1.0)))
    f_lo = max(250.0, f0 * 1.4)
    f_hi = min(4800.0, f0 * 5.2)
    voiced = bandpass(harm, f_lo, f_hi)
    e1 = env_adsr(len(t1), 0.008, 0.04, 0.75, 0.03)
    e2 = env_adsr(len(t2), 0.008, 0.05, 0.85, 0.06)
    env = np.r_[e1, e2]
    sig_l = voiced * env
    sig_r = np.roll(sig_l, 20) * 0.98
    target_rms = 0.095 + 0.045 * tier
    return master_clip(sig_l, sig_r, target_rms=target_rms)


def synth_robot_head_launch(robot_id: str, idx: int, total: int, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    tier = idx / max(1, total - 1)
    dur = 0.95 + 0.25 * tier
    t = make_t(dur)
    # 1. Decoupler bolt pop at t=0
    pop = modal_cluster(t, spec["base_hz"] * 1.6, [1.0, 1.72, 2.85], [1.0, 0.6, 0.35], [0.08, 0.05, 0.03], 0.5) * 0.75
    # 2. Rising turbine spool-up (180 Hz -> 920 Hz)
    spool = pitch_sweep(t, 180.0 + 30.0 * tier, 780.0 + 180.0 * tier, 0.58)
    spool2 = pitch_sweep(t, 270.0 + 45.0 * tier, 1170.0 + 240.0 * tier, 0.58) * 0.45
    spool_env = env_adsr(len(t), 0.025, 0.18, 0.65, 0.28)
    # 3. Warm filtered jet ignition whoosh
    jet_noise = bandpass(rng.standard_normal(len(t)), 220.0, 2400.0 + 600.0 * tier) * spool_env * (0.55 + 0.20 * tier)
    sig_l = pop + (spool + spool2) * spool_env * 0.48 + jet_noise
    sig_r = pop + np.roll((spool + spool2) * spool_env * 0.48, 36) + np.roll(jet_noise, 24) * 0.95
    target_rms = 0.110 + 0.045 * tier
    return master_clip(sig_l, sig_r, target_rms=target_rms)


def synth_robot_rolling(robot_id: str, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    spec = ROBOT_SPECS[robot_id]
    dur = 4.6
    t = make_t(dur)
    # Periodic rotation modulation (integer cycles over loop duration for seamlessness)
    rot_hz = 5.0
    mod = 0.65 + 0.35 * np.sin(2.0 * np.pi * rot_hz * t) + 0.15 * np.sin(4.0 * np.pi * rot_hz * t + 0.7)
    noise_l = bandpass(rng.standard_normal(len(t)), 140.0, 1150.0)
    noise_r = bandpass(rng.standard_normal(len(t)), 140.0, 1150.0)
    hum = (
        0.35 * np.sin(2.0 * np.pi * (spec["base_hz"] * 0.5) * t)
        + 0.20 * np.sin(2.0 * np.pi * spec["base_hz"] * t)
    )
    sig_l = (noise_l * 0.65 + hum * 0.35) * mod
    sig_r = (noise_r * 0.65 + hum * 0.35) * mod
    return master_clip(sig_l, sig_r, target_rms=0.055, max_peak=0.45, loop=True)


# ==============================================================================
# COMMON GAMEPLAY & UI SOUNDS
# ==============================================================================
def note_hz(midi: float) -> float:
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def warm_chime(t: np.ndarray, freq: float, decay: float = 0.22, brightness: float = 0.35) -> np.ndarray:
    return (
        np.sin(2.0 * np.pi * freq * t) * exp_decay(t, decay, 0.0015)
        + brightness * np.sin(2.0 * np.pi * (freq * 2.0) * t) * exp_decay(t, decay * 0.55, 0.001)
        + (brightness * 0.45) * np.sin(2.0 * np.pi * (freq * 3.0) * t) * exp_decay(t, decay * 0.32, 0.001)
    )


def synth_common_family(family: str, rng: np.random.Generator) -> list[tuple[np.ndarray, float, bool]]:
    clips = []
    if family == "click":
        for i in range(4):
            t = make_t(0.14)
            f = 580.0 + i * 35.0
            # Crisp tactile wooden-mechanical key switch
            snap = pitch_sweep(t, f * 2.2, f * 0.65, 0.32) * exp_decay(t, 0.016, 0.0006)
            body = warm_chime(t, f, 0.042, 0.25) * 0.55
            sig = snap + body
            stereo, rms = master_clip(sig, np.roll(sig, 12), target_rms=0.075 + 0.005 * i)
            clips.append((stereo, rms, False))

    elif family == "back":
        for i in range(4):
            t = make_t(0.22)
            f1 = note_hz(74 + i * 0.5)  # D5
            f2 = note_hz(69 + i * 0.5)  # A4
            s1 = warm_chime(t, f1, 0.055, 0.28)
            off = int(0.055 * SR)
            s2 = np.zeros_like(t)
            s2[off:] = warm_chime(t[:len(t) - off], f2, 0.075, 0.22)
            sig = s1 * 0.75 + s2 * 0.90
            stereo, rms = master_clip(sig, np.roll(sig, 16), target_rms=0.078 + 0.005 * i)
            clips.append((stereo, rms, False))

    elif family == "browse":
        for i in range(4):
            t = make_t(0.13)
            f = 680.0 + i * 45.0
            tick = pitch_sweep(t, f * 1.8, f * 0.85, 0.35) * exp_decay(t, 0.014, 0.0006)
            woody = warm_chime(t, f, 0.035, 0.20) * 0.50
            sig = tick + woody
            stereo, rms = master_clip(sig, np.roll(sig, 10), target_rms=0.072 + 0.005 * i)
            clips.append((stereo, rms, False))

    elif family == "confirm":
        for i in range(4):
            t = make_t(0.32)
            n1 = note_hz(72 + i)  # C5..D#5
            n2 = note_hz(79 + i)  # G5..A#5
            s1 = warm_chime(t, n1, 0.085, 0.35)
            off = int(0.068 * SR)
            s2 = np.zeros_like(t)
            s2[off:] = warm_chime(t[:len(t) - off], n2, 0.14, 0.42)
            latch = pitch_sweep(t, 320.0, 120.0, 0.35) * exp_decay(t, 0.025, 0.001) * 0.35
            sig = s1 * 0.75 + s2 * 0.95 + latch
            stereo, rms = master_clip(sig, np.roll(sig, 20), target_rms=0.082 + 0.008 * i)
            clips.append((stereo, rms, False))

    elif family == "module_install":
        for i in range(3):
            t = make_t(0.52)
            sig = np.zeros_like(t)
            notes = [67 + i, 71 + i, 74 + i, 79 + i]
            for k, m in enumerate(notes):
                off = int(k * 0.055 * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(m), 0.12, 0.38) * (0.65 + 0.1 * k)
            stereo, rms = master_clip(sig, np.roll(sig, 24), target_rms=0.078 + 0.008 * i)
            clips.append((stereo, rms, False))

    elif family == "module_remove":
        for i in range(3):
            t = make_t(0.44)
            sig = np.zeros_like(t)
            notes = [76 + i, 72 + i, 67 + i]
            for k, m in enumerate(notes):
                off = int(k * 0.065 * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(m), 0.11, 0.28) * 0.75
            stereo, rms = master_clip(sig, np.roll(sig, 22), target_rms=0.074 + 0.007 * i)
            clips.append((stereo, rms, False))

    elif family == "countdown":
        for i in range(3):
            t = make_t(0.26)
            f = note_hz(79 + i)  # G5..A5
            sig = warm_chime(t, f, 0.095, 0.30)
            stereo, rms = master_clip(sig, np.roll(sig, 16), target_rms=0.070 + 0.008 * i)
            clips.append((stereo, rms, False))

    elif family == "go":
        # THE GIANT FINGER FLICK ("ЩЕЛБАН")!
        for i in range(4):
            tier = i / 3.0
            t = make_t(0.46 + 0.06 * tier)
            # 1. Elastic finger snap-thwack transient
            thwack = pitch_sweep(t, 420.0 + 90.0 * tier, 68.0, 0.36) * exp_decay(t, 0.065, 0.0008) * 1.1
            # 2. Crisp nail/metallic flick ping
            ping = modal_cluster(t, 520.0 + 70.0 * tier, [1.0, 1.5, 2.25, 3.2], [0.9, 0.65, 0.4, 0.22], [0.14, 0.10, 0.07, 0.05], 0.4) * 0.75
            # 3. Pressurized air impulse whoosh
            whoosh = bandpass(rng.standard_normal(len(t)), 350.0, 3200.0) * exp_decay(t, 0.11 + 0.04 * tier, 0.004) * (0.45 + 0.15 * tier)
            sig_l = thwack + ping + whoosh
            sig_r = thwack + np.roll(ping, 26) + np.roll(whoosh, 18) * 0.92
            stereo, rms = master_clip(sig_l, sig_r, target_rms=0.092 + 0.015 * tier)
            clips.append((stereo, rms, False))

    elif family == "energy":
        # 7 tiered spin-charge & kinetic-boost release clips (0.0 -> 1.0)
        for i in range(7):
            tier = i / 6.0
            dur = 0.26 + 0.24 * tier
            t = make_t(dur)
            f_start = note_hz(60 + i * 2.5)
            f_end = note_hz(67 + i * 3.0)
            # Smooth dynamo spin-up sweep + harmonic shimmer
            sweep1 = pitch_sweep(t, f_start, f_end, 0.65) * env_adsr(len(t), 0.012, 0.06, 0.7, 0.08)
            sweep2 = pitch_sweep(t, f_start * 1.5, f_end * 1.5, 0.65) * env_adsr(len(t), 0.015, 0.06, 0.5, 0.08) * (0.35 + 0.35 * tier)
            spark = warm_chime(t, f_end * 2.0, 0.09 + 0.06 * tier, 0.4) * (0.25 + 0.45 * tier)
            sig_l = sweep1 * 0.65 + sweep2 * 0.45 + spark
            sig_r = np.roll(sweep1, 20) * 0.65 + np.roll(sweep2, 34) * 0.45 + np.roll(spark, 14)
            stereo, rms = master_clip(sig_l, sig_r, target_rms=0.068 + 0.042 * tier)
            clips.append((stereo, rms, False))

    elif family == "flight":
        # Seamless 4.8s rocket-head jet propulsion loop
        dur = 4.8
        t = make_t(dur)
        mod = 0.78 + 0.22 * np.sin(2.0 * np.pi * 2.5 * t) + 0.10 * np.sin(2.0 * np.pi * 5.0 * t)
        jet_l = bandpass(rng.standard_normal(len(t)), 180.0, 1850.0) * mod
        jet_r = bandpass(rng.standard_normal(len(t)), 180.0, 1850.0) * mod
        turbine = (
            0.32 * np.sin(2.0 * np.pi * 220.0 * t + 0.4 * np.sin(2.0 * np.pi * 2.5 * t))
            + 0.22 * np.sin(2.0 * np.pi * 330.0 * t)
            + 0.12 * np.sin(2.0 * np.pi * 440.0 * t)
        )
        sig_l = jet_l * 0.62 + turbine * 0.38
        sig_r = jet_r * 0.62 + np.roll(turbine, 24) * 0.38
        stereo, rms = master_clip(sig_l, sig_r, target_rms=0.115, max_peak=0.58, loop=True)
        clips.append((stereo, rms, True))

    elif family == "wilhelm":
        for i in range(2):
            t = make_t(1.02)
            # Cartoon falling robot Doppler whistle-scream ("WaaaAAAH-ooo!")
            vib = 1.0 + 0.045 * np.sin(2.0 * np.pi * 16.0 * t)
            f_curve = (720.0 + 180.0 * np.sin(np.pi * np.clip(t / 0.28, 0.0, 1.0)) - 420.0 * (t / 1.02) ** 1.3) * vib
            phase = 2.0 * np.pi * np.cumsum(f_curve) / SR
            voice = np.sin(phase) + 0.55 * np.sin(2.0 * phase) + 0.28 * np.sin(3.0 * phase)
            formant = bandpass(voice, 500.0, 3200.0) * env_adsr(len(t), 0.025, 0.15, 0.78, 0.22)
            stereo, rms = master_clip(formant, np.roll(formant, 28), target_rms=0.125 + 0.01 * i)
            clips.append((stereo, rms, False))

    elif family == "coin":
        for i in range(4):
            t = make_t(0.34)
            f1 = note_hz(83 + i * 0.5)  # B5
            f2 = note_hz(88 + i * 0.5)  # E6
            c1 = warm_chime(t, f1, 0.07, 0.48)
            off = int(0.052 * SR)
            c2 = np.zeros_like(t)
            c2[off:] = warm_chime(t[:len(t) - off], f2, 0.16, 0.52)
            sig = c1 * 0.72 + c2 * 0.95
            stereo, rms = master_clip(sig, np.roll(sig, 18), target_rms=0.078 + 0.006 * i)
            clips.append((stereo, rms, False))

    elif family == "purchase":
        for i in range(4):
            t = make_t(0.58)
            sig = pitch_sweep(t, 280.0, 110.0, 0.4) * exp_decay(t, 0.035, 0.001) * 0.45
            chord = [72 + i, 76 + i, 79 + i, 84 + i]
            for k, m in enumerate(chord):
                off = int((0.03 + k * 0.048) * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(m), 0.18, 0.45) * 0.65
            stereo, rms = master_clip(sig, np.roll(sig, 24), target_rms=0.082 + 0.007 * i)
            clips.append((stereo, rms, False))

    elif family == "unlock":
        for i in range(4):
            t = make_t(0.72)
            sig = np.zeros_like(t)
            notes = [69 + i, 73 + i, 76 + i, 81 + i, 85 + i]
            for k, m in enumerate(notes):
                off = int(k * 0.068 * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(m), 0.22, 0.48) * (0.55 + 0.08 * k)
            stereo, rms = master_clip(sig, np.roll(sig, 28), target_rms=0.084 + 0.006 * i)
            clips.append((stereo, rms, False))

    elif family == "star":
        for i in range(4):
            t = make_t(0.46)
            sig = np.zeros_like(t)
            notes = [76 + i, 83 + i, 88 + i]  # E5 - B5 - E6
            for k, m in enumerate(notes):
                off = int(k * 0.062 * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(m), 0.18, 0.50) * (0.68 + 0.12 * k)
            stereo, rms = master_clip(sig, np.roll(sig, 22), target_rms=0.082 + 0.006 * i)
            clips.append((stereo, rms, False))

    elif family == "all_stars":
        for i in range(4):
            t = make_t(0.84)
            sig = np.zeros_like(t)
            notes = [72 + i, 76 + i, 79 + i, 83 + i, 86 + i, 91 + i]
            for k, m in enumerate(notes):
                off = int(k * 0.065 * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(m), 0.24, 0.52) * (0.52 + 0.07 * k)
            stereo, rms = master_clip(sig, np.roll(sig, 30), target_rms=0.088 + 0.006 * i)
            clips.append((stereo, rms, False))

    elif family == "record":
        for i in range(4):
            t = make_t(0.88)
            sig = np.zeros_like(t)
            notes = [67 + i, 72 + i, 76 + i, 79 + i, 84 + i]
            for k, m in enumerate(notes):
                off = int(k * 0.075 * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(m), 0.25, 0.46) * (0.58 + 0.08 * k)
            stereo, rms = master_clip(sig, np.roll(sig, 28), target_rms=0.085 + 0.007 * i)
            clips.append((stereo, rms, False))

    elif family == "victory":
        for i in range(4):
            t = make_t(0.86)
            sig = np.zeros_like(t)
            # Punchy uplifting cartoon brass-marimba fanfare (C5 - E5 - G5 - C6 chordal stinger)
            arp = [(0.00, 72 + i, 0.14), (0.09, 76 + i, 0.14), (0.18, 79 + i, 0.16), (0.28, 84 + i, 0.38)]
            for delay_s, midi_n, dec in arp:
                off = int(delay_s * SR)
                st = t[:len(t) - off]
                sig[off:] += warm_chime(st, note_hz(midi_n), dec, 0.48) * 0.72
                sig[off:] += warm_chime(st, note_hz(midi_n - 12), dec * 0.9, 0.25) * 0.38
            stereo, rms = master_clip(sig, np.roll(sig, 26), target_rms=0.088 + 0.007 * i)
            clips.append((stereo, rms, False))

    elif family == "defeat":
        for i in range(4):
            t = make_t(0.78)
            sig = np.zeros_like(t)
            # Playful descending cartoon wind-down (G4 -> F#4 -> F4 -> E4 droop)
            steps = [(0.00, 67 - i * 0.5, 0.14), (0.15, 66 - i * 0.5, 0.14), (0.30, 65 - i * 0.5, 0.32)]
            for delay_s, midi_n, dec in steps:
                off = int(delay_s * SR)
                st = t[:len(t) - off]
                f0 = note_hz(midi_n)
                f1 = f0 * (0.92 if delay_s > 0.25 else 0.98)
                tone = pitch_sweep(st, f0, f1, 0.7) * exp_decay(st, dec, 0.006)
                tone2 = pitch_sweep(st, f0 * 2.0, f1 * 2.0, 0.7) * exp_decay(st, dec * 0.7, 0.006) * 0.35
                sig[off:] += (tone + tone2) * 0.65
            stereo, rms = master_clip(sig, np.roll(sig, 24), target_rms=0.076 + 0.006 * i)
            clips.append((stereo, rms, False))

    return clips


def main() -> None:
    rng = np.random.default_rng(20260418)

    # 1. Clean up old root Audio/ directory if present
    if RAW_AUDIO_DIR.exists():
        shutil.rmtree(RAW_AUDIO_DIR)
        print("Removed obsolete root Audio/ directory.")

    # 2. Clean up old .ogg files in game/assets/audio/ (preserve .ogg.import for matching paths or let Godot reimport)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    existing_imports = {}
    for imp in OUT_DIR.rglob("*.ogg.import"):
        existing_imports[imp.stem] = imp.read_text(encoding="utf-8")
    for p in list(OUT_DIR.rglob("*.ogg")) + list(OUT_DIR.rglob("*.ogg.import")):
        p.unlink()

    banks: dict[str, list[dict]] = {}
    profiles: dict[str, dict[str, str]] = {}

    def register_family(family_key: str, prefix_name: str, items: list[tuple[np.ndarray, float, bool]]) -> None:
        # Sort by energy ascending so tier 0.0 -> 1.0 is strictly monotonic
        items_sorted = sorted(items, key=lambda x: x[1])
        entries = []
        for idx, (stereo, rms, is_loop) in enumerate(items_sorted):
            rel_path = f"{family_key}_{idx + 1:02d}.ogg"
            abs_path = OUT_DIR / rel_path
            write_ogg(abs_path, stereo)
            tier = idx / max(1, len(items_sorted) - 1)
            entries.append({
                "path": f"res://assets/audio/{rel_path}",
                "energy": round(rms, 4),
                "duration": round(stereo.shape[1] / SR, 3),
                "loop": bool(is_loop),
                "tier": round(tier, 4),
            })
        banks[family_key] = entries

    # 3. Synthesize all 5 playable robot banks
    for robot_id in ["tin", "hopper", "heavy", "rocket", "samurai"]:
        profiles[robot_id] = {}
        robot_events = [
            ("launch", 6, synth_robot_launch),
            ("spring", 8, synth_robot_spring),
            ("body", 8, synth_robot_body),
            ("head", 6, synth_robot_head),
            ("limb", 6, synth_robot_limb),
            ("voice", 6, synth_robot_voice),
            ("head_launch", 5, synth_robot_head_launch),
        ]
        for ev_name, count, fn in robot_events:
            fkey = f"{robot_id}/{ev_name}"
            profiles[robot_id][ev_name] = fkey
            raw_clips = []
            for idx in range(count):
                stereo, rms = fn(robot_id, idx, count, rng)
                raw_clips.append((stereo, rms, False))
            register_family(fkey, ev_name, raw_clips)

        # Rolling loop per robot
        rkey = f"{robot_id}/rolling"
        profiles[robot_id]["rolling"] = rkey
        rstereo, rrms = synth_robot_rolling(robot_id, rng)
        register_family(rkey, "rolling", [(rstereo, rrms, True)])

    # 4. Synthesize all Common events
    common_events = [
        "click", "back", "browse", "confirm", "module_install", "module_remove",
        "countdown", "go", "coin", "purchase", "unlock", "star", "all_stars",
        "record", "victory", "defeat", "energy", "flight", "wilhelm",
    ]
    for ev in common_events:
        fkey = f"common/{ev}"
        items = synth_common_family(ev, rng)
        register_family(fkey, ev, items)

    manifest = {
        "banks": banks,
        "profiles": profiles,
        "wilhelm_height": 1800.0,
        "wilhelm_probability": 0.05,
        "voice_probability": 0.18,
        "missing_robot_banks": [],
        "music_excluded": True,
        "audio_version": "v24_procedural_redesign",
    }
    (OUT_DIR / "bank.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    total_files = sum(len(v) for v in banks.values())
    total_bytes = sum(p.stat().st_size for p in OUT_DIR.rglob("*.ogg"))
    print(f"Generated {total_files} Ogg Vorbis clips across {len(banks)} families ({total_bytes / 1024:.1f} KB total).")


if __name__ == "__main__":
    main()
