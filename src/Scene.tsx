import { Component, Suspense, useEffect, useMemo, useRef } from "react";
import type { ReactNode } from "react";
import { Canvas } from "@react-three/fiber";
import {
  ContactShadows,
  Html,
  Line,
  OrbitControls,
  PerspectiveCamera,
  useGLTF,
} from "@react-three/drei";
import * as THREE from "three";
import { BALL_RADIUS, handScale, solveGrip } from "./grip";
import { retargetHand } from "./riggedHand";
import { createHandSurface } from "./handSurface";
import type { FingerRig, Measurements, Pitch } from "./grip";

const SKIN = "#c9987d";
function skinTexture() {
  let seed = 8423;
  const pixels = new Uint8Array(256 * 256 * 4);
  for (let i = 0; i < 256 * 256; i++) {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const value = 118 + (seed % 35);
    pixels.set([value, value, value, 255], i * 4);
  }
  const texture = new THREE.DataTexture(pixels, 256, 256);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(3, 3);
  texture.needsUpdate = true;
  return texture;
}
function HandSkin({
  rigs,
  measurements,
}: {
  rigs: FingerRig[];
  measurements: Measurements;
}) {
  const geometry = useMemo(
    () => createHandSurface(rigs, measurements),
    [rigs, measurements],
  );
  const pores = useMemo(skinTexture, []);
  useEffect(() => () => pores.dispose(), [pores]);
  useEffect(() => () => geometry.dispose(), [geometry]);
  return (
    <group>
      <mesh geometry={geometry} castShadow receiveShadow>
        <meshPhysicalMaterial
          color={SKIN}
          roughness={0.6}
          bumpMap={pores}
          bumpScale={0.12}
          clearcoat={0.08}
          clearcoatRoughness={0.7}
        />
      </mesh>
      {rigs.map((rig) => {
        const bend = rig.angles.reduce((sum, a) => sum + a, 0);
        const rotation = new THREE.Quaternion()
          .setFromAxisAngle(new THREE.Vector3(0, 0, 1), rig.yaw)
          .multiply(
            new THREE.Quaternion().setFromAxisAngle(
              new THREE.Vector3(1, 0, 0),
              bend,
            ),
          );
        const dorsal = new THREE.Vector3(0, 0, -1).applyQuaternion(rotation);
        const direction = rig.points[3].clone().sub(rig.points[2]).normalize();
        const position = rig.points[3]
          .clone()
          .addScaledVector(direction, -rig.radius * 0.55)
          .addScaledVector(dorsal, rig.radius * 0.72);
        return (
          <mesh
            key={rig.name}
            position={position}
            quaternion={rotation}
            scale={[rig.radius * 0.58, rig.radius * 0.88, 0.7]}
          >
            <sphereGeometry args={[1, 24, 16]} />
            <meshPhysicalMaterial
              color="#e7c4b1"
              roughness={0.36}
              clearcoat={0.35}
            />
          </mesh>
        );
      })}
    </group>
  );
}
class HandAssetBoundary extends Component<
  { children: ReactNode; rigs: FingerRig[]; measurements: Measurements },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <>
        <HandSkin
          rigs={this.props.rigs}
          measurements={this.props.measurements}
        />
        <Html position={[0, -100, 0]} center>
          <div className="scene-label">
            Fallback hand · reload to retry the rigged asset
          </div>
        </Html>
      </>
    ) : (
      this.props.children
    );
  }
}
function AnatomicalHand({
  rigs,
  measurements,
}: {
  rigs: FingerRig[];
  measurements: Measurements;
}) {
  const { scene } = useGLTF(`${import.meta.env.BASE_URL}models/right-hand.glb`);
  const hand = useMemo(() => {
    let source: THREE.SkinnedMesh | undefined;
    scene.traverse((o) => {
      if ((o as THREE.SkinnedMesh).isSkinnedMesh)
        source = o as THREE.SkinnedMesh;
    });
    if (!source) throw new Error("Hand asset has no skeleton");
    return retargetHand(source, rigs, measurements);
  }, [scene, rigs, measurements]);
  useEffect(
    () => () => {
      hand.mesh.geometry.dispose();
      (hand.mesh.material as THREE.Material).dispose();
      hand.mesh.skeleton.dispose();
    },
    [hand],
  );
  return <primitive object={hand.mesh} dispose={null} />;
}
function BaseballAsset() {
  const { scene } = useGLTF(`${import.meta.env.BASE_URL}models/baseball.glb`);
  return <primitive object={scene} dispose={null} />;
}
class BallAssetBoundary extends Component<
  { children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <>
        <mesh>
          <sphereGeometry args={[BALL_RADIUS, 32, 24]} />
          <meshStandardMaterial wireframe color="#b16c50" />
        </mesh>
        <Html center>
          <div className="scene-label">
            Ball asset failed to load. Refresh to retry.
          </div>
        </Html>
      </>
    ) : (
      this.props.children
    );
  }
}
function Baseball({ ball }: { ball: ReturnType<typeof solveGrip>["ball"] }) {
  return (
    <group position={ball.position} rotation={ball.rotation}>
      <BallAssetBoundary>
        <Suspense
          fallback={
            <Html center>
              <div className="scene-label">Loading baseball…</div>
            </Html>
          }
        >
          <BaseballAsset />
        </Suspense>
      </BallAssetBoundary>
    </group>
  );
}
function Contact({
  rig,
  text,
  number,
  ball,
}: {
  rig: FingerRig;
  text: string;
  number: number;
  ball: ReturnType<typeof solveGrip>["ball"];
}) {
  const outward = rig.target.clone().sub(ball.position).normalize();
  const end = rig.target.clone().addScaledVector(outward, -rig.radius + 0.9);
  const label = end
    .clone()
    .add(
      new THREE.Vector3(
        number === 3 ? 58 : number === 1 ? 52 : -53,
        number === 3 ? -20 : number === 1 ? 22 : 32,
        10,
      ),
    );
  return (
    <>
      <mesh position={end}>
        <sphereGeometry args={[2.2, 16, 16]} />
        <meshBasicMaterial color="#d8ff72" />
      </mesh>
      <Line
        points={[end, label]}
        color="#788c7c"
        lineWidth={1}
        dashed
        dashSize={2}
        gapSize={2}
      />
      <Html position={label} center distanceFactor={270} zIndexRange={[20, 0]}>
        <div className="scene-label">
          <span>{number}</span>
          {text}
        </div>
      </Html>
    </>
  );
}
function Model({
  measurements,
  pitch,
  annotations,
  left,
  exploded,
}: {
  measurements: Measurements;
  pitch: Pitch;
  annotations: boolean;
  left: boolean;
  exploded: boolean;
}) {
  const solution = useMemo(
    () => solveGrip(measurements, pitch),
    [measurements, pitch],
  );
  const rigs = solution.fingers;
  return (
    <group scale={[handScale(left), 1, 1]}>
      <group position={[0, exploded ? -32 : 0, exploded ? -25 : 0]}>
        <HandAssetBoundary rigs={rigs} measurements={measurements}>
          <Suspense
            fallback={
              <Html center>
                <div className="scene-label">Loading anatomical hand…</div>
              </Html>
            }
          >
            <AnatomicalHand rigs={rigs} measurements={measurements} />
          </Suspense>
        </HandAssetBoundary>
        {annotations &&
          [rigs[0], rigs[1], rigs[4]].map((rig, i) => (
            <Contact
              key={rig.name}
              rig={rig}
              number={i + 1}
              text={pitch.cues[i]}
              ball={solution.ball}
            />
          ))}
      </group>
      <Baseball ball={solution.ball} />
      {annotations &&
        rigs.slice(0, 2).map((r) => (
          <mesh key={r.name} position={r.target}>
            <sphereGeometry args={[1.5, 16, 16]} />
            <meshBasicMaterial color="#637c38" />
          </mesh>
        ))}
    </group>
  );
}

