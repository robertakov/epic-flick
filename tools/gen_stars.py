"""Development-only star generation and audit. Never invoked by the game.
python -I tools/gen_stars.py --logs reports/calibration/*.log --generate [--overwrite]
python -I tools/gen_stars.py --logs reports/validation/*.log --report reports/stars_balance.md
"""
import argparse, collections, itertools, json, math, random, runpy
from pathlib import Path
CAPS=runpy.run_path(str(Path(__file__).with_name('star_caps.py')))

CATS = {'A': ['DISTANCE','CLEAN_START','LIMB_LIMIT','SURVIVAL_HP'],
        'B': ['BAD_LANDING_LIMIT','GOOD_LANDING_STREAK','TOTAL_GOOD_LANDINGS','RECOVERY','CLEAN_SECTION'],
        'C': ['CHARGE_TARGET','CHARGED_LANDING','CHARGED_LANDING_STREAK','AIR_TIME','LONG_JUMP','SPEED_TARGET']}
MIN = dict(zip(['DISTANCE','TOTAL_GOOD_LANDINGS','CHARGE_TARGET','CLEAN_START','AIR_TIME','GOOD_LANDING_STREAK','SPEED_TARGET','LONG_JUMP','CHARGED_LANDING','SURVIVAL_HP','BAD_LANDING_LIMIT','LIMB_LIMIT','CLEAN_SECTION','RECOVERY','CHARGED_LANDING_STREAK'],[1,1,1,2,2,3,4,4,5,6,6,8,8,10,12]))
MIN['CHARGED_LANDING_STREAK'] = 18  # Fresh-seed low-skill completion was only 8%; introduce later.
BAD = [{'GOOD_LANDING_STREAK','CHARGED_LANDING_STREAK'}, {'TOTAL_GOOD_LANDINGS','CHARGED_LANDING_STREAK'}, {'CLEAN_START','SURVIVAL_HP'}]
ROBOTS = ['tin','hopper','heavy','rocket','samurai']

def evaluate(c,m):
    t=c['type']; x=c.get('m',0); n=c.get('n',0)
    if t=='DISTANCE': return m['distance']>=x
    if t in ['CLEAN_START','LIMB_LIMIT','BAD_LANDING_LIMIT']:
        ev=m['bad_m' if t=='BAD_LANDING_LIMIT' else 'limb_loss_m']
        return m['distance']>=x and sum(d<=x for d in ev)<=n
    if t=='SURVIVAL_HP':
        hp=100
        for d,h in m['hp_changes']:
            if d<=x: hp=h
        return m['distance']>=x and hp>=c['hp']
    fields={'GOOD_LANDING_STREAK':('max_good_streak','n'),'TOTAL_GOOD_LANDINGS':('total_good','n'),'RECOVERY':('recoveries','n'),
            'AIR_TIME':('max_air','s'),'LONG_JUMP':('max_jump','m'),'SPEED_TARGET':('max_speed','kmh'),'CLEAN_SECTION':('max_clean','m')}
    if t in fields:
        f,p=fields[t];return m[f]+(0.000001 if t=='AIR_TIME' else 0)>=c[p]
    if t=='CHARGE_TARGET': return m['peak_charge']*100+0.00001>=c['pct']
    best=streak=0
    for good,charge,d in m['landings']:
        streak=streak+1 if good and charge*100+0.00001>=c['pct'] else 0
        best=max(best,streak)
    return best>=c.get('n',1)

def quantile(v,q):
    v=sorted(v); return v[round((len(v)-1)*q)]

def assignments():
    rng=random.Random(110120)
    counts=collections.Counter(); used=set(); prev=set(); out=[]
    for r in range(1,41):
        choices=[]
        for trip in itertools.product(*CATS.values()):
            types=set(trip)
            if any(MIN[t]>r for t in trip) or any(p<=types for p in BAD): continue
            if len(types&prev)>1 or frozenset(types) in used: continue
            score=sum(counts[t]*len(CATS[cat]) for cat,t in zip(CATS,trip)) + rng.random()*.1
            choices.append((score,trip))
        assert choices, r
        trip=min(choices)[1];out.append(trip);counts.update(trip);prev=set(trip);used.add(frozenset(trip))
    return out

