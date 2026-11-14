from pathlib import Path
import json, statistics
p=Path(__file__).resolve().parents[1]/'reports'
lines=['# Desktop AI performance evidence','','Same planner algorithm, same seeds 94000/94017, all 48 opponents, 96 physical runs per variant. Legacy disables the new bands in the debug harness; production never runs these simulations. Profiling clocks are disabled in normal gameplay. The final comparison runs sequentially without concurrent distribution/regression processes. Longer/shorter physical runs affect totals; use per-plan and per-simulated-second costs rather than wall-clock duration. This is not a phone benchmark.','','|Variant|n|Planner calls|Total CPU ms|Mean µs / plan|CPU ms / simulated opponent second|','|---|---:|---:|---:|---:|---:|']
data={}
for variant in ['legacy','bands']:
 f=p/'ai_perf_isolated'/f'{variant}.log';a=[json.loads(l.split(' ',1)[1]) for l in f.read_text(encoding='utf-8-sig').splitlines() if l.startswith('AT|distribution ')]
 if len(a)!=96: print(variant,'NOT DONE',len(a));raise SystemExit(1)
 calls=sum(r['plan_calls'] for r in a);micros=sum(r['plan_usec'] for r in a);secs=sum(r['elapsed'] for r in a)
 assert calls>0
 data[variant]=(micros/calls,micros/1000/secs)
 lines.append('|%s|%d|%d|%.1f|%.1f|%.3f|'%(variant,len(a),calls,micros/1000,micros/calls,micros/1000/secs))
lines+=['','Per-plan ratio %.3f; per simulated second ratio %.3f.'%(data['bands'][0]/data['legacy'][0],data['bands'][1]/data['legacy'][1]),'', 'New band weights perform two smoothstep scalar evaluations once per physics tick. No additional trajectory search, candidate runs, robot instances or planner resolution were added. The release regression measures 100,000 scalar queries in <500ms (actual value in ai_bands_shipped.log). Existing coarse/fine hold planner, ballistic lookahead and cadence resolution are retained.','', 'Stress: 20 complete Free Run attempts and 20 rapid retries pass. Memory #5→#20 and orphan/body/chunk bounds are in reports/v12_tests/stress_final.log; no growth/leak assertions were weakened. Existing engine self_list shutdown diagnostic remains separately documented.']
(p/'ai_performance.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines[4:10]).encode('ascii','replace').decode())