class SceneBoundary extends Component<
  { children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <div className="webgl-fallback">
        The 3D viewer needs WebGL. Enable hardware acceleration or try another
        browser.
      </div>
    ) : (
      this.props.children
    );
  }
}
export function Scene(props: {
  measurements: Measurements;
  pitch: Pitch;
  annotations: boolean;
  left: boolean;
  exploded: boolean;
  reset: number;
}) {
  const controls = useRef<React.ComponentRef<typeof OrbitControls>>(null);
  useEffect(() => {
    controls.current?.reset();
  }, [props.reset]);
  return (
    <SceneBoundary>
      <Canvas
        shadows
        dpr={[1, 2]}
        fallback={
          <div className="webgl-fallback">
            Your browser does not support WebGL.
          </div>
        }
      >
        <color attach="background" args={["#e9ece5"]} />
        <PerspectiveCamera makeDefault position={[-145, 95, 275]} fov={39} />
        <ambientLight intensity={1.4} />
        <hemisphereLight
          color="#fff7e9"
          groundColor="#8d9a87"
          intensity={0.6}
        />
        <directionalLight
          position={[-100, 180, 150]}
          intensity={2.3}
          castShadow
          shadow-mapSize={[2048, 2048]}
          shadow-camera-left={-180}
          shadow-camera-right={180}
          shadow-camera-top={180}
          shadow-camera-bottom={-180}
          shadow-normalBias={0.5}
        />
        <directionalLight
          position={[150, 0, -100]}
          intensity={1.1}
          color="#e3eed6"
        />
        <Suspense fallback={null}>
          <Model {...props} />
          <ContactShadows
            position={[0, -120, 0]}
            opacity={0.25}
            scale={400}
            blur={2.8}
            far={200}
            resolution={512}
          />
        </Suspense>
        <OrbitControls
          ref={controls}
          makeDefault
          target={[0, -5, 5]}
          minDistance={150}
          maxDistance={520}
          maxPolarAngle={Math.PI * 0.91}
          enableDamping
        />
      </Canvas>
    </SceneBoundary>
  );
}
