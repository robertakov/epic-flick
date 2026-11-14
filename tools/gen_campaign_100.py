import json, runpy
from pathlib import Path

CAPS = runpy.run_path(str(Path(__file__).with_name("star_caps.py")))

ROOT = Path(r"G:\Godot\EpicShalban\game\config")
MAIN_PATH = ROOT / "campaign" / "main.json"
STARS_PATH = ROOT / "campaign" / "stars.json"
ROSTER_PATH = ROOT / "enemy_roster.json"

main_data = json.loads(MAIN_PATH.read_text(encoding="utf-8"))
stars_data = json.loads(STARS_PATH.read_text(encoding="utf-8"))
roster_data = json.loads(ROSTER_PATH.read_text(encoding="utf-8"))

# Keep only r1..r40 from existing files before expanding to r100
nodes_40 = [n for n in main_data["nodes"] if int(n["round"]) <= 40]
for n in nodes_40:
    r = int(n["round"])
    if r == 40:
        n["next"] = ["r41"]
    # Gently strengthen r11..r39 AI skill and bands while keeping r1..r10 and r40 test anchors
    if 11 <= r <= 39 and n["difficulty"] != "boss":
        for e in n["enemies"]:
            old_sk = float(e["skill"])
            boost = 0.035 if r < 25 else 0.045
            e["skill"] = round(min(0.955, old_sk + boost), 3)
            e["target_min_distance"] = int(round(float(e["target_min_distance"]) * 1.08 / 5.0) * 5)
            e["target_max_distance"] = int(round(float(e["target_max_distance"]) * 1.10 / 5.0) * 5)

# Irregular spike / pressure rounds in r41..r100 (non-periodic intervals: +6, +5, +6, +5, +7, +4, +7, +6, +5, +7, +4)
# Combined with r1..r40 pressure rounds: r5, r12, r17, r24, r29, r36
PRESSURE_ROUNDS_41_100 = {42, 47, 53, 58, 65, 69, 76, 82, 87, 94, 98}
HARD_ROUNDS_41_100 = {44, 47, 49, 53, 56, 63, 65, 68, 74, 76, 79, 82, 85, 89, 92, 94, 97, 98, 99}
TWO_ENEMY_ROUNDS_41_100 = {43, 46, 49, 52, 55, 59, 62, 66, 68, 72, 75, 78, 83, 86, 89, 93, 96, 99}
BREATHER_ROUNDS_41_100 = {41, 43, 48, 51, 54, 59, 61, 66, 71, 77, 81, 83, 88, 91, 95}

BOSS_SPECS = {
    50: {
        "title": "Босс: Медный Барон",
        "reward_first": 1650,
        "reward_skin": "tin_copper",
        "enemy": {"name": "Медный Барон", "robot": "tin", "skill": 0.875, "lean": 18, "greed": 0.76, "skin": "tin_copper", "target_min_distance": 430, "target_max_distance": 890},
    },
    60: {
        "title": "Босс: Изумрудный Прыгун",
        "reward_first": 1850,
        "reward_skin": "hopper_lime",
        "enemy": {"name": "Изумрудный Прыгун", "robot": "hopper", "skill": 0.905, "lean": 19, "greed": 0.80, "skin": "hopper_lime", "target_min_distance": 460, "target_max_distance": 935},
    },
    70: {
        "title": "Босс: Железный Колосс",
        "reward_first": 2100,
        "reward_skin": "heavy_iron",
        "enemy": {"name": "Железный Колосс", "robot": "heavy", "skill": 0.930, "lean": 17, "greed": 0.83, "skin": "heavy_iron", "target_min_distance": 490, "target_max_distance": 980},
    },
    80: {
        "title": "Босс: Хронос-Титан",
        "reward_first": 2400,
        "reward_skin": "samurai_shogun",
        "enemy": {"name": "Хронос-Титан", "robot": "rocket", "skill": 0.955, "lean": 20, "greed": 0.86, "skin": "", "target_min_distance": 515, "target_max_distance": 1030},
    },
    90: {
        "title": "Босс: Тень Сёгуна",
        "reward_first": 2800,
        "reward_skin": "samurai_shogun",
        "enemy": {"name": "Тень Сёгуна", "robot": "samurai", "skill": 0.975, "lean": 18, "greed": 0.89, "skin": "samurai_shogun", "target_min_distance": 545, "target_max_distance": 1085},
    },
    100: {
        "title": "Финал: Император Щелбана",
        "reward_first": 3600,
        "reward_skin": "samurai_shogun",
        "enemy": {"name": "Император Щелбана", "robot": "samurai", "skill": 0.99, "lean": 19, "greed": 0.92, "skin": "samurai_shogun", "target_min_distance": 580, "target_max_distance": 1160},
    },
}

