from pathlib import Path
import json,hashlib
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage as nd
import av
ROOT=Path(__file__).resolve().parents[2];SRC=ROOT/'Characters/Enamies';OUT=ROOT/'game/assets/enemies'
work=ROOT/'reports/v19_processing';work.mkdir(parents=True,exist_ok=True)
files={'vampire':'file_0000000018b8820db5ffad5f50225d73.png','tiger':'file_0000000044b081f493dcf9d368333a75.png','devil':'file_00000000d40c81f7a83a0687f2642729.png','shark':'file_00000000e21c81f5b21d0e70f490f94d.png','cowboy':'file_00000000f4cc81f6aea0bf78ee4e8442.png'}
def key(a):
 rgb=a.astype(np.float32);r,g,b=rgb.transpose(2,0,1)
 candidate=(g>r+25)&(g>b+25)&(g>70)
 seeds=np.zeros(candidate.shape,bool);seeds[:4]=candidate[:4];seeds[-4:]=candidate[-4:];seeds[:,:4]|=candidate[:,:4];seeds[:,-4:]|=candidate[:,-4:]
 exterior=nd.binary_propagation(seeds,mask=candidate)
 sample=rgb[exterior & (g>r+80)&(g>b+80)]
 bg=np.median(sample,axis=0)
 excess=np.maximum(0,g-np.maximum(r,b));coverage=np.clip(excess/max(bg[1]-max(bg[0],bg[2]),1),0,1)
 alpha=np.ones(g.shape,np.float32);alpha[exterior]=1-coverage[exterior]
 # Near-key exterior is background even with JPEG/video noise; black/dark outlines are opaque.
 alpha[exterior & (coverage>.88)]=0
 fg=np.clip((rgb-(1-alpha[:,:,None])*bg)/np.maximum(alpha[:,:,None],.025),0,255)
 fg[alpha==0]=0
 return np.dstack([fg,alpha*255]).astype(np.uint8)
def cut(image,box,limit=256):
 x0,y0,x1,y1=box;a=key(np.asarray(image.convert('RGB'))[y0:y1,x0:x1])
 labels,n=nd.label(a[:,:,3]>90);sizes=np.bincount(labels.ravel());sizes[0]=0;main=labels==sizes.argmax()
 ys,xs=np.where(main);bounds=[max(0,xs.min()-12),max(0,ys.min()-12),min(a.shape[1],xs.max()+13),min(a.shape[0],ys.max()+13)]
 # Keep antialias fringe connected to the actual object, never sheet grid lines/noise islands.
 mask=nd.binary_dilation(main,iterations=3);a[~mask]=0
 im=Image.fromarray(a).crop(bounds);factor=min(1,limit/max(im.size));im=im.resize((round(im.width*factor),round(im.height*factor)),Image.Resampling.LANCZOS)
 return im,{'panel':box,'bounds_in_panel':list(map(int,bounds)),'scale':factor}
def panels(image):
 a=np.asarray(image.convert('RGB'));dark=a.max(2)<55
 def groups(values):
  return [v for v in np.split(values,np.where(np.diff(values)>1)[0]+1) if len(v)]
 rows=groups(np.where(dark.mean(1)>.85)[0]);assert len(rows)==3,len(rows)
 top,bottom=rows[0],rows[1];last=rows[2]
 upper=groups(np.where(dark[top[-1]+5:bottom[0]-5].mean(0)>.85)[0]);lower=groups(np.where(dark[bottom[-1]+5:last[0]-5].mean(0)>.85)[0])
 assert len(upper)==4 and len(lower)==3,(len(upper),len(lower))
 return [[int(upper[i][-1]+4),int(top[-1]+4),int(upper[i+1][0]-3),int(bottom[0]-3)] for i in range(3)]+[[int(lower[i][-1]+4),int(bottom[-1]+4),int(lower[i+1][0]-3),int(last[0]-3)] for i in range(2)]
meta={}; board=Image.new('RGB',(1450,1050),'#eeeeeb');draw=ImageDraw.Draw(board)
for j,(id,filename) in enumerate(files.items()):
 image=Image.open(SRC/filename)
 boxes=dict(zip(['arm_l','torso','arm_r','leg_l','leg_r'],panels(image)))
 dest=OUT/id;dest.mkdir(parents=True,exist_ok=True);parts={}
 for k,box in boxes.items():
  im,details=cut(image,box);im.save(dest/(k+'.png'));parts[k]={'size':list(im.size),'source':details}
  if k=='torso':board.paste(im,(j*290+15,40),im);draw.text((j*290+15,12),id,fill='black')
  elif k=='arm_l':board.paste(im,(j*290+15,350),im)
  elif k=='leg_l':board.paste(im,(j*290+15,650),im)
 meta[id]={'source':filename,'parts':parts}
headsheet=Image.open(SRC/'file_00000000f230822fb783c708d31097dd.png')
ids=['devil','vampire','cowboy','tiger','shark']
headboxes=panels(headsheet)
for id,box in zip(ids,headboxes):
 im,detail=cut(headsheet,box,256);im.save(OUT/id/'head_base.png');meta[id]['parts']['head']={'size':list(im.size),'source':detail}
(work/'extracted.json').write_text(json.dumps(meta,indent=2),encoding='utf8');board.save(work/'parts.png')
print(json.dumps({k:{p:v['size'] for p,v in d['parts'].items()} for k,d in meta.items()},indent=2))
