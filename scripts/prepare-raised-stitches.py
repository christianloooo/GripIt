"""Build continuous, equal-radius thread from the supplied clean Ball.glb albedo.
Run with Python, NumPy and Pillow. Original ball geometry, UVs and maps are retained.
"""
import hashlib, io, json, math, struct
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image
root = Path(__file__).resolve().parents[1]
raw = (root/'assets/source/Ball.glb').read_bytes()
n = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20+n]); binary = raw[28+n:]
mat = doc['materials'][0]
image = doc['images'][doc['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
view = doc['bufferViews'][image['bufferView']]
im = Image.open(io.BytesIO(binary[view['byteOffset']:view['byteOffset']+view['byteLength']])).convert('RGB')
im.thumbnail((2048,2048)); rgb = np.asarray(im).astype(float); h,w = rgb.shape[:2]
mask = (rgb[:,:,0]>rgb[:,:,1]*2)&(rgb[:,:,0]>rgb[:,:,2]*2)&(rgb[:,:,0]>70)
seen=np.zeros((h,w),bool); groups=[]
for y,x in zip(*np.where(mask)):
    if seen[y,x]: continue
    q=deque([(y,x)]);seen[y,x]=True;group=[]
    while q:
        yy,xx=q.popleft();group.append((xx,yy))
        for dy,dx in ((0,1),(0,-1),(1,0),(-1,0),(1,1),(1,-1),(-1,1),(-1,-1)):
            ny,nx=yy+dy,xx+dx
            if 0<=ny<h and 0<=nx<w and mask[ny,nx] and not seen[ny,nx]:
                seen[ny,nx]=True;q.append((ny,nx))
    if len(group)>25: groups.append(np.asarray(group,float))
asset=json.loads((root/'ios/GripItScannerCore/Sources/GripItScannerCore/Resources/grip-baseball.json').read_text())
xyz=np.asarray(asset['vertices']);uv=np.asarray(asset['uv']);tri=np.asarray(asset['indices']).reshape(-1,3)
a,b,c=uv[tri[:,0]],uv[tri[:,1]],uv[tri[:,2]]
v0=b-a;v1=c-a;den=v0[:,0]*v1[:,1]-v1[:,0]*v0[:,1]
seams=np.asarray([s['position'] for s in asset['seams']])
def project(pixel):
    t=pixel/np.array([w,h]);v2=t-a
    with np.errstate(divide='ignore',invalid='ignore'):
        u=(v2[:,0]*v1[:,1]-v1[:,0]*v2[:,1])/den
        v=(v0[:,0]*v2[:,1]-v2[:,0]*v0[:,1])/den
    found=np.where((u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(np.abs(den)>1e-10))[0]
    if len(found)==0:return None
    i=found[0];p=xyz[tri[i,0]]*(1-u[i]-v[i])+xyz[tri[i,1]]*u[i]+xyz[tri[i,2]]*v[i]
    return p/np.linalg.norm(p)*36.5
verts=[];normals=[];indices=[];stitches=0;lengths=[]
for group in groups:
    mean=group.mean(axis=0); eig,axes=np.linalg.eigh(np.cov(group.T))
    if eig[1]<eig[0]*2.5:continue
    axis=axes[:,1];along=(group-mean)@axis
    # Bin by axial position to retain gentle curves in the original thread stroke.
    lo,hi=np.quantile(along,[.03,.97]); count=max(5,int((hi-lo)/3))
    pixels=[]
    side=np.array([-axis[1],axis[0]])
    for t in np.linspace(lo,hi,count):
        near=group[np.abs(along-t)<max(2,(hi-lo)/count)]
        cross=np.median((near-mean)@side) if len(near) else 0
        pixels.append(mean+axis*t+side*cross)
    points=[project(p) for p in pixels]
    # Discard printing and unused UV padding, rather than lifting every red texel.
    if any(p is None for p in points):continue
    points=np.asarray(points)
    length=np.linalg.norm(np.diff(points,axis=0),axis=1).sum()
    if not .7<length<9:continue
    if np.min(np.linalg.norm(seams-points[len(points)//2],axis=1))>3:continue
    stitches+=1;lengths.append(float(length));start=len(verts);rings=len(points);sides=10
    for j,p in enumerate(points):
        normal=p/np.linalg.norm(p)
        tangent=points[min(j+1,rings-1)]-points[max(0,j-1)]
        tangent/=np.linalg.norm(tangent)
        lateral=np.cross(tangent,normal);lateral/=np.linalg.norm(lateral)
        center=normal*36.75
        for k in range(sides):
            angle=k*2*math.pi/sides
            direction=normal*math.cos(angle)+lateral*math.sin(angle)
            verts.append((center+direction*.32).tolist());normals.append(direction.tolist())
    for j in range(rings-1):
        for k in range(sides):
            aa=start+j*sides+k;bb=start+j*sides+(k+1)%sides;cc=aa+sides;dd=bb+sides
            indices.extend([aa,bb,cc,bb,dd,cc])
    # Close both tube ends: no disconnected spikes or missing stitch faces.
    for j,reverse in ((0,True),(rings-1,False)):
        center=points[j]/np.linalg.norm(points[j])*36.75
        cap=len(verts);verts.append(center.tolist())
        tangent=points[1]-points[0] if j==0 else points[-1]-points[-2]
        tangent=tangent/np.linalg.norm(tangent)*(-1 if reverse else 1);normals.append(tangent.tolist())
        for k in range(sides):
            aa=start+j*sides+k;bb=start+j*sides+(k+1)%sides
            indices.extend([cap,bb,aa] if reverse else [cap,aa,bb])
# Keep winding consistent with the outward thread normals at tight UV curves.
for i in range(0,len(indices),3):
    ids=indices[i:i+3];p=np.asarray([verts[j] for j in ids]);normal=np.asarray([normals[j] for j in ids]).sum(axis=0)
    if np.dot(np.cross(p[1]-p[0],p[2]-p[0]),normal)<0:
        indices[i+1],indices[i+2]=indices[i+2],indices[i+1]
assert stitches>150, f'Only {stitches} original thread strokes recovered'
result=dict(vertices=np.round(verts,6).tolist(),normals=np.round(normals,6).tolist(),indices=indices,
    stitchCount=stitches,threadRadiusMm=.32,threadCenterRadiusMm=36.75,
    sourceSHA256=hashlib.sha256(raw).hexdigest())
folder=root/'ios/GripItScannerCore/Sources/GripItScannerCore/Resources'
(folder/'grip-baseball-stitches.json').write_text(json.dumps(result,separators=(',',':')))
print(f'{stitches} continuous stitches; {len(verts)} vertices; equal thread radius 0.32 mm; raised height 0.57 mm; lengths {min(lengths):.2f}–{max(lengths):.2f} mm')
