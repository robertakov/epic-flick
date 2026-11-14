"""v33 campaign star challenge rebalance (development-only, deterministic, never invoked by the game).

Problem (v32): every round had exactly one A/B/C challenge and the early B ("landing") pool was only
TOTAL_GOOD_LANDINGS + GOOD_LANDING_STREAK (other B types unlocked at r6..r10), so r1..r5 ALL asked "land on your feet
N times" (7 / 6-7). Each feet landing costs damage_feet = 15 HP (DamageController, legs are a damage zone), so 7 feet
landings exceed the starter robot's HP.

New selection (same three slots A run-outcome/survival, B landing & control, C air/charge/speed):
  * unlock round per type (UNLOCK) - FLICK_MAX_POWER and CCW_TURNS now also early (both taught by the v33 tutorial);
  * anti-repetition: a TYPE is never on consecutive rounds when another valid option exists, preferably >= 3 rounds
    apart (relaxed step by step only when the pool is empty); the behaviour FAMILY (FAMILIES) is also not repeated on
    the next round; numeric variants are the same type;
  * one round never mixes two types of the same family, never an incompatible pair (INCOMPATIBLE);
  * least-used type first (weighted by pool size), deterministic seeded tie-break (SEED);
  * thresholds: GOOD_LANDING_STREAK 3 / 4 / 5 and TOTAL_GOOD_LANDINGS 4 / 5 / 5 (r1-33 / r34-66 / r67-100), see the
    survivability reasoning in AI_HANDOFF v33; SPEED / MAX_HEIGHT by star_caps.py curves; NO_TOUCH_AND_WIN s=3.5;
    every other type keeps its existing calibrated value from the nearest earlier round of the old file (or its
    earliest value when it is now unlocked earlier). Rewards per round/slot are kept from the old file.
Usage:  python -I tools/rebalance_stars_v33.py [--write]
"""
import collections, json, random, runpy, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATH = ROOT / "game/config/campaign/stars.json"
# calibrated values come from the frozen v32 file (never from this tool's own output -> reruns are identical)
SOURCE = Path(__file__).with_name("stars_v32_source.json")
CAPS = runpy.run_path(str(Path(__file__).with_name("star_caps.py")))
SEED = 330033
REMOVED = {"FINISH_WITHIN_ENEMY", "KEEP_ENEMY_IN_VIEW"}

SLOTS = {   # = StarChallenges.TYPES categories (the game rejects rounds that are not one A, one B, one C)
    "A": ["DISTANCE", "CLEAN_START", "SURVIVAL_HP", "LIMB_LIMIT", "WIN_MARGIN_OVER", "ROCKET_HEAD_DISTANCE"],
    "B": ["TOTAL_GOOD_LANDINGS", "GOOD_LANDING_STREAK", "RECOVERY", "BAD_LANDING_LIMIT", "CLEAN_SECTION",
          "HEAD_LANDINGS", "NO_TOUCH_AND_WIN"],
    "C": ["CHARGE_TARGET", "AIR_TIME", "SPEED_TARGET", "LONG_JUMP", "CHARGED_LANDING", "CHARGED_LANDING_STREAK",
          "FLICK_MAX_POWER", "CCW_TURNS", "MAX_HEIGHT_M", "FLICK_MIN_AND_WIN"],
}
UNLOCK = {"DISTANCE": 1, "TOTAL_GOOD_LANDINGS": 1, "CHARGE_TARGET": 1, "CLEAN_START": 2, "AIR_TIME": 2,
          "FLICK_MAX_POWER": 2, "GOOD_LANDING_STREAK": 3, "CCW_TURNS": 3, "SPEED_TARGET": 3, "LONG_JUMP": 4,
          "CHARGED_LANDING": 5, "SURVIVAL_HP": 4, "BAD_LANDING_LIMIT": 3, "LIMB_LIMIT": 6, "CLEAN_SECTION": 8,
          "RECOVERY": 2, "CHARGED_LANDING_STREAK": 18, "WIN_MARGIN_OVER": 41, "NO_TOUCH_AND_WIN": 41,
          "FLICK_MIN_AND_WIN": 41, "ROCKET_HEAD_DISTANCE": 41, "HEAD_LANDINGS": 41, "MAX_HEIGHT_M": 41}
# behaviour families: what the player actually has to do
FAMILIES = {
    "distance": ["DISTANCE"], "survival": ["CLEAN_START", "SURVIVAL_HP", "LIMB_LIMIT"],
    "race": ["WIN_MARGIN_OVER", "NO_TOUCH_AND_WIN", "FLICK_MIN_AND_WIN"], "head": ["ROCKET_HEAD_DISTANCE", "HEAD_LANDINGS"],
    "feet": ["TOTAL_GOOD_LANDINGS", "GOOD_LANDING_STREAK"], "flick": ["FLICK_MAX_POWER", "FLICK_MIN_AND_WIN"],
    "rotation": ["CCW_TURNS"], "clean_landing": ["BAD_LANDING_LIMIT", "CLEAN_SECTION", "RECOVERY"],
    "charge": ["CHARGE_TARGET", "CHARGED_LANDING", "CHARGED_LANDING_STREAK"], "air": ["AIR_TIME", "LONG_JUMP", "MAX_HEIGHT_M"],
    "speed": ["SPEED_TARGET"],
}
FAMILY = {}
for fam, ts in FAMILIES.items():
    for t in ts:
        FAMILY.setdefault(t, fam)
