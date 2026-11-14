# Slice the owner's alpha art sheets (nexora-ui-refs) into individual transparent WebP icons.
import sys, numpy as np
from PIL import Image
from scipy import ndimage
REF='/workspace/work/nexora-ui-refs/'
def slice_sheet(fn, names, out, thr=40, dil=9, minarea=4000, size=256):
    im=Image.open(REF+fn).convert('RGBA'); a=np.array(im)
    m=a[:,:,3]>thr
    lab,n=ndimage.label(ndimage.binary_dilation(m,iterations=dil))
    objs=ndimage.find_objects(lab)
    boxes=[]
    for i,sl in enumerate(objs):
        area=(lab[sl]==i+1).sum()
        if area<minarea: continue
        boxes.append((sl[0].start,sl[0].stop,sl[1].start,sl[1].stop,area))
    # row-major ordering: cluster by vertical centre
    boxes.sort(key=lambda b:(b[0]+b[1])/2)
    rows=[];
    for b in boxes:
        cy=(b[0]+b[1])/2
        if rows and abs(cy-rows[-1][0])<(b[1]-b[0])*0.45: rows[-1][1].append(b)
        else: rows.append([cy,[b]])
    ordered=[b for r in rows for b in sorted(r[1],key=lambda b:b[2])]
    print(fn, 'found', len(ordered), 'expected', len(names))
    for b,nm in zip(ordered,names):
        y0,y1,x0,x1,_=b; crop=im.crop((x0,y0,x1,y1))
        w,h=crop.size; s=size/max(w,h); crop=crop.resize((max(1,int(w*s)),max(1,int(h*s))),Image.LANCZOS)
        crop.save(out+nm+'.webp','WEBP',quality=86,method=6)
slice_sheet('file_0000000091d08246b693fb26cb2b4e5f-bdc3e569a0a7.webp',
  ['ball','cup','stadium','shield','team','tactics','gift','chest','calendar','gear','mega','bell','star','coin','gem','profile'],
  'assets/g/kit/k_')
slice_sheet('file_00000000dc4c820a8154f8b67dacf6c5-7a3bebdf7165.webp',
  ['cards','gamepad','portal','hood','hood2','crate','orbs','cog'], 'assets/g/kit/w_', size=320)
# disc ring wheel: whole image
im=Image.open(REF+'Picsart_26-11-12_16-06-14-296-db357fe94fa1.webp').convert('RGBA'); im=im.resize((640,int(640*im.size[1]/im.size[0])),Image.LANCZOS); im.save('assets/g/kit/disc_ring.webp','WEBP',quality=84,method=6)
