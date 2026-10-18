"""Import the project-supplied Ball.glb clean variant into GripIt's mm coordinates.
Keeps original UVs and PBR maps; derives stitch references from this ball's albedo.
Requires Pillow, also used by convert-baseball.py. Source is never modified.
"""
import hashlib, io, json, math, struct, sys
from pathlib import Path
from PIL import Image

source = Path(sys.argv[1] if len(sys.argv) > 1 else 'assets/source/Ball.glb')
raw = source.read_bytes()
if raw[:4] != b'glTF': raise ValueError('Expected a GLB source')
size = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20+size]); binary = raw[28+size:]
node = next(n for n in doc['nodes'] if n.get('name') == 'Baseball_Ball_Clean')
primitive = doc['meshes'][node['mesh']]['primitives'][0]
material = doc['materials'][primitive['material']]
def read(index):
    a = doc['accessors'][index]; v = doc['bufferViews'][a['bufferView']]
    count = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    char = {5126:'f',5125:'I',5123:'H'}[a['componentType']]
    stride = v.get('byteStride', count*struct.calcsize(char))
    offset = v.get('byteOffset',0)+a.get('byteOffset',0)
    return [list(struct.unpack_from('<'+char*count,binary,offset+i*stride)) for i in range(a['count'])]
def image(texture):
    im = doc['images'][doc['textures'][texture]['source']]
    v = doc['bufferViews'][im['bufferView']]
    return Image.open(io.BytesIO(binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])).convert('RGB')
positions = read(primitive['attributes']['POSITION']); uv = read(primitive['attributes']['TEXCOORD_0'])
indices = [i[0] for i in read(primitive['indices'])]
center = [(min(p[i] for p in positions)+max(p[i] for p in positions))/2 for i in range(3)]
positions = [[(p[i]-center[i])/math.dist(p,center)*36.5 for i in range(3)] for p in positions]
normals = [[v/36.5 for v in p] for p in positions]
base = image(material['pbrMetallicRoughness']['baseColorTexture']['index'])
normal = image(material['normalTexture']['index'])
packed = image(material['pbrMetallicRoughness']['metallicRoughnessTexture']['index'])
# Read this asset's own stitched surface; glTF UVs use the image's top-left origin.
pixels=base.load(); width,height=base.size; cloud=[]; seen=set(); resolution=40
for offset in range(0,len(indices),3):
    ids=indices[offset:offset+3]
    for a in range(resolution+1):
        for b in range(resolution+1-a):
            weights=(a/resolution,b/resolution,1-(a+b)/resolution)
            u=sum(uv[j][0]*w for j,w in zip(ids,weights)); v=sum(uv[j][1]*w for j,w in zip(ids,weights))
            r,g,blue=pixels[min(width-1,max(0,int(u*width))),min(height-1,max(0,int(v*height)))]
            if r<60 or r<g*1.45 or r<blue*1.45: continue
            point=[sum(positions[j][i]*w for j,w in zip(ids,weights)) for i in range(3)]
            length=math.sqrt(sum(x*x for x in point)); point=[x/length for x in point]
            key=tuple(round(x,2) for x in point)
            if key not in seen: seen.add(key); cloud.append([round(x,7) for x in point])
if len(cloud)<500: raise RuntimeError(f'Insufficient stitch references: {len(cloud)}')
Path('src/baseballSeams.json').write_text(json.dumps(cloud,separators=(',',':')))
images=[]
for im,format in [(base,'JPEG'),(normal,'PNG'),(packed,'PNG')]:
    im.thumbnail((2048,2048),Image.Resampling.LANCZOS)
    stream=io.BytesIO(); im.save(stream,format=format,**({'quality':94} if format=='JPEG' else {'optimize':True}))
    images.append((stream.getvalue(),'image/jpeg' if format=='JPEG' else 'image/png'))
blob=bytearray(); views=[]; accessors=[]
def buffer(data,target=None):
    while len(blob)%4:blob.append(0)
    v={'buffer':0,'byteOffset':len(blob),'byteLength':len(data)}
    if target:v['target']=target
    views.append(v);blob.extend(data);return len(views)-1
def attribute(values,count,kind,component=5126):
    flat=[x for row in values for x in row]; char='f' if component==5126 else 'I'
    v=buffer(struct.pack('<'+char*len(flat),*flat),34962 if component==5126 else 34963)
    a={'bufferView':v,'componentType':component,'count':len(values),'type':kind}
    if kind=='VEC3' and not accessors:a.update(min=[min(p[i]for p in values)for i in range(3)],max=[max(p[i]for p in values)for i in range(3)])
    accessors.append(a);return len(accessors)-1
pos=attribute(positions,3,'VEC3'); nor=attribute(normals,3,'VEC3'); tex=attribute(uv,2,'VEC2'); idx=attribute([[i]for i in indices],1,'SCALAR',5125)
image_defs=[{'bufferView':buffer(data),'mimeType':mime}for data,mime in images]
sha=hashlib.sha256(raw).hexdigest()
result={'asset':{'version':'2.0','generator':'GripIt supplied Ball.glb import'},'scene':0,'scenes':[{'nodes':[0]}],
'nodes':[{'name':'Baseball_Ball_Clean','mesh':0}],'meshes':[{'primitives':[{'attributes':{'POSITION':pos,'NORMAL':nor,'TEXCOORD_0':tex},'indices':idx,'material':0}]}],
'materials':[{'name':'Supplied clean baseball','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicRoughnessTexture':{'index':2},'metallicFactor':1,'roughnessFactor':1},'normalTexture':{'index':1}}],
'images':image_defs,'textures':[{'source':i}for i in range(3)],'bufferViews':views,'accessors':accessors,'buffers':[{'byteLength':len(blob)}],
'extras':{'source':'assets/source/Ball.glb','sourceSHA256':sha,'variant':'Baseball_Ball_Clean','radiusMm':36.5}}
js=json.dumps(result,separators=(',',':')).encode();js+=b' '*((-len(js))%4);blob+=b'\0'*((-len(blob))%4)
Path('public/models/baseball.glb').write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob)
# SceneKit's UIImage texture path uses the supplied glTF UVs directly.
folder=Path('ios/GripItScannerCore/Sources/GripItScannerCore/Resources')
normal.save(folder/'grip-baseball-normal.png',optimize=True)
packed.save(folder/'grip-baseball-material.png',optimize=True)
(folder/'grip-baseball-attribution.txt').write_text('Project-supplied Ball.glb, clean variant.\nSource SHA-256: '+sha+'\nThe source GLB names no creator or license in its asset metadata.\nImported with original UVs and PBR textures; normalized to 73 mm diameter.\n')
print(f'Imported clean Ball.glb: {len(positions)} vertices, {len(cloud)} stitch samples, {(28+len(js)+len(blob))/1e6:.1f} MB runtime GLB.')
