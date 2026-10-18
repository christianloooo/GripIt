"""Import the user-supplied open Hand.R from Rigged Hands.blend.

Run Blender with --disable-autoexec before --python. Authored mesh and painted
weights are retained; only the long forearm is trimmed and topology reduced for
mobile rendering. No procedural palm/finger sculpting is applied.
"""
import bpy, bmesh, json, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'ios/GripItScannerCore/Sources/GripItScannerCore/Resources'
bpy.context.view_layer.update()
src = bpy.data.objects['Hand.R']
rig = bpy.data.objects['Hand_Right']
bones = rig.data.bones
aliases = {
 'Bone.020':'wrist', 'Bone.016':'palm',
 'Bone.012':'index-finger-metacarpal','Bone':'index-finger-phalanx-proximal',
 'Bone.001':'index-finger-phalanx-intermediate','Bone.002':'index-finger-phalanx-distal',
 'Bone.013':'middle-finger-metacarpal','Bone.003':'middle-finger-phalanx-proximal',
 'Bone.004':'middle-finger-phalanx-intermediate','Bone.005':'middle-finger-phalanx-distal',
 'Bone.014':'ring-finger-metacarpal','Bone.006':'ring-finger-phalanx-proximal',
 'Bone.007':'ring-finger-phalanx-intermediate','Bone.008':'ring-finger-phalanx-distal',
 'Bone.015':'pinky-finger-metacarpal','Bone.009':'pinky-finger-phalanx-proximal',
 'Bone.010':'pinky-finger-phalanx-intermediate','Bone.011':'pinky-finger-phalanx-distal',
 'Bone.021':'thumb-palm','Bone.017':'thumb-metacarpal',
 'Bone.018':'thumb-phalanx-proximal','Bone.019':'thumb-phalanx-distal',
}
ends={'index':'Bone.002','middle':'Bone.005','ring':'Bone.008','pinky':'Bone.011','thumb':'Bone.019'}
world = lambda name, tail=False: rig.matrix_world @ (rig.pose.bones[name].tail if tail else rig.pose.bones[name].head)
origin=world('Bone.016')
y=(world('Bone.003')-origin).normalized()
x=world('Bone')-world('Bone.009');x=(x-y*x.dot(y)).normalized()
z=x.cross(y).normalized()
basis=Matrix((x,y,z)).transposed()
rotation=basis.transposed()
unit=62.0/(world('Bone')-world('Bone.009')).length
canonical=lambda p: rotation @ (p-origin)*unit

# This file has baked posed mesh copies with painted groups but no live
# armature modifier. Adopt the selected open pose as the new bind pose, using
# matching posed bone heads rather than unrelated edit-bone coordinates.
# This preserves the authored surface exactly instead of reverse-deforming it.
bind_positions=[canonical(src.matrix_world@v.co) for v in src.data.vertices]
obj=src.copy();obj.data=src.data.copy();bpy.context.collection.objects.link(obj)
obj.parent=None;obj.matrix_world=Matrix.Identity(4)
for v, position in zip(obj.data.vertices,bind_positions):v.co=position
obj.name='GripIt supplied neutral hand'
for g in obj.vertex_groups:
 if g.name in aliases:g.name=aliases[g.name]
# Preserve painted weights through a short wrist cut and a conservative decimation.
bm=bmesh.new();bm.from_mesh(obj.data)
bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
 plane_co=Vector((0,-28,0)),plane_no=Vector((0,1,0)),clear_inner=True,clear_outer=False)
boundary=[e for e in bm.edges if e.is_boundary and all(abs(v.co.y+28)<0.01 for v in e.verts)]
if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=0)
bm.to_mesh(obj.data);bm.free()
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
dec=obj.modifiers.new('Mobile topology','DECIMATE');dec.ratio=0.62
bpy.ops.object.modifier_apply(modifier=dec.name)
obj.data.calc_loop_triangles()
for p in obj.data.polygons:p.use_smooth=True

ordered=[n for n in bones.keys() if n in aliases]
joints=[]
for name in ordered:
 # The wrist anchor is at the base of the hand, not at the forearm's root.
 p=Vector((0,0,0)) if name=='Bone.020' else canonical(world(name))
 joints.append(dict(name=aliases[name],position=list(p)))
for f, name in ends.items():
 label='thumb-tip' if f=='thumb' else f'{f}-finger-tip'
 joints.append(dict(name=label,position=list(canonical(world(name,True)))))
