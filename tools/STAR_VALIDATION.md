# Star validation workflow

Run the documented suites in README. Debug scripts are excluded from Android export.

For calibration, run ai_sim separately for tin/hopper/heavy/rocket/samurai with
`--sim_seeds=12 --sim_skills=0.2,0.45,0.7,0.95 --max_time=10000`.
Each process must have distinct `--profile_path`, `--settings_path`, and `--stats_path` under user://test.
Capture complete AT|simrun logs. AI decision form remains stochastic by design.

`python -I tools/gen_stars.py --logs reports/calibration/*.log --generate` refuses to overwrite existing stars.json.
An intentional regeneration requires `--overwrite`. Main Campaign generation never writes star data.
No generator is invoked at runtime.

Candidate thresholds come from empirical quantiles, snapped to readable units. The final rejection filter
requires >=20% top-skill success for each archetype, >=12% pooled success for each archetype, >=18% overall,
and >=15% at the nearest sampled round skill. Reference targets are 55% early to 40% late, with small mastery/boss
adjustments. Count discreteness and caps limit the achievable rates. Monotonic thresholds are preferred, but
relaxed when those filters would otherwise fail. HP 60% avoids the existing 75/50/25 limb thresholds.
Charged streaks start no earlier than round 18 because the initially proposed round-12 introduction had only
8% fresh-seed completion at skill 0.2. Rewards follow the handoff proposal, rounded to five; bosses x1.5.

Validate on a distinct seed base (e.g. --sim_seed_base=23000). Each AI robot now runs the actual tracker over all
120 objectives and emits live_status plus metrics and final evaluator outcomes. The Python report asserts
agreement between live completion, the runtime evaluator, and its offline implementation.

`python -I tools/gen_stars.py --logs reports/validation/*.log --report reports/stars_balance.md`

Never silently retune from a validation run. Edit data intentionally, rerun validation, and preserve raw logs.
Phone testing is still required for intentional mastery versus terrain luck, fonts, touch, and performance.

Final shipped evidence: reports/validation/shipped_*.log contains the 160 physical runs.
The last r39 checkpoint adjustment is replayed from their contact sequences by:
`--autotest --scenario=star_report --audit_dir=G:/Godot/EpicShalban/reports/validation`.
The resulting final_audit.log holds current-data runtime outcomes and original live flags,
with r39#2 explicitly annotated as a deterministic tracker replay.
Reproduce the final table with:
`python -I tools/gen_stars.py --logs reports/final_audit.log --report reports/stars_balance.md`.

Refine existing values conservatively without changing triplets/rewards:
`python -I tools/refine_stars.py --logs <patterns> --types <types>` prints review output.
`--apply` writes data; `--each-cohort` requires acceptance in every separately named input cohort.
The source report records exactly which values changed; a final report/audit must follow.