FAMILY["FLICK_MIN_AND_WIN"] = "flick"
# families whose members ask for the SAME repeated action: also kept off the next round (numeric/type variants)
SPACED_FAMILIES = {"feet": 3, "charge": 2}
INCOMPATIBLE = [set(p) for p in [   # StarChallenges.INCOMPATIBLE (game) ...
    ["GOOD_LANDING_STREAK", "CHARGED_LANDING_STREAK"], ["CLEAN_START", "SURVIVAL_HP"],
    ["TOTAL_GOOD_LANDINGS", "CHARGED_LANDING_STREAK"], ["FLICK_MAX_POWER", "FLICK_MIN_AND_WIN"],
    ["CLEAN_START", "ROCKET_HEAD_DISTANCE"], ["SURVIVAL_HP", "ROCKET_HEAD_DISTANCE"], ["BAD_LANDING_LIMIT", "ROCKET_HEAD_DISTANCE"],
    ["CLEAN_START", "HEAD_LANDINGS"], ["BAD_LANDING_LIMIT", "HEAD_LANDINGS"],
    # ... plus v33 behaviour conflicts (no-touch cannot be combined with hold-to-steer / charge objectives)
    ["LIMB_LIMIT", "HEAD_LANDINGS"], ["SURVIVAL_HP", "HEAD_LANDINGS"], ["NO_TOUCH_AND_WIN", "CCW_TURNS"],
    ["NO_TOUCH_AND_WIN", "CHARGED_LANDING_STREAK"]]]


def stage(r):
    return 0 if r <= 33 else (1 if r <= 66 else 2)


def build_params(old):
    hist = collections.defaultdict(list)   # type -> [(round, params)]
    for i in range(1, 101):
        for c in old["r%d" % i]:
            hist[c["type"]].append((i, {k: v for k, v in c.items() if k not in ("type", "reward")}))

    def params(t, r):
        if t == "GOOD_LANDING_STREAK":
            return {"n": [3, 4, 5][stage(r)]}
        if t == "TOTAL_GOOD_LANDINGS":
            return {"n": [4, 5, 5][stage(r)]}
        if t == "SPEED_TARGET":
            return {"kmh": CAPS["speed_for_round"](r)}
        if t == "MAX_HEIGHT_M":
            return {"m": CAPS["height_for_round"](max(r, 41))}
        if t == "NO_TOUCH_AND_WIN":
            return {"s": 3.5}
        rows = hist[t]
        before = [p for (i, p) in rows if i <= r]
        return dict(before[-1] if before else rows[0][1])
    return params


def select(rounds=100):
    rng = random.Random(SEED)
    count = collections.Counter()
    last_seen = {}          # type -> round
    used_triplets = set()
    fam_last = {}           # family -> round
    plan = []
    for r in range(1, rounds + 1):
        noise = {t: rng.random() * 0.01 for t in UNLOCK}   # deterministic seeded tie-break

        def score(t, slot):
            unlocked = max(1, sum(1 for x in SLOTS[slot] if UNLOCK[x] <= r))
            return count[t] * len(SLOTS[slot]) / unlocked + 0.02 * max(0, 6 - (r - last_seen.get(t, -99))) + noise[t]

        def ok(t, gap):
            if UNLOCK[t] > r or r - last_seen.get(t, -99) < gap:
                return False
            fam = FAMILY[t]
            # repetitive-action families (feet, charge) also stay off the following round(s)
            return not (gap > 1 and fam in SPACED_FAMILIES and r - fam_last.get(fam, -99) < SPACED_FAMILIES[fam])

        chosen = None
        for gap in (3, 2, 1):        # preferred separation, relaxed only if no valid triplet exists
            best = None
            for a in [t for t in SLOTS["A"] if ok(t, gap)]:
                for b in [t for t in SLOTS["B"] if ok(t, gap)]:
                    for c in [t for t in SLOTS["C"] if ok(t, gap)]:
                        trip = [a, b, c]
                        if len({FAMILY[t] for t in trip}) < 3:
                            continue                     # three different behaviours per round
                        if any(p <= set(trip) for p in INCOMPATIBLE):
                            continue
                        if frozenset(trip) in used_triplets:
                            continue                     # unique triplets (campaign_data rejects repeats)
                        s = score(a, "A") + score(b, "B") + score(c, "C")
                        if best is None or s < best[0]:
                            best = (s, trip)
            if best:
                chosen = best[1]
                break
        assert chosen, r
        used_triplets.add(frozenset(chosen))
        for t in chosen:
            count[t] += 1
            last_seen[t] = r
            fam_last[FAMILY[t]] = r
        plan.append(chosen)
    return plan


def main():
    old = json.loads(SOURCE.read_text(encoding="utf-8"))
    params = build_params(old)
    plan = select()
    new = {}
    for r, types in enumerate(plan, 1):
        rewards = [c.get("reward", 0) for c in old["r%d" % r]]
        row = []
        for j, t in enumerate(types):
            c = CAPS["clamp"](dict(type=t, **params(t, r)))
            assert CAPS["within_caps"](c) and t not in REMOVED
            c["reward"] = rewards[j] if j < len(rewards) else rewards[-1]
            row.append(c)
        new["r%d" % r] = row
    if "--write" in sys.argv:
        PATH.write_text(json.dumps(new, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("written", PATH)
    else:
        for r in range(1, 11):
            print("r%d" % r, [(c["type"], {k: v for k, v in c.items() if k not in ("type", "reward")}) for c in new["r%d" % r]])


if __name__ == "__main__":
    main()