joint_ids={j['name']:i for i,j in enumerate(joints)}
vertices=[list(v.co) for v in obj.data.vertices]
weights=[]
for v in obj.data.vertices:
 w=[0.0]*len(joints)
 for g in v.groups:
  name=obj.vertex_groups[g.group].name
  if name in joint_ids:w[joint_ids[name]]+=g.weight
 total=sum(w)
 if total<1e-8:w[joint_ids['wrist']]=1.0
 else:w=[n/total for n in w]
 weights.append(w)
# Use the visible skin cap as the last segment endpoint, retaining actual bone
# heads at MCP/PIP/DIP. Bone tails can end slightly inside the supplied skin.
for f,name in ends.items():
 distal=joint_ids[aliases[name]];tip=joint_ids['thumb-tip' if f=='thumb' else f'{f}-finger-tip']
 start=Vector(joints[distal]['position']);direction=(Vector(joints[tip]['position'])-start).normalized()
 extent=max((Vector(p)-start).dot(direction) for p,w in zip(vertices,weights) if w[distal]>.6)
 joints[tip]['position']=list(start+direction*extent)

def radius(f):
 prefix='thumb' if f=='thumb' else f'{f}-finger'
 names=[f'{prefix}-metacarpal',f'{prefix}-phalanx-proximal',f'{prefix}-phalanx-distal'] if f=='thumb' else [f'{prefix}-phalanx-proximal',f'{prefix}-phalanx-intermediate',f'{prefix}-phalanx-distal']
 a=Vector(joints[joint_ids[names[1]]]['position']);b=Vector(joints[joint_ids[names[2]]]['position']);d=(b-a).normalized()
 values=[]
 ids=[joint_ids[n] for n in names]
 for p,w in zip(vertices,weights):
  v=Vector(p)-a;t=v.dot(d)
  if sum(w[i] for i in ids)>.7 and 0<t<(b-a).length*.7:values.append((v-d*t).length)
 values.sort()
 return values[int(len(values)*.7)] if values else 7.0
radii={f:radius(f) for f in ends}
indices=[i for t in obj.data.loop_triangles for i in t.vertices]
source_hash=hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()
payload=dict(vertices=vertices,weights=weights,joints=joints,indices=indices,
 source='User-supplied Rigged Hands.blend / Hand.R',sourceSHA256=source_hash,
 authoredFingerRadii=radii,preserveAuthoredAnatomy=True)
(OUT/'grip-hand.json').write_text(json.dumps(payload,separators=(',',':')))

# Create a portable armature whose deform bones carry the same weights as JSON.
data=bpy.data.armatures.new('Supplied hand skeleton');arm=bpy.data.objects.new('Supplied hand skeleton',data);bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm;obj.select_set(False);arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for name in ordered:
 bone=data.edit_bones.new(aliases[name]);bone.head=Vector(joints[joint_ids[aliases[name]]]['position'])/1000
 tail=canonical(world(name,True))/1000
 if (tail-bone.head).length<.0001:tail=bone.head+Vector((0,.003,0))
 bone.tail=tail
for name in ordered:
 parent=bones[name].parent
 if parent and parent.name in aliases:data.edit_bones[aliases[name]].parent=data.edit_bones[aliases[parent.name]]
for f,name in ends.items():
 label='thumb-tip' if f=='thumb' else f'{f}-finger-tip'
 bone=data.edit_bones.new(label);bone.head=Vector(joints[joint_ids[label]]['position'])/1000
 bone.tail=bone.head+Vector((0,.003,0));bone.parent=data.edit_bones[aliases[name]]
bpy.ops.object.mode_set(mode='OBJECT')
for v in obj.data.vertices:v.co/=1000
mod=obj.modifiers.new('Authored skin weights','ARMATURE');mod.object=arm;mod.use_deform_preserve_volume=True
obj.parent=arm
obj['gripitPreserveAnatomy']=True
obj['authoredFingerRadii']=radii
mat=bpy.data.materials.new('Neutral hand');mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.46,.28,.19,1);bs.inputs['Roughness'].default_value=.65
obj.data.materials.clear();obj.data.materials.append(mat)
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);arm.select_set(True);bpy.context.view_layer.objects.active=arm
bpy.ops.export_scene.gltf(filepath=str(ROOT/'public/models/supplied-hand.glb'),export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
print('EXPORTED_HAND',len(vertices),'vertices',len(indices)//3,'triangles',radii)
(ROOT/'work/hand-rig/import-summary.json').write_text(json.dumps({k:v for k,v in payload.items() if k not in ['vertices','weights','indices']},indent=2))
