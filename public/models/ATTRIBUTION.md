# Current baseball: project-supplied Ball.glb

`assets/source/Ball.glb` is the original file supplied for this project. The
runtime `baseball.glb` uses its `Baseball_Ball_Clean` variant, original UVs, and
PBR maps, recentered and normalized to a 73 mm sphere. The original file's asset
metadata names Blender as its generator and does not name a creator or license.
Source SHA-256: `29dffd40550f1a938d2caa63a2061a1c3b57e5e5e055637ba5bed30f49c0a0ca`.
The unused dirty variant remains in the source file. `scripts/import-baseball.py`
generates the optimized runtime asset and its own stitch samples.

The following worn-ball credit is retained for the previous asset and conversion
script; it is not an attribution claim for the newly supplied file.

# Worn Baseball Ball

Original: **Worn Baseball Ball** by **Alex Bes (@alexbescg)**
https://sketchfab.com/3d-models/worn-baseball-ball-fdf3de6ae225421ea78961b897b9608a
License: **Creative Commons Attribution 4.0 International (CC BY 4.0)**
https://creativecommons.org/licenses/by/4.0/

Downloaded from the public redistribution in:
https://huggingface.co/datasets/barszot/3d-models-for-isaac-sim-dataset/blob/main/small_ball/baseball_ball.usdz
The enclosed source USD metadata identifies Alex Bes and CC-BY-4.0.

Changes: extracted source mesh/textures from nested USDZ, recentered and radially normalized to a 73 mm sphere (with corresponding radial base normals), converted to glTF binary, resized texture maps to 2048 pixels, packed roughness/occlusion channels, and sampled visible stitch pixels into contact-reference points. Outer scene wrappers and lights were omitted. The original source scale does not establish regulation dimensions; GripIt applies the 73 mm reference explicitly.

# Rigged hand

Generic right-hand mesh from the Immersive Web WebXR Input Profiles assets, package @webxr-input-profiles/assets@1.0, `generic-hand/right.glb`.
https://github.com/immersive-web/webxr-input-profiles/tree/main/packages/assets
MIT license: included as HAND-LICENSE.md.
Modified at runtime: recentered, converted to millimeters, proportioned, given a skin material, and retargeted to GripIt FK anchors. Source geometry is cloned before modification.
