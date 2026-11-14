from pathlib import Path
import json
from PIL import Image
import numpy as np
r=Path(__file__).resolve().parents[2]/'game/assets/enemies'
for d in r.iterdir():
 p=d/'rig.json';data=json.loads(p.read_text())
 for side in ['l','r']:
  part=data['parts']['leg_'+side];a=np.array(Image.open(d/('leg_'+side+'.png')))[:,:,3]
  y0=86 if d.name=='vampire' else 55;y1=y0+16
  ys,xs=np.where(a[y0:y1]>80)
  part['ring_region']=[int(xs.min())-2,y0,int(xs.max()-xs.min())+5,y1-y0]
  y=18;xs=np.where(a[y]>80)[0]
  part['pivot']=[float((xs.min()+xs.max())/2),y]
  for j,y in enumerate(part['spring_rows']):
   xs=np.where(a[y]>80)[0]
   part['spring_centers'][j]=[float((xs.min()+xs.max())/2),y]
  part['ring_count']=8;part['coil_scale']=1.0
 p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
print('source ring bounds and actual upper sockets tuned individually')