def candidates(t,rows):
    ms=[r['metrics'] for r in rows]
    extra={}
    if t=='CLEAN_START': values=[m['first_limb_m'] for m in ms];key='m';step=5
    elif t=='LIMB_LIMIT':
        extra={'n':1};values=[m['limb_loss_m'][1] if len(m['limb_loss_m'])>1 else m['distance'] for m in ms];key='m';step=5
    elif t=='BAD_LANDING_LIMIT':
        extra={'n':1};values=[m['bad_m'][1] if len(m['bad_m'])>1 else m['distance'] for m in ms];key='m';step=5
    elif t=='SURVIVAL_HP':
        extra={'hp':60};values=[next((d for d,h in m['hp_changes'] if h<60),m['distance']) for m in ms];key='m';step=5
    elif t in ['CHARGED_LANDING','CHARGED_LANDING_STREAK']:
        values=[c*100 for m in ms for good,c,d in m['landings'] if good];key='pct';step=5
        if t.endswith('STREAK'):extra={'n':2}
    else:
        f,key,step={'DISTANCE':('distance','m',5),'CLEAN_SECTION':('max_clean','m',5),'GOOD_LANDING_STREAK':('max_good_streak','n',1),
           'TOTAL_GOOD_LANDINGS':('total_good','n',1),'RECOVERY':('recoveries','n',1),'AIR_TIME':('max_air','s',.1),
           'LONG_JUMP':('max_jump','m',5),'SPEED_TARGET':('max_speed','kmh',5),'CHARGE_TARGET':('peak_charge','pct',5)}[t]
        values=[m[f]*(100 if key=='pct' else 1) for m in ms]
    # Candidate grid derives from measured quantiles, rather than invented goal distances.
    vals=sorted({round(max(step,round(quantile(values,q/100)/step)*step),2) for q in range(5,96)})
    contact_floor=math.ceil(quantile([m['first_touch_m'] for m in ms],.95)/5)*5
    if t in ['CLEAN_START','LIMB_LIMIT','SURVIVAL_HP','BAD_LANDING_LIMIT','CLEAN_SECTION']:
        vals=[v for v in vals if v>=contact_floor]
    if t in CAPS['HARD_CAPS']:
        # hard design caps (star_caps.py): never offer a threshold above the cap; the cap itself stays a candidate
        cap=CAPS['HARD_CAPS'][t][1];vals=sorted({v for v in vals if v<=cap}|{cap})
    return [dict(type=t,**extra,**{key:v}) for v in vals],key

def rate(c,rows):return sum(evaluate(c,r['metrics']) for r in rows)/len(rows) if rows else 0