# Identity -> valid archetypes
IDENTITY_POOL = [
    ("vampire", "hopper"),
    ("cowboy", "heavy"),
    ("devil", "heavy"),
    ("tiger", "hopper"),
    ("shark", "rocket"),
    ("cowboy", "samurai"),
    ("tiger", "heavy"),
    ("shark", "hopper"),
    ("devil", "tin"),
    ("vampire", "tin"),
]

ENEMY_NAMES_RU = {
    "devil": "Чёрт",
    "vampire": "Вампир",
    "cowboy": "Ковбой",
    "tiger": "Тигр",
    "shark": "Акула",
}

new_nodes = list(nodes_40)
roster_rounds = {k: v for k, v in roster_data["rounds"].items() if int(k[1:]) <= 40}

normal_reward = 195
for r in range(41, 101):
    rid = f"r{r}"
    nxt = [f"r{r + 1}"] if r < 100 else []
    if r in BOSS_SPECS:
        bs = BOSS_SPECS[r]
        new_nodes.append({
            "id": rid,
            "type": "race",
            "round": r,
            "difficulty": "boss",
            "next": nxt,
            "title": bs["title"],
            "reward_first": bs["reward_first"],
            "reward_skin": bs["reward_skin"],
            "enemies": [dict(bs["enemy"])],
        })
        continue

    is_hard = r in HARD_ROUNDS_41_100
    is_pressure = r in PRESSURE_ROUNDS_41_100
    is_breather = r in BREATHER_ROUNDS_41_100
    is_two = r in TWO_ENEMY_ROUNDS_41_100

    # Wave-like skill progression from r41..r99
    progress = (r - 41) / 58.0
    base_skill = 0.62 + 0.31 * progress
    if is_breather:
        base_skill -= 0.065
    elif is_pressure:
        base_skill += 0.055
    elif is_hard:
        base_skill += 0.035
    else:
        # Subtle wave modulation
        wave = ((r * 7) % 5 - 2) * 0.012
        base_skill += wave
    base_skill = round(max(0.54, min(0.982, base_skill)), 3)

    # Target distance band
    min_d = int(round((330 + 185 * progress + (35 if is_pressure else (20 if is_hard else (-30 if is_breather else 0)))) / 5.0) * 5)
    max_d = int(round((680 + 360 * progress + (70 if is_pressure else (45 if is_hard else (-55 if is_breather else 0)))) / 5.0) * 5)

    if not is_hard:
        normal_reward += 5 if (r % 2 == 1) else 0
        reward_first = normal_reward
    else:
        reward_first = normal_reward + 55 + (15 if is_pressure else 0)

    # Pick opponent identity & archetype
    idx1 = (r * 3 + (2 if is_pressure else 0)) % len(IDENTITY_POOL)
    id1, arch1 = IDENTITY_POOL[idx1]
    lean1 = 15 + ((r * 5) % 8)
    greed1 = round(min(0.86, 0.56 + 0.26 * progress + (0.04 if is_pressure else 0.0)), 2)

    enemies = [{
        "name": ENEMY_NAMES_RU[id1],
        "robot": arch1,
        "skill": base_skill,
        "lean": lean1,
        "greed": greed1,
        "skin": "",
        "target_min_distance": min_d,
        "target_max_distance": max_d,
    }]
    r_slots = [{
        "id": id1,
        "archetype": arch1,
        "pressure": is_pressure,
    }]

    if is_two:
        idx2 = (idx1 + 3 + (r % 4)) % len(IDENTITY_POOL)
        id2, arch2 = IDENTITY_POOL[idx2]
        sk2 = round(max(0.48, base_skill - 0.038), 3)
        lean2 = 14 + ((r * 7 + 3) % 8)
        greed2 = round(max(0.48, greed1 - 0.03), 2)
        enemies.append({
            "name": ENEMY_NAMES_RU[id2],
            "robot": arch2,
            "skill": sk2,
            "lean": lean2,
            "greed": greed2,
            "skin": "",
            "target_min_distance": min_d,
            "target_max_distance": max_d + 15,
        })
        r_slots.append({
            "id": id2,
            "archetype": arch2,
            "pressure": False,
        })

    new_nodes.append({
        "id": rid,
        "type": "race",
        "round": r,
        "difficulty": "hard" if is_hard else "normal",
        "next": nxt,
        "title": f"Раунд {r}",
        "reward_first": reward_first,
        "enemies": enemies,
    })
    roster_rounds[rid] = r_slots

