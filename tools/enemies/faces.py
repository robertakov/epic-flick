from pathlib import Path
import json
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from scipy import ndimage as nd
import av
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'game/assets/enemies'
s=Path(__file__).with_name('extract.py').read_text(encoding='utf-8-sig');exec(s[s.index('def key('):s.index('meta={};')])
ids=['devil','vampire','cowboy','tiger','shark']
patches={'devil':[.27,.40,.85,.86],'vampire':[.34,.32,.76,.68],'cowboy':[.31,.48,.79,.76],'tiger':[.32,.42,.85,.68],'shark':[.40,.38,.82,.65]}
selections={'devil':[0,8,16,24,72,72,168,120,192,176],'vampire':[0,8,16,144,0,0,168,120,192,176],'cowboy':[0,8,16,48,96,72,24,120,192,32],'tiger':[0,8,16,48,72,72,24,120,192,32],'shark':[0,8,16,48,72,72,24,120,192,32]}
indices=sorted(set(i for frames in selections.values() for i in frames))
clips={'idle':[0,1,2,1],'neutral':[0,1,2,1],'scared':[3],'angry':[4],'determined':[5],'happy':[6,9],'dizzy':[7],'death':[8]}
capture={}
with av.open(str(ROOT/'Characters/Enamies/700012142_1791771975780390.mp4')) as c:
 for i,f in enumerate(c.decode(video=0)):
  if i in indices:capture[i]=f.to_image()
# The video has no horizontal outer frame. Measured divider bands: x638..646/1275..1283,
# y536..544, lower x955..963; avoid those actual black lines, not equal-percentage slicing.
panel_boxes=[[12,5,635,531],[650,5,1272,531],[1287,5,1908,531],[12,549,952,1075],[967,549,1908,1075]]
report={};board=Image.new('RGB',(1400,760),'#ddd');d=ImageDraw.Draw(board)
for col,id in enumerate(ids):
 base=Image.open(OUT/id/'head_base.png').convert('RGBA');a=np.asarray(base);w,h=base.size
 rect=patches[id];mask=Image.new('L',(w,h));draw=ImageDraw.Draw(mask);draw.ellipse((rect[0]*w,rect[1]*h,rect[2]*w,rect[3]*h),fill=255)
 mask=mask.filter(ImageFilter.GaussianBlur(2));alpha=np.asarray(mask,dtype=float)/255
 shell=(a[:,:,3]>180)&(alpha<.05)
 frames=[];offsets=[]
 for i in selections[id]:
  frame,_=cut(capture[i],panel_boxes[col]);frame=frame.resize((w,h),Image.Resampling.LANCZOS);v=np.asarray(frame)
  best=(1e9,0,0)
  for dy in range(-5,6):
   for dx in range(-5,6):
    shifted=nd.shift(v.astype(float),(dy,dx,0),order=0,mode='constant')
    cost=np.mean(np.abs(a[:,:,:3].astype(float)-shifted[:,:,:3])[shell])
    if cost<best[0]:best=(cost,dx,dy)
  shifted=nd.shift(v.astype(float),(best[2],best[1],0),order=1,mode='constant')
  use=alpha*np.minimum(1,shifted[:,:,3]/255)
  rgba=a.copy();rgba[:,:,:3]=np.clip(a[:,:,:3]*(1-use[:,:,None])+shifted[:,:,:3]*use[:,:,None],0,255).astype(np.uint8)
  rgba[:,:,3]=a[:,:,3] # All frame silhouettes/pivots are exactly the same rigid head shell.
  frames.append(Image.fromarray(rgba));offsets.append({'frame':i,'dx':best[1],'dy':best[2],'shell_error':round(best[0],2)})
 atlas=Image.new('RGBA',(w*5,h*2))
 for i,im in enumerate(frames):atlas.paste(im,((i%5)*w,(i//5)*h))
 atlas.save(OUT/id/'head.png')
 meta={'frame_size':[w,h],'count':len(frames),'columns':5,'fps':3,'clips':clips,'face_region':rect,'registration':offsets,'fixed_shell_alpha':True}
 (OUT/id/'face.json').write_text(json.dumps(meta,indent=2),encoding='utf8');report[id]=meta
 for row,idx in enumerate([0,4,6,3]):
  im=frames[idx];board.paste(im,(col*280+12,row*190+5),im);d.text((col*280+12,row*190+165),id+' '+['idle','angry','happy','scared'][row],fill='black')
board.save(ROOT/'reports/v19_processing/face_review.png')
(ROOT/'reports/v19_processing/face_registration.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('50 fixed-shell facial frames, 5 atlases; body sprites remain static')