def generate(rows,main):
    pools={t:candidates(t,rows) for t in MIN};last={};stars={};decisions=[]
    skills=sorted({r['skill'] for r in rows})
    for i,trip in enumerate(assignments(),1):
        node=main['nodes'][i-1];skill=sum(e['skill'] for e in node['enemies'])/len(node['enemies'])
        nearest=min(skills,key=lambda s:abs(s-skill));ref=[r for r in rows if r['skill']==nearest]
        challenges=[]
        for j,t in enumerate(trip):
            target=(.55-.15*((i-1)/39)**.7)-j*.035-(.03 if i%10==0 else 0)
            pool,key=pools[t];eligible=[]
            for c in pool:
                overall=rate(c,rows)
                top=[rate(c,[r for r in rows if r['robot']==rid and r['skill']==max(skills)]) for rid in ROBOTS]
                by_robot=[rate(c,[r for r in rows if r['robot']==rid]) for rid in ROBOTS]
                if overall>.85 or min(top)<.2 or min(by_robot)<.12 or overall<.18 or rate(c,ref)<.15:continue
                score=abs(rate(c,ref)-target)+max(0,.2-min(top))*.4
                eligible.append((score,c))
            if not eligible and t in CAPS['HARD_CAPS']:
                # e.g. every capped speed is "too easy" by the AI filter: the cap is the hardest allowed value
                eligible=[(0.0,dict(type=t,**{key:CAPS['HARD_CAPS'][t][1]}))]
                decisions.append(f'r{i} {t}: hard cap used ({key}={CAPS["HARD_CAPS"][t][1]})')
            assert eligible,('No achievable measured candidate',t)
            monotonic=[pair for pair in eligible if pair[1][key]>=last.get(t,0)]
            if monotonic:eligible=monotonic
            else:decisions.append(f'r{i} {t}: lower threshold allowed to preserve multi-robot attainability')
            c=min(eligible,key=lambda pair:pair[0])[1].copy();last[t]=c[key]
            c['reward']=int(5*round((15+1.25*i)*(1.5 if i%10==0 else 1)/5));challenges.append(c)
        stars[f'r{i}']=challenges
    return stars,decisions

def report(stars,rows,main,out,decisions):
    counts=collections.Counter(c['type'] for cs in stars.values() for c in cs);cats=collections.Counter()
    lines=['# Star Challenge balance report','',f'{len(rows)} measured runs; 5 robot archetypes. AI is a rejection filter, not a human difficulty rating.',
      'Fixed objectives, one A/B/C per round. Thresholds are generated once from measured quantile candidates. No runtime generation or adaptive scaling.',
      'Targets: about 55% early to 40% late at the nearest sampled enemy skill, slightly lower for mastery/bosses. Counts are discrete; actual rates can differ.',
      'AIR_TIME/LONG_JUMP/SPEED_TARGET exclude the flick and jet-head. CLEAN_SECTION excludes the jet-head.',
      'Calibration and validation use separate terrain seed ranges. AI form is deliberately stochastic, so archived raw logs are the reproducibility record.','',
      '| Round | # | Type | Category | Parameters | Coins | All | Reference skill / rate | Per robot tin/hopper/heavy/rocket/samurai | Flags |',
      '|---|---|---|---|---|---:|---:|---|---|---|']
    warnings=[];prev=set();seen={};disagree=0
    for i in range(1,41):
        rid=f'r{i}'; cs=stars[rid]; types={c['type'] for c in cs}
        assert len(cs)==3 and sorted(next(cat for cat,ts in CATS.items() if c['type'] in ts) for c in cs)==['A','B','C']
        assert not any(p<=types for p in BAD) and len(types&prev)<=1 and frozenset(types) not in seen
        seen[frozenset(types)]=rid;prev=types
        skill=sum(e['skill'] for e in main['nodes'][i-1]['enemies'])/len(main['nodes'][i-1]['enemies'])
        nearest=min({r['skill'] for r in rows},key=lambda s:abs(s-skill));ref=[r for r in rows if r['skill']==nearest]
        for j,c in enumerate(cs):
            cat=next(cat for cat,ts in CATS.items() if c['type'] in ts);cats[cat]+=1
            allrate=rate(c,rows);by=[rate(c,[r for r in rows if r['robot']==robot]) for robot in ROBOTS];rr=rate(c,ref)
            flags=[]
            if allrate>.85: flags.append('EASY >85%')
            if allrate<.15 or rr<.15:flags.append('HARD <15%')
            if allrate<.05:flags.append('RARE <5%')
            if min(by)<.1:flags.append('robot disparity')
            if max(by)-min(by)>.35:flags.append('robot spread >35pp')
            if c['type'] in ['CLEAN_START','LONG_JUMP','AIR_TIME','SPEED_TARGET','CLEAN_SECTION','CHARGED_LANDING','CHARGED_LANDING_STREAK']:
                flags.append('phone: intentional control')
            if flags:warnings.append(f'{rid} #{j+1}: '+', '.join(flags))
            params=', '.join(f'{k}={v:g}' for k,v in c.items() if k not in ['type','reward'])
            lines.append(f'| {rid} | {j+1} | {c["type"]} | {cat} | {params} | {c["reward"]} | {allrate:.0%} | {nearest:.2f} / {rr:.0%} | '+ '/'.join(f'{v:.0%}' for v in by)+' | '+', '.join(flags)+' |')
            for r in rows:
                actual=r.get('achieved',{}).get(rid,[])
                if len(actual)==3 and bool(actual[j])!=evaluate(c,r['metrics']):disagree+=1
                live=r.get('live_status',[])
                if len(live)==120 and (live[(i-1)*3+j]==1)!=evaluate(c,r['metrics']):disagree+=1
    lines+=['','## Distribution','',*['- '+t+': '+str(n) for t,n in sorted(counts.items())],f'- Categories: {dict(cats)}',
            f'- Total stars: {sum(counts.values())}; all 15 types used: {len(counts)==15}',
            '- Identical triplets: 0. Neighbor overlap >1: 0. Incompatible pairs: 0.',
            f'- Runtime/offline evaluator disagreements: {disagree}',
            '', '## Interpretation and phone follow-up','',
            'Use feet alignment to retain limbs/HP, recover after a bad contact, and build landing streaks. Release to charge, then steer before touchdown for charged objectives. Use spring rebounds for flights/jumps/speed. No objective requires a named terrain template.',
            'Speed frequently reaches the normal cap: high speed thresholds can have similar success rates; inspect intentional controllability on phone. Recovery requires a bad landing first; an entirely clean run intentionally cannot earn it.',
            '12 calibration seeds per skill/archetype and separate validation seeds still leave sampling uncertainty, especially per robot. Reference-skill rates are pooled across robots. Human play must assess terrain luck, readable instructions and deliberate pursuit.',
            '', '## Flags', '',*['- '+w for w in warnings], '', '## Generation exceptions','',*(decisions or ['None.'])]
    assert disagree==0,('Runtime mismatch',disagree)
    out.parent.mkdir(parents=True,exist_ok=True);out.write_text('\n'.join(lines)+'\n',encoding='utf-8')

