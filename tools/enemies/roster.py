from pathlib import Path
import json,random
r=Path(__file__).resolve().parents[2]/'game';campaign=json.loads((r/'config/campaign/main.json').read_text(encoding='utf8'))
identities={'devil':{'name':'Чёрт','archetypes':['tin','heavy']},'vampire':{'name':'Вампир','archetypes':['tin','hopper']},'cowboy':{'name':'Ковбой','archetypes':['tin','heavy','samurai']},'tiger':{'name':'Тигр','archetypes':['tin','hopper','heavy']},'shark':{'name':'Акула','archetypes':['hopper','rocket']}}
rng=random.Random(190019);counts={k:0 for k in identities};history=[];rounds={};normal_index=0
pressure_ordinals=[5,11,16,22,27,33]
for node in campaign['nodes']:
 if node['difficulty']=='boss' or 'boss' in node['type']:continue
 normal_index+=1;slots=[];used=set()
 pressure_slot=max(range(len(node['enemies'])),key=lambda i:node['enemies'][i]['skill']) if normal_index in pressure_ordinals else -1
 for i,enemy in enumerate(node['enemies']):
  choices=[id for id,value in identities.items() if enemy['robot'] in value['archetypes'] and id not in used]
  if not choices:choices=[id for id,value in identities.items() if enemy['robot'] in value['archetypes']]
  rng.shuffle(choices)
  chosen=min(choices,key=lambda id:counts[id]+(5 if history and history[-1]==id else 0)+(2 if id in history[-3:] else 0))
  slots.append({'id':chosen,'archetype':enemy['robot'],'pressure':i==pressure_slot});used.add(chosen);counts[chosen]+=1;history.append(chosen)
 rounds[node['id']]=slots
data={'version':1,'identities':identities,'rounds':rounds,'pressure_normal_ordinals':pressure_ordinals,'pressure_decisions':{'angle_error_deg':.5,'timing_error':.5,'blunder_chance':.25,'naive_slope_mix':.5,'reaction_delay':.65,'replan_interval':.8,'plan_tolerance':.8,'form_spread':.5,'long_run_skill_drop':.65}}
(r/'config/enemy_roster.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'counts':counts,'rounds':rounds},ensure_ascii=False,indent=2))
