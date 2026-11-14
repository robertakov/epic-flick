from pathlib import Path
import json
root=Path(__file__).resolve().parents[2]/'game/assets/enemies'
# Pivots/joins are tuned against actual extracted source geometry, separate from all physics anchors.
profiles={
'devil':{'torso':([128,108],.44),'head':([100,170],.48),'anchors':{'neck':[128,23],'shoulder_l':[26,65],'shoulder_r':[231,63],'hip_l':[92,185],'hip_r':[163,185]},'arms':[[180,44,70,185,76,160,.38],[28,43,134,186,76,160,.38]],'legs':[[158,14,152,248,24,116,[113,33,57,20],.38],[66,14,73,248,24,116,[58,33,57,20],.38]]},
'vampire':{'torso':([128,135],.43),'head':([128,174],.40),'anchors':{'neck':[128,65],'shoulder_l':[39,119],'shoulder_r':[218,117],'hip_l':[94,200],'hip_r':[161,200]},'arms':[[178,47,64,181,77,151,.36],[25,44,132,180,77,151,.36]],'legs':[[191,27,153,246,66,136,[119,83,54,20],.34],[37,28,71,246,66,136,[52,83,54,20],.34]]},
'cowboy':{'torso':([128,117],.43),'head':([127,189],.39),'anchors':{'neck':[129,23],'shoulder_l':[26,68],'shoulder_r':[231,64],'hip_l':[95,200],'hip_r':[166,200]},'arms':[[184,43,70,180,72,152,.37],[28,42,144,179,72,152,.37]],'legs':[[165,14,182,247,25,97,[129,43,52,20],.34],[80,14,63,247,25,97,[65,43,52,20],.34]]},
'tiger':{'torso':([128,108],.46),'head':([106,178],.45),'anchors':{'neck':[129,22],'shoulder_l':[25,63],'shoulder_r':[231,62],'hip_l':[88,189],'hip_r':[169,189]},'arms':[[182,47,70,181,75,150,.40],[27,48,140,184,75,150,.40]],'legs':[[159,13,169,247,25,107,[122,42,56,20],.37],[78,13,75,247,25,107,[66,42,56,20],.37]]},
'shark':{'torso':([128,110],.44),'head':([88,174],.44),'anchors':{'neck':[128,22],'shoulder_l':[25,65],'shoulder_r':[231,65],'hip_l':[94,188],'hip_r':[164,188]},'arms':[[195,44,105,122,77,119,.37],[32,44,120,122,77,119,.37]],'legs':[[206,13,190,230,24,104,[158,40,52,20],.35],[49,13,66,231,24,104,[40,40,52,20],.35]]}}
for id,data in profiles.items():
 parts={}
 for name in ['torso','head']:
  pivot,unit=data[name];parts[name]={'pivot':pivot,'unit_scale':unit,'z':2 if name=='head' else 0}
 for limb in ['arm','leg']:
  for i,side in enumerate(['l','r']):
   row=data[limb+'s'][i];parts[limb+'_'+side]={'pivot':row[:2],'end':row[2:4],'spring_rows':row[4:6],'unit_scale':row[-1],'z':1 if limb=='arm' else 0,'inertia_gain':.28}
   if limb=='leg':parts[limb+'_'+side].update({'ring_region':row[6],'ring_count':6,'coil_scale':1.15,'spring_centers':[[row[0],row[4]],[row[2],row[5]]]})
 profile={'id':id,'anchors':data['anchors'],'parts':parts,'source_only_static_body':True}
 (root/id/'rig.json').write_text(json.dumps(profile,indent=2),encoding='utf8')
print('five independent visual profiles written')