main_data["nodes"] = new_nodes
roster_data["rounds"] = roster_rounds
# Compute pressure_normal_ordinals across all non-boss rounds
non_boss = [n["id"] for n in new_nodes if n["difficulty"] != "boss"]
ordinals = []
for idx, rid in enumerate(non_boss, start=1):
    slots = roster_rounds.get(rid, [])
    if any(s.get("pressure", False) for s in slots):
        ordinals.append(idx)
roster_data["pressure_normal_ordinals"] = ordinals
roster_data["pressure_decisions"] = {
    "angle_error_deg": 0.45,
    "timing_error": 0.45,
    "blunder_chance": 0.2,
    "naive_slope_mix": 0.45,
    "reaction_delay": 0.6,
    "replan_interval": 0.75,
    "plan_tolerance": 0.75,
    "form_spread": 0.45,
    "long_run_skill_drop": 0.55,
}

# ---------------- Generate 300 stars (r1..r100) ----------------
# Keep r1..r40 stars unchanged, and generate r41..r100 using all 10 new types + 15 existing types
INCOMPATIBLE = [
    {"GOOD_LANDING_STREAK", "CHARGED_LANDING_STREAK"},
    {"CLEAN_START", "SURVIVAL_HP"},
    {"TOTAL_GOOD_LANDINGS", "CHARGED_LANDING_STREAK"},
    {"FLICK_MAX_POWER", "FLICK_MIN_AND_WIN"},
    {"CLEAN_START", "ROCKET_HEAD_DISTANCE"},
    {"SURVIVAL_HP", "ROCKET_HEAD_DISTANCE"},
    {"BAD_LANDING_LIMIT", "ROCKET_HEAD_DISTANCE"},
    {"CLEAN_START", "HEAD_LANDINGS"},
    {"BAD_LANDING_LIMIT", "HEAD_LANDINGS"},
]

CAT_A = [
    "ROCKET_HEAD_DISTANCE",
    "WIN_MARGIN_OVER",
    "DISTANCE",
    "CLEAN_START",
    "LIMB_LIMIT",
    "SURVIVAL_HP",
]
CAT_B = [
    "HEAD_LANDINGS",
    "NO_TOUCH_AND_WIN",
    "BAD_LANDING_LIMIT",
    "GOOD_LANDING_STREAK",
    "TOTAL_GOOD_LANDINGS",
    "RECOVERY",
    "CLEAN_SECTION",
]
CAT_C = [
    "CCW_TURNS",
    "MAX_HEIGHT_M",
    "FLICK_MAX_POWER",
    "FLICK_MIN_AND_WIN",
    "CHARGE_TARGET",
    "CHARGED_LANDING",
    "CHARGED_LANDING_STREAK",
    "AIR_TIME",
    "LONG_JUMP",
    "SPEED_TARGET",
]

new_stars = {}
seen_triplets = set()
prev_types = set()

