"""Development-only conservative refinement of existing static stars from fresh telemetry.
Defaults to review-only; --apply is required to change stars.json.
"""
import argparse, glob, json, runpy
from pathlib import Path
_library=runpy.run_path(str(Path(__file__).with_name('gen_stars.py')))
ROBOTS, candidates, rate=(_library[k] for k in ['ROBOTS','candidates','rate'])

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--logs',nargs='+',required=True)
    ap.add_argument('--types',nargs='+',required=True)
    ap.add_argument('--apply',action='store_true')
    ap.add_argument('--report',default='reports/stars_refinements.md')
    ap.add_argument('--each-cohort',action='store_true')
    args=ap.parse_args()
    root=Path(__file__).resolve().parent.parent
    rows=[]
    for pattern in args.logs:
        for p in glob.glob(pattern):
            for line in Path(p).read_text(encoding='utf-8-sig').splitlines():
                if line.startswith('AT|simrun '):
                    row=json.loads(line.split('AT|simrun ',1)[1]);row['_cohort']=Path(p).stem.split('_')[0];rows.append(row)
    assert len(rows)>=160
    stars_path=root/'game/config/campaign/stars.json'
    stars=json.loads(stars_path.read_text(encoding='utf-8'))
    top_skill=max(r['skill'] for r in rows)
    caps={}
    for t in args.types:
        pool,key=candidates(t,rows)
        acceptable=[]
        for c in pool:
            groups=[[r for r in rows if r['_cohort']==cohort] for cohort in sorted({r['_cohort'] for r in rows})] if args.each_cohort else [rows]
            top=[rate(c,[r for r in group if r['robot']==rid and r['skill']==top_skill]) for group in groups for rid in ROBOTS]
            pooled=[rate(c,[r for r in group if r['robot']==rid]) for group in groups for rid in ROBOTS]
            if min(top)>=.25 and min(pooled)>=.12:
                acceptable.append(c)
        assert acceptable, ('No measured multi-robot cap',t)
        caps[t]=(max(acceptable,key=lambda c:c[key]),key)
    changes=[]
    for rid,cs in stars.items():
        for i,c in enumerate(cs):
            if c['type'] not in caps:continue
            cap,key=caps[c['type']]
            if c[key]>cap[key]:
                old=c[key];c[key]=cap[key]
                changes.append(f'{rid} #{i+1} {c["type"]}: {key} {old:g} -> {c[key]:g}')
    report=['# Conservative fresh-seed balance refinements','',f'{len(rows)} runs, all five archetypes, four skill levels.',
      'Caps are the highest empirical candidate meeting >=25% top-skill completion and >=12% pooled completion for every archetype in this fresh cohort.',
      'This refinement only lowers existing thresholds; triplets, rewards, and other parameters remain fixed.','',*changes]
    if args.each_cohort:report.insert(4,'The acceptance criteria must hold separately in every input cohort, rather than only in the pooled sample.')
    print('\n'.join(report))
    if args.apply:
        assert all(_library['CAPS']['within_caps'](c) for cs in stars.values() for c in cs),'hard cap violated (star_caps.py)'
        stars_path.write_text(json.dumps(stars,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        (root/args.report).write_text('\n'.join(report)+'\n',encoding='utf-8')

if __name__=='__main__':main()
