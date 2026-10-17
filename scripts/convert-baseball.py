"""Convert the CC BY 4.0 Alex Bes USD mesh to a local, 73 mm GLB.
Usage: python convert-baseball.py path/to/extracted/ball.usda path/to/textures
Requires Pillow. usdcat can convert scene.usdc to ASCII USD first.
"""
import ast, io, json, math, re, struct, sys
from pathlib import Path
from PIL import Image
source=Path(sys.argv[1]).read_text();folder=Path(sys.argv[2]);out=Path('public/models');out.mkdir(parents=True,exist_ok=True)
def array(name):return ast.literal_eval(re.search(r'\b'+re.escape(name)+r' = (\[[^\n]+\])',source).group(1))
points=array('points');normals=array('normals');uv=array('primvars:st0');indices=array('faceVertexIndices')
lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)];center=[(a+b)/2 for a,b in zip(lo,hi)]
radius=max(math.dist(p,center) for p in points)
positions=[tuple((p[i]-center[i])/math.dist(p,center)*36.5 for i in range(3)) for p in points]
normals=[tuple(v/36.5 for v in p) for p in positions]
base=Image.open(folder/'lambert1_baseColor.jpg').convert('RGB');normal=Image.open(folder/'lambert1_normal.jpg').convert('RGB')
rough=Image.open(folder/'lambert1_metallicRoughness_rough.jpg').convert('L').resize((2048,2048));occ=Image.open(folder/'lambert1_metallicRoughness_occl.jpg').convert('L').resize((2048,2048));orm=Image.merge('RGB',(occ,rough,Image.new('L',(2048,2048),0)))
# Recover stitch locations from the original UV/material, not a made-up seam curve.
pixels=base.load();w,h=base.size;seam=[];seen=set()
for offset in range(0,len(indices),3):
 ids=indices[offset:offset+3]
 for a in range(17):
  for b in range(17-a):
   weights=(a/16,b/16,1-(a+b)/16)
   u=sum(uv[j][0]*t for j,t in zip(ids,weights));v=sum(uv[j][1]*t for j,t in zip(ids,weights))
   r,g,bl=pixels[min(w-1,max(0,int(u*w))),min(h-1,max(0,int((1-v)*h)))]
   if r<55 or r<g*1.35 or r<bl*1.35:continue
   point=[sum(positions[j][i]*t for j,t in zip(ids,weights)) for i in range(3)]
   length=math.sqrt(sum(t*t for t in point));point=[t/36.5 for t in point];key=tuple(round(t,2) for t in point)
   if key not in seen:seen.add(key);seam.append([round(t,7) for t in point])
if len(seam)<100:raise RuntimeError(f'Only {len(seam)} stitch samples; inspect the albedo threshold.')
Path('src/baseballSeams.json').write_text(json.dumps(seam,separators=(',',':')))
blob=bytearray();views=[];accessors=[]
def buffer(data,target=None):
 while len(blob)%4:blob.append(0)
 view={'buffer':0,'byteOffset':len(blob),'byteLength':len(data)}
 if target:view['target']=target
 views.append(view);blob.extend(data);return len(views)-1
def attr(values,dimension,kind='VEC3',component=5126):
 raw=struct.pack('<'+('I' if component==5125 else 'f')*len(values),*values);view=buffer(raw,34963 if component==5125 else 34962)
 ac={'bufferView':view,'componentType':component,'count':len(values)//dimension,'type':kind}
 if kind=='VEC3' and not accessors:ac.update(min=[min(values[i::3]) for i in range(3)],max=[max(values[i::3]) for i in range(3)])
 accessors.append(ac);return len(accessors)-1
pos=attr([n for p in positions for n in p],3);nor=attr([n for p in normals for n in p],3);tex=attr([n for u,v in uv for n in (u,1-v)],2,'VEC2');ind=attr(indices,1,'SCALAR',5125)
images=[]
for image in (base,normal,orm):
 image.thumbnail((2048,2048),Image.Resampling.LANCZOS);stream=io.BytesIO();image.save(stream,format='JPEG',quality=92);images.append({'bufferView':buffer(stream.getvalue()),'mimeType':'image/jpeg'})
gltf={'asset':{'version':'2.0','generator':'GripIt USD conversion','copyright':'Worn Baseball Ball by Alex Bes, CC BY 4.0'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0}],'meshes':[{'primitives':[{'attributes':{'POSITION':pos,'NORMAL':nor,'TEXCOORD_0':tex},'indices':ind,'material':0}]}],'materials':[{'name':'Worn leather','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicFactor':0,'roughnessFactor':1,'metallicRoughnessTexture':{'index':2}},'normalTexture':{'index':1,'scale':.7},'occlusionTexture':{'index':2,'strength':.6}}],'textures':[{'source':i} for i in range(3)],'images':images,'bufferViews':views,'accessors':accessors,'buffers':[{'byteLength':len(blob)}]}
js=json.dumps(gltf,separators=(',',':')).encode();js+=b' '*((-len(js))%4);blob+=b'\0'*((-len(blob))%4)
result=struct.pack('<III',0x46546C67,2,12+8+len(js)+8+len(blob))+struct.pack('<II',len(js),0x4E4F534A)+js+struct.pack('<II',len(blob),0x004E4942)+blob
(out/'baseball.glb').write_bytes(result)
print(f'{len(points)} vertices, {len(indices)//3} triangles, {len(seam)} seam samples; normalized radius 36.5 mm; GLB {len(result)} bytes')