for r in range(1, 41):
    rid = f"r{r}"
    rows = stars_data[rid]
    new_stars[rid] = rows
    t_list = sorted(ch["type"] for ch in rows)
    seen_triplets.add(",".join(t_list))
    prev_types = set(t_list)

node_by_id = {n["id"]: n for n in new_nodes}
usage_counts = {t: 0 for t in CAT_A + CAT_B + CAT_C}
for r in range(1, 41):
    for ch in new_stars[f"r{r}"]:
        usage_counts[ch["type"]] += 1

def make_challenge(ctype: str, r: int, reward: int) -> dict:
    prog = (r - 41) / 59.0
    if ctype == "ROCKET_HEAD_DISTANCE":
        # First appearance uses exact 100m from prompt
        m_vals = [100, 90, 110, 120, 100, 130, 140]
        return {"type": ctype, "m": m_vals[usage_counts[ctype] % len(m_vals)], "reward": reward}
    if ctype == "WIN_MARGIN_OVER":
        # First appearance uses exact 200m from prompt
        m_vals = [200, 160, 180, 200, 220, 240, 250]
        return {"type": ctype, "m": m_vals[usage_counts[ctype] % len(m_vals)], "reward": reward}
    if ctype == "DISTANCE":
        return {"type": ctype, "m": int(round((380 + 220 * prog) / 10.0) * 10), "reward": reward}
    if ctype == "CLEAN_START":
        return {"type": ctype, "m": int(round((140 + 70 * prog) / 5.0) * 5), "reward": reward}
    if ctype == "LIMB_LIMIT":
        return {"type": ctype, "m": int(round((220 + 110 * prog) / 10.0) * 10), "n": 1 if r % 2 == 0 else 2, "reward": reward}
    if ctype == "SURVIVAL_HP":
        return {"type": ctype, "m": int(round((200 + 90 * prog) / 10.0) * 10), "hp": 50 if r < 70 else 60, "reward": reward}
    if ctype == "HEAD_LANDINGS":
        # First appearance uses exact 2 from prompt
        n_vals = [2, 2, 3, 2, 3, 2]
        return {"type": ctype, "n": n_vals[usage_counts[ctype] % len(n_vals)], "reward": reward}
    if ctype == "NO_TOUCH_AND_WIN":
        return {"type": ctype, "s": 3.5, "reward": reward}
    if ctype == "BAD_LANDING_LIMIT":
        return {"type": ctype, "m": int(round((210 + 90 * prog) / 10.0) * 10), "n": 1 if r < 75 else 0, "reward": reward}
    if ctype == "GOOD_LANDING_STREAK":
        return {"type": ctype, "n": 6 if r < 65 else (7 if r < 85 else 8), "reward": reward}
    if ctype == "TOTAL_GOOD_LANDINGS":
        return {"type": ctype, "n": 8 if r < 65 else (9 if r < 85 else 10), "reward": reward}
    if ctype == "RECOVERY":
        return {"type": ctype, "n": 2 if r < 75 else 3, "reward": reward}
    if ctype == "CLEAN_SECTION":
        return {"type": ctype, "m": int(round((210 + 90 * prog) / 10.0) * 10), "reward": reward}
    if ctype == "CCW_TURNS":
        # First appearance uses exact 2 turns from prompt
        n_vals = [2, 2, 3, 2, 3, 4, 2]
        return {"type": ctype, "n": n_vals[usage_counts[ctype] % len(n_vals)], "reward": reward}
    if ctype == "MAX_HEIGHT_M":
        # hard cap 30 m (star_caps.py): 24 m rising to 30 m, never above
        return {"type": ctype, "m": CAPS["height_for_round"](r), "reward": reward}
    if ctype == "FLICK_MAX_POWER":
        return {"type": ctype, "reward": reward}
    if ctype == "FLICK_MIN_AND_WIN":
        return {"type": ctype, "reward": reward}
    if ctype == "CHARGE_TARGET":
        return {"type": ctype, "pct": 90 if r < 70 else 95, "reward": reward}
    if ctype == "CHARGED_LANDING":
        return {"type": ctype, "pct": 85 if r < 70 else 90, "reward": reward}
    if ctype == "CHARGED_LANDING_STREAK":
        return {"type": ctype, "n": 3 if r < 75 else 4, "pct": 65 if r < 75 else 70, "reward": reward}
    if ctype == "AIR_TIME":
        return {"type": ctype, "s": round(2.8 + 0.4 * prog, 1), "reward": reward}
    if ctype == "LONG_JUMP":
        return {"type": ctype, "m": int(round((65 + 20 * prog) / 5.0) * 5), "reward": reward}
    if ctype == "SPEED_TARGET":
        # hard cap 100 (star_caps.py)
        return {"type": ctype, "kmh": CAPS["speed_for_round"](r), "reward": reward}
    raise ValueError(f"Unknown type {ctype}")

