import { Component, Suspense, useEffect, useMemo, useRef } from "react";
import type { ReactNode } from "react";
import { Canvas } from "@react-three/fiber";
import {
  ContactShadows,
  Html,
  Line,
  OrbitControls,
  PerspectiveCamera,
} from "@react-three/drei";
import * as THREE from "three";
import { BALL_RADIUS, handScale, seamPoint, solveGrip } from "./grip";
import { createHandSurface } from "./handSurface";
import type { FingerRig, Measurements, Pitch } from "./grip";

const SKIN = "#cc9c81";
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
  useEffect(() => () => geometry.dispose(), [geometry]);
  return (
    <group>
      <mesh geometry={geometry} castShadow receiveShadow>
        <meshPhysicalMaterial
          color={SKIN}
          roughness={0.66}
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
function Baseball({ ball }: { ball: ReturnType<typeof solveGrip>["ball"] }) {
  const { seam, stitches } = useMemo(
    () => ({
      seam: Array.from({ length: 361 }, (_, i) =>
        seamPoint((i / 360) * Math.PI * 2, 0, BALL_RADIUS + 0.22),
      ),
      stitches: Array.from({ length: 108 }, (_, i) => {
        const t = (i / 108) * Math.PI * 2;
        return [
          seamPoint(t - 0.018, -0.035, BALL_RADIUS + 0.3),
          seamPoint(t + 0.018, 0.035, BALL_RADIUS + 0.3),
        ];
      }),
    }),
    [],
  );
  return (
    <group position={ball.position} rotation={ball.rotation}>
      <mesh castShadow receiveShadow>
        <sphereGeometry args={[BALL_RADIUS, 80, 64]} />
        <meshStandardMaterial color="#f2eee3" roughness={0.88} />
      </mesh>
      <Line points={seam} color="#a9463e" lineWidth={1.1} />
      {stitches.map((points, i) => (
        <Line key={i} points={points} color="#af413a" lineWidth={1.7} />
      ))}
    </group>
  );
}
function Contact({
  rig,
  text,
  number,
}: {
  rig: FingerRig;
  text: string;
  number: number;
}) {
  const end = rig.points[3];
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
        <HandSkin rigs={rigs} measurements={measurements} />
        {annotations &&
          [rigs[0], rigs[1], rigs[4]].map((rig, i) => (
            <Contact
              key={rig.name}
              rig={rig}
              number={i + 1}
              text={pitch.cues[i]}
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