def main():
    import glob
    ap=argparse.ArgumentParser();ap.add_argument('--logs',nargs='+',required=True);ap.add_argument('--generate',action='store_true');ap.add_argument('--overwrite',action='store_true');ap.add_argument('--report',default='reports/stars_balance.md');args=ap.parse_args()
    root=Path(__file__).resolve().parent.parent
    rows=[json.loads(l.split('AT|simrun ',1)[1]) for pattern in args.logs for p in glob.glob(pattern) for l in Path(p).read_text(encoding='utf-8-sig').splitlines() if l.startswith('AT|simrun ')]
    assert len(rows)>=160,'Collect multiple seeds across all five archetypes and four skills first'
    campaign=json.loads((root/'game/config/campaign/main.json').read_text(encoding='utf-8'))
    path=root/'game/config/campaign/stars.json';decisions=[]
    if args.generate:
        if path.exists() and not args.overwrite:raise SystemExit('Refusing to overwrite stars.json without --overwrite')
        stars,decisions=generate(rows,campaign)
        for row in rows: row.pop('live_status',None); row.pop('achieved',None)  # Old outcomes refer to the previous objective revision.
        assert all(CAPS['within_caps'](c) for cs in stars.values() for c in cs),'hard cap violated'
        path.write_text(json.dumps(stars,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    else:
        stars=json.loads(path.read_text(encoding='utf-8'))
        calibration=root/'reports/stars_calibration.md'
        if calibration.exists():
            section=calibration.read_text(encoding='utf-8').split('## Generation exceptions',1)
            if len(section)==2:decisions=[line for line in section[1].strip().splitlines() if line.strip()]
    report(stars,rows,campaign,root/args.report,decisions)
    print(f'{len(rows)} runs, 120 stars, report: {root/args.report}')

if __name__=='__main__':main()