NEW_10_TYPES = {
    "ROCKET_HEAD_DISTANCE", "WIN_MARGIN_OVER",
    "HEAD_LANDINGS", "NO_TOUCH_AND_WIN",
    "CCW_TURNS", "MAX_HEIGHT_M", "FLICK_MAX_POWER", "FLICK_MIN_AND_WIN",
}

for r in range(41, 101):
    rid = f"r{r}"
    node = node_by_id[rid]
    num_enemies = len(node["enemies"])
    is_boss = node["difficulty"] == "boss"
    reward = 110 if is_boss else (55 + ((r - 41) // 6) * 5)

    # Sort candidate types in each category prioritizing least-used (with a bonus for the 8 new types so each is well represented)
    def priority_key(t: str, salt: int):
        new_bonus = -3 if (t in NEW_10_TYPES and usage_counts[t] < 7) else 0
        return (usage_counts[t] + new_bonus, (hash((t, r, salt)) & 0xffff))

    a_cands = sorted(CAT_A, key=lambda t: priority_key(t, 1))
    b_cands = sorted(CAT_B, key=lambda t: priority_key(t, 2))
    c_cands = sorted(CAT_C, key=lambda t: priority_key(t, 3))

    chosen = None
    for ta in a_cands:
        for tb in b_cands:
            for tc in c_cands:
                tset = {ta, tb, tc}
                if any(pair.issubset(tset) for pair in INCOMPATIBLE):
                    continue
                if len(tset.intersection(prev_types)) > 1:
                    continue
                key = ",".join(sorted(tset))
                if key in seen_triplets:
                    continue
                chosen = (ta, tb, tc, key)
                break
            if chosen:
                break
        if chosen:
            break

    assert chosen is not None, f"Could not find valid star triple for {rid}"
    ta, tb, tc, key = chosen
    seen_triplets.add(key)
    prev_types = {ta, tb, tc}
    rows = [
        make_challenge(ta, r, reward),
        make_challenge(tb, r, reward),
        make_challenge(tc, r, reward),
    ]
    for ch in rows:
        usage_counts[ch["type"]] += 1
    new_stars[rid] = rows

# hard caps also apply to the copied r1..r40 stars; nothing above a cap is ever written
for rid in new_stars:
    for i, ch in enumerate(new_stars[rid]):
        if ch["type"] == "SPEED_TARGET" and not CAPS["within_caps"](ch):
            new_stars[rid][i] = dict(ch, kmh=CAPS["speed_for_round"](int(rid[1:])))
        new_stars[rid][i] = CAPS["clamp"](new_stars[rid][i])
        assert CAPS["within_caps"](new_stars[rid][i]), (rid, new_stars[rid][i])

MAIN_PATH.write_text(json.dumps(main_data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
STARS_PATH.write_text(json.dumps(new_stars, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
ROSTER_PATH.write_text(json.dumps(roster_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Generated {len(main_data['nodes'])} rounds, {len(new_stars) * 3} stars, {len(roster_data['rounds'])} non-boss roster entries.")
print("New challenge usage counts:")
for t in sorted(NEW_10_TYPES):
    print(f"  {t}: {usage_counts[t]}")
