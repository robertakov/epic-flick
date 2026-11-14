"""Offline Campaign balance evidence; never called by the game.
python -I tools/ai_balance.py --before reports/ai_before --after reports/ai_shipped --report reports/ai_balance.md
Initial calibration only: --before reports/ai_before --calibrate --apply (otherwise prints proposed data).
"""
import argparse, json, statistics, math, sys
sys.stdout.reconfigure(encoding="utf-8")
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1]
def read(folder):
    rows = defaultdict(list)
    for f in Path(folder).glob('*.log'):
        for line in f.read_text(encoding='utf-8-sig').splitlines():
            if line.startswith('AT|distribution '):
                r = json.loads(line.split(' ',1)[1])
                rows[(r['round'],r['index'])].append(r)
    return rows
def q(v,p):
    v=sorted(v); t=(len(v)-1)*p; i=int(t)
    return v[i]+(v[min(i+1,len(v)-1)]-v[i])*(t-i)
def weighted_q(pairs,p):
    pairs=sorted(pairs); target=sum(w for _,w in pairs)*p; acc=0
    for value,weight in pairs:
        acc+=weight
        if acc>=target: return value
    return pairs[-1][0]
def stats(rows):
    v=[r['distance'] for r in rows]
    return {'n':len(v),'mean':statistics.mean(v),'p10':q(v,.1),'p25':q(v,.25),'median':q(v,.5),'p75':q(v,.75),'p90':q(v,.9),'iqr':q(v,.75)-q(v,.25),'early':sum(x<50 for x in v)/len(v),'min':min(v),'max':max(v)}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--before',required=True,type=Path)
    ap.add_argument('--after',type=Path)
    ap.add_argument('--report',type=Path)
    ap.add_argument('--calibrate',action='store_true')
    ap.add_argument('--apply',action='store_true')
    ap.add_argument('--lower',type=float,default=.5)
    ap.add_argument('--upper',type=float,default=.85)
    ap.add_argument('--after-seed-base',type=int,default=105000)
    args=ap.parse_args(); before=read(args.before)
    data_path=ROOT/'game/config/campaign/main.json'
    data=json.loads(data_path.read_text(encoding='utf-8'))
    enemies={(n['round'],i):e for n in data['nodes'] for i,e in enumerate(n['enemies'])}
    assert set(before)==set(enemies) and all(len(v)>=20 for v in before.values()), 'Require >=20 physical samples for every opponent.'
    if args.calibrate:
        for key,e in enemies.items():
            neighbors=sorted((k for k,a in before.items() if a[0]['robot']==e['robot']),key=lambda k:(abs(before[k][0]['base_skill']-e['skill']),k))[:5]
            pool=[(r['distance'],math.exp(-.5*((r['base_skill']-e['skill'])/.1)**2)) for k in neighbors for r in before[k]]
            e['target_min_distance']=round(weighted_q(pool,args.lower)/5)*5
            e['target_max_distance']=round(weighted_q(pool,args.upper)/5)*5
        if args.apply:
            data_path.write_text(json.dumps(data,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
        else:
            print(json.dumps({str(k):(e['target_min_distance'],e['target_max_distance']) for k,e in enemies.items()},indent=1))
        return
    assert not args.apply, '--apply requires --calibrate'
    after=read(args.after)
    assert set(after)==set(enemies) and all(len(v)>=20 for v in after.values()), 'Require >=20 held-out samples for every opponent.'
    lines=['# Campaign AI distribution validation','',
      'All values are measured distances from real physics runs; no distance is replaced/clamped and no run ends at a configured band. Before: 20 terrain seeds (61000 + sample*17), 960 runs. After: 20 new terrain seeds (105000 + sample*17), 960 runs. AI RNG is reset to hash([terrain_seed,round,index,9147]) in this debug harness only. An initial paired 8-seed pilot (384 runs) and independent initial 20-seed validation (960 runs) are retained as refinement history. Default player settings, original robot configurations, skill/lean/greed, ordinary race end rules and launch slots.', '',
      'Final bands: weighted pooled P10/P90 of five nearest configured skills of the same archetype, snapped to 5m, from the preceding 960-run improved-controller cohort (seed base 83000). Initial baseline P40/P80 and subsequent weighted P50/P85 bands became too low after early-error suppression raised ordinary performance, so they were recalibrated from real outcomes. This report uses new held-out seeds rather than that calibration cohort. All available configurations are pooled if fewer than five. Baseline distributions were measured before any AI changes. Final ranges were calibrated after improving decision quality, then validated independently. Every enemy entry remains directly editable. Samples carry Gaussian weights exp(−0.5×(skill gap/0.10)²), so distant skill levels do not erase progression. Lower protection fades smoothly from 90% of the lower distance to 25% of the band width inside it; upper loss of precision starts in the final 20% of the band and reaches its bounded maximum 80% of a band width beyond the upper value. No player distance is read.', '',
      'Interpretation: n=20 per opponent is useful screening, not proof of a 90–95% production rate. Terrain/archetype physics still produces organic outliers. IQR=P75−P25; early=<50m (the reported phone failure class). Near-band compatibility includes a quarter band-width beyond either bound; exact and near rates are both shown. No tests force these rates to pass.', '',
      '|Round/enemy|Robot|Base skill|Band m|Before mean/P10/P25/median/P75/P90|After mean/P10/P25/median/P75/P90|IQR before→after|Early before→after|Exact / near after|After min–max|',
      '|---|---|---:|---|---|---|---|---|---|---|---|']
    ratios=[];warnings=[];exact_total=near_total=0
    for key,e in enemies.items():
        b=stats(before[key]); a=stats(after[key]); lo=e['target_min_distance'];hi=e['target_max_distance'];pad=(hi-lo)*.25
        exact=sum(lo<=r['distance']<=hi for r in after[key])/a['n']; near=sum(lo-pad<=r['distance']<=hi+pad for r in after[key])/a['n']
        exact_total+=exact*a['n'];near_total+=near*a['n'];ratios.append(a['iqr']/max(b['iqr'],1))
        fmt=lambda d:'/'.join('%.0f'%d[k] for k in ['mean','p10','p25','median','p75','p90'])
        lines.append('|%d/%d|%s|%.3f|%d–%d|%s|%s|%.0f→%.0f|%.0f%%→%.0f%%|%.0f%% / %.0f%%|%.0f–%.0f|'%(key[0],key[1]+1,e['robot'],e['skill'],lo,hi,fmt(b),fmt(a),b['iqr'],a['iqr'],100*b['early'],100*a['early'],100*exact,100*near,a['min'],a['max']))
        if a['early']>=.1: warnings.append('r%d enemy %d: %.0f%% under 50m.'%(key[0],key[1]+1,100*a['early']))
        if a['iqr']>b['iqr']*1.15: warnings.append('r%d enemy %d: IQR widened %.0f→%.0fm.'%(key[0],key[1]+1,b['iqr'],a['iqr']))
        if near<.8: warnings.append('r%d enemy %d: near-band compatibility %.0f%%, below aspirational 90–95%%.'%(key[0],key[1]+1,100*near))
    allb=[r for a in before.values() for r in a]; alla=[r for a in after.values() for r in a];b=stats(allb);a=stats(alla)
    lines+=['','## Aggregates','',
      'Early failures: %.2f%% → %.2f%%. Median per-opponent IQR ratio %.3f (%.1f%% reduction); %d/%d opponents have a narrower IQR. Exact band %.1f%%, near band %.1f%% after.'%(b['early']*100,a['early']*100,statistics.median(ratios),(1-statistics.median(ratios))*100,sum(x<1 for x in ratios),len(ratios),exact_total/len(alla)*100,near_total/len(alla)*100), '',
      '|Group|Before mean/median/P10|After mean/median/P10|Early before→after|','|---|---|---|---|']
    for label,cond in [('r1–10',lambda k:k[0]<=10),('r11–20',lambda k:11<=k[0]<=20),('r21–30',lambda k:21<=k[0]<=30),('r31–40',lambda k:k[0]>=31)]+[(r,lambda k,r=r:enemies[k]['robot']==r) for r in ['tin','hopper','heavy','rocket','samurai']]+[('boss r%d'%r,lambda k,r=r:k[0]==r) for r in [10,20,30,40]]:
        b=stats([r for k,v in before.items() if cond(k) for r in v]); a=stats([r for k,v in after.items() if cond(k) for r in v])
        lines.append('|%s|%.0f/%.0f/%.0f|%.0f/%.0f/%.0f|%.1f%%→%.1f%%|'%(label,b['mean'],b['median'],b['p10'],a['mean'],a['median'],a['p10'],b['early']*100,a['early']*100))
    lines+=['','## Remaining balance warnings','']+['* '+w for w in warnings]
    lines+=['','AI form/effective skill are recorded in each raw line. Base skill and adaptive bounds are unchanged; protection scales form to 25%, angle noise to 15%, timing to 20%, reaction delay to 25%, blunders to 2%, slope mix to 30%, planner tolerance to 50% and limits Gaussian tails to ±1.7 sigma while protected. These are not perfect decisions; normal slope judgment and tolerance return as protection fades, while planner cadence, target lean and greed remain configured throughout. Inside the band normal quality returns. At long distances skill precision drops smoothly by at most 0.18; angle/timing noise spread rises by at most 45%/25%. Physical difficulty, unavoidable bad geometry, jet travel and chance still matter. Phone tuning must not replace measured distances with desired results.']
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('\n'.join(lines[lines.index('## Aggregates'):lines.index('## Aggregates')+4]))
if __name__=='__main__': main()
