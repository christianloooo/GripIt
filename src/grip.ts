import { Euler, Vector3 } from "three";

export const FINGERS = ["index", "middle", "ring", "pinky", "thumb"] as const;
export type Finger = (typeof FINGERS)[number];
export type Measurements = {
  palmWidth: number;
  palmLength?: number;
  radii?: Partial<Record<Finger, number>>;
  segments: Record<Finger, [number, number, number]>;
};
export const DEFAULT_MEASUREMENTS: Measurements = {
  palmWidth: 82,
  segments: {
    index: [38, 24, 18],
    middle: [42, 27, 20],
    ring: [39, 25, 18],
    pinky: [30, 19, 16],
    thumb: [30, 24, 20],
  },
};
export const PITCHES = [
  {
    id: "four-seam",
    name: "Four-seam fastball",
    short: "4S",
    family: "FASTBALL",
    subtitle: "Your foundation. Find the seams.",
    description:
      "Set your index and middle fingers across the horseshoe seam. Let your thumb support the ball underneath.",
    cues: [
      "Index across the seam",
      "Middle finger beside the index",
      "Thumb supports from below",
    ],
    spread: 0.23,
    seam: 0,
  },
  {
    id: "two-seam",
    name: "Two-seam fastball",
    short: "2S",
    family: "FASTBALL",
    subtitle: "A different seam. A new feel.",
    description:
      "Place your index and middle fingers along the narrow seams, with your thumb underneath the ball.",
    cues: [
      "Index along the narrow seam",
      "Middle along the opposite seam",
      "Keep the thumb underneath",
    ],
    spread: 0.18,
    seam: Math.PI / 2,
  },
  {
    id: "slider",
    name: "Slider",
    short: "SL",
    family: "BREAKING BALL",
    subtitle: "Find a different seam angle.",
    description:
      "Explore the outer seam with your middle finger. Keep the index nearby and the thumb on the lower side.",
    cues: [
      "Index rests beside the middle",
      "Middle follows the outer seam",
      "Thumb on the lower side",
    ],
    spread: 0.14,
    seam: 0.6,
  },
  {
    id: "changeup",
    name: "Changeup",
    short: "CH",
    family: "OFF-SPEED",
    subtitle: "More fingers. A different feel.",
    description:
      "Wrap your middle and ring fingers around the ball. Let the index rest lightly and keep the thumb underneath.",
    cues: [
      "Index rests lightly",
      "Middle wraps over the ball",
      "Thumb cradles the lower side",
    ],
    spread: 0.32,
    seam: -0.4,
  },
] as const;
export type Pitch = (typeof PITCHES)[number];
export const BALL_RADIUS = 36.5;
export const BALL_CENTER = new Vector3(0, 24, 24);
export type FingerRig = {
  name: Finger;
  root: Vector3;
  yaw: number;
  lengths: number[];
  radius: number;
  angles: number[];
  points: Vector3[];
  target: Vector3;
  error: number;
  clearance: number;
};

export function forward(
  root: Vector3,
  yaw: number,
  lengths: number[],
  angles: number[],
) {
  const points = [root.clone()];
  let bend = 0;
  for (let i = 0; i < lengths.length; i++) {
    bend += angles[i];
    const delta = new Vector3(
      -Math.sin(yaw) * Math.cos(bend),
      Math.cos(yaw) * Math.cos(bend),
      Math.sin(bend),
    ).multiplyScalar(lengths[i]);
    points.push(points[i].clone().add(delta));
  }
  return points;
}
export type BallPose = {
  position: Vector3;
  rotation: [number, number, number];
};
export type GripSolution = {
  fingers: FingerRig[];
  ball: BallPose;
  objective: {
    position: number;
    joint: number;
    collision: number;
    total: number;
  };
};
export const OBJECTIVE_WEIGHTS = { position: 1, joint: 6, collision: 80 };
export const JOINT_NEUTRAL = [0.12, 0.65, 0.6];
export const JOINT_MIN = [-0.35, 0, 0];
export const JOINT_MAX = [1.5, 1.85, 1.85];
export function handScale(left: boolean) {
  return left ? -1 : 1;
}
export function fingerRadius(name: Finger, m: Measurements) {
  return (
    m.radii?.[name] ??
    ((name === "thumb"
      ? 8
      : name === "pinky"
        ? 5.5
        : name === "middle"
          ? 7.1
          : 6.6) *
      m.palmWidth) /
      82
  );
}
// Shared by the rendered stitching and optimization targets. Points lie on the sphere.
export function seamPoint(t: number, offset = 0, radius = BALL_RADIUS) {
  const latitude = 0.52 * Math.cos(2 * t) + offset;
  return new Vector3(
    Math.cos(latitude) * Math.cos(t),
    Math.sin(latitude),
    Math.cos(latitude) * Math.sin(t),
  ).multiplyScalar(radius);
}
export function worldSeamPoint(
  t: number,
  ball: BallPose,
  radius = BALL_RADIUS,
) {
  return seamPoint(t, 0, radius)
    .applyEuler(new Euler(...ball.rotation))
    .add(ball.position);
}
export function clearance(
  points: Vector3[],
  radius: number,
  center = BALL_CENTER,
) {
  let min = Infinity;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1],
      d = points[i].clone().sub(a);
    const t = Math.max(
      0,
      Math.min(1, center.clone().sub(a).dot(d) / Math.max(1e-12, d.lengthSq())),
    );
    min = Math.min(
      min,
      a.clone().addScaledVector(d, t).distanceTo(center) - BALL_RADIUS - radius,
    );
  }
  return min;
}
// Exact distance between finite line segments, including parallel/degenerate cases.
export function segmentDistance(
  a: Vector3,
  b: Vector3,
  c: Vector3,
  d: Vector3,
) {
  const u = b.clone().sub(a),
    v = d.clone().sub(c),
    w = a.clone().sub(c);
  const aa = u.dot(u),
    bb = u.dot(v),
    cc = v.dot(v),
    dd = u.dot(w),
    ee = v.dot(w);
  if (aa < 1e-12 && cc < 1e-12) return a.distanceTo(c);
  if (aa < 1e-12)
    return a.distanceTo(
      c.clone().addScaledVector(v, Math.max(0, Math.min(1, ee / cc))),
    );
  let t =
    cc < 1e-12
      ? 0
      : Math.max(
          0,
          Math.min(1, (aa * ee - bb * dd) / Math.max(1e-12, aa * cc - bb * bb)),
        );
  let s = Math.max(0, Math.min(1, (bb * t - dd) / aa));
  t = cc < 1e-12 ? 0 : Math.max(0, Math.min(1, (bb * s + ee) / cc));
  s = Math.max(0, Math.min(1, (bb * t - dd) / aa));
  return a
    .clone()
    .addScaledVector(u, s)
    .distanceTo(c.clone().addScaledVector(v, t));
}
function baseRig(name: Finger, m: Measurements): FingerRig {
  // Right hand: palm faces +Z, fingertips +Y, thumb on +X.
  const bases = {
    index: 0.29,
    middle: 0.075,
    ring: -0.15,
    pinky: -0.34,
    thumb: 0.49,
  };
  const palmScale = (m.palmLength ?? 72) / 72;
  return {
    name,
    root: new Vector3(
      m.palmWidth * bases[name],
      (name === "thumb" ? -28 : name === "pinky" ? -8 : 0) * palmScale,
      -24,
    ),
    yaw: name === "thumb" ? 1.05 : 0,
    lengths: m.segments[name],
    radius: fingerRadius(name, m),
    angles: [...JOINT_NEUTRAL],
    points: [],
    target: new Vector3(),
    error: 0,
    clearance: 0,
  };
}
function targetsFor(m: Measurements, pitch: Pitch, ball: BallPose) {
  return FINGERS.map((name) => {
    const rig = baseRig(name, m),
      r = BALL_RADIUS + rig.radius;
    const x = rig.root.x - ball.position.x;
    const region =
      name === "index"
        ? -0.5 + pitch.spread - 0.23
        : name === "middle"
          ? pitch.id === "changeup"
            ? -0.6
            : -0.35
          : name === "ring"
            ? pitch.id === "changeup"
              ? -0.5
              : -0.75
            : -1.1;
    const ideal =
      name === "thumb"
        ? new Vector3(0.5, -0.78, 0.33)
            .normalize()
            .multiplyScalar(r)
            .add(ball.position)
        : new Vector3(
            rig.root.x,
            ball.position.y +
              Math.sqrt(Math.max(1, r * r - x * x)) * Math.cos(region),
            ball.position.z +
              Math.sqrt(Math.max(1, r * r - x * x)) * Math.sin(region),
          );
    // Index/middle contact the SAME curve that is drawn, choosing a reachable seam region.
    if (name !== "index" && name !== "middle") return ideal;
    let best = ideal,
      score = Infinity;
    for (let i = 0; i < 240; i++) {
      const candidate = worldSeamPoint((i / 240) * Math.PI * 2, ball, r);
      const value = candidate.distanceToSquared(ideal);
      if (value < score) {
        score = value;
        best = candidate;
      }
    }
    return best;
  });
}
export function jointEnergy(angles: number[]) {
  return angles.reduce(
    (sum, a, j) =>
      sum + ((a - JOINT_NEUTRAL[j]) / (JOINT_MAX[j] - JOINT_MIN[j])) ** 2,
    0,
  );
}
function updateRig(rig: FingerRig, center: Vector3) {
  rig.points = forward(rig.root, rig.yaw, rig.lengths, rig.angles);
  rig.error = rig.points[3].distanceTo(rig.target);
  rig.clearance = clearance(rig.points, rig.radius, center);
}
function collisionEnergy(
  rig: FingerRig,
  others: FingerRig[],
  ball: BallPose,
  pairWeight = 0.5,
) {
  let energy = 0;
  for (let j = 0; j < 3; j++) {
    const a = rig.points[j],
      b = rig.points[j + 1],
      delta = b.clone().sub(a);
    const t = Math.max(
      0,
      Math.min(1, ball.position.clone().sub(a).dot(delta) / delta.lengthSq()),
    );
    energy +=
      Math.max(
        0,
        BALL_RADIUS +
          rig.radius -
          a.clone().addScaledVector(delta, t).distanceTo(ball.position),
      ) ** 2;
    // Adjacent finger bases merge into the palm; test the exposed distal chains.
    for (const other of others)
      if (other !== rig)
        for (let k = 0; k < 3; k++) {
          if (j === 0 && k === 0) continue;
          energy +=
            pairWeight *
            Math.max(
              0,
              rig.radius +
                other.radius -
                segmentDistance(a, b, other.points[k], other.points[k + 1]),
            ) **
              2;
        }
  }
  return energy;
}
function optimizeFinger(
  rig: FingerRig,
  others: FingerRig[],
  ball: BallPose,
  multiStart: boolean,
) {
  const evaluate = () => {
    updateRig(rig, ball.position);
    return (
      rig.error ** 2 * OBJECTIVE_WEIGHTS.position +
      (jointEnergy(rig.angles) +
        ((rig.yaw - (rig.name === "thumb" ? 1.05 : 0)) / 0.8) ** 2) *
        OBJECTIVE_WEIGHTS.joint +
      collisionEnergy(rig, others, ball, 1) * OBJECTIVE_WEIGHTS.collision
    );
  };
  let best = [...rig.angles],
    bestYaw = rig.yaw,
    bestCost = Infinity;
  const nominalYaw = rig.name === "thumb" ? 1.05 : 0;
  const seeds = multiStart
    ? [
        [0, 0.8, 1],
        [0.35, 0.5, 1.2],
        [-0.2, 1.4, 0.5],
        [1.2, 0.2, 0.3],
        rig.angles,
      ]
    : [rig.angles];
  for (const seed of seeds) {
    rig.angles = [...seed];
    rig.yaw = nominalYaw;
    for (const step of [0.25, 0.09, 0.03, 0.01])
      for (let loop = 0; loop < 14; loop++) {
        let changed = false;
        for (let j = 0; j < 4; j++) {
          const original = j === 3 ? rig.yaw : rig.angles[j];
          let value = original,
            cost = evaluate();
          for (const sign of [-1, 1]) {
            const trial = Math.max(
              j === 3 ? nominalYaw - 0.4 : JOINT_MIN[j],
              Math.min(
                j === 3 ? nominalYaw + 0.4 : JOINT_MAX[j],
                original + sign * step,
              ),
            );
            if (j === 3) rig.yaw = trial;
            else rig.angles[j] = trial;
            const c = evaluate();
            if (c < cost) {
              cost = c;
              value = trial;
              changed = true;
            }
          }
          if (j === 3) rig.yaw = value;
          else rig.angles[j] = value;
        }
        if (!changed) break;
      }
    const cost = evaluate();
    if (cost < bestCost) {
      bestCost = cost;
      best = [...rig.angles];
      bestYaw = rig.yaw;
    }
  }
  rig.angles = best;
  rig.yaw = bestYaw;
  updateRig(rig, ball.position);
}
export function gripObjective(fingers: FingerRig[], ball: BallPose) {
  const position = fingers.reduce((sum, r) => sum + r.error ** 2, 0);
  const joint = fingers.reduce(
    (sum, r) =>
      sum +
      jointEnergy(r.angles) +
      ((r.yaw - (r.name === "thumb" ? 1.05 : 0)) / 0.8) ** 2,
    0,
  );
  const collision = fingers.reduce(
    (sum, r) => sum + collisionEnergy(r, fingers, ball),
    0,
  );
  return {
    position,
    joint,
    collision,
    total:
      position * OBJECTIVE_WEIGHTS.position +
      joint * OBJECTIVE_WEIGHTS.joint +
      collision * OBJECTIVE_WEIGHTS.collision,
  };
}
const solutionCache = new Map<string, GripSolution>();
export function solveGrip(m: Measurements, pitch: Pitch): GripSolution {
  const key = JSON.stringify([m, pitch.id]);
  const cached = solutionCache.get(key);
  if (cached) return cached;
  const ball: BallPose = {
    position: BALL_CENTER.clone(),
    rotation: [1.6, pitch.seam, -0.2],
  };
  const fingers = FINGERS.map((f) => baseRig(f, m));
  const assignTargets = () => {
    const targets = targetsFor(m, pitch, ball);
    fingers.forEach((r, i) => {
      r.target = targets[i];
      updateRig(r, ball.position);
    });
  };
  assignTargets();
  // Bounded block coordinate descent over theta AND ball translation/orientation.
  // Each ball trial recomputes seam-attached targets, preserving renderer/solver agreement.
  fingers.forEach((r) => optimizeFinger(r, [], ball, true));
  for (let pass = 0; pass < 3; pass++) {
    fingers.forEach((r) => optimizeFinger(r, fingers, ball, false));
    for (let axis = 0; axis < 6; axis++) {
      let best = gripObjective(fingers, ball).total;
      const original =
        axis < 3 ? ball.position.getComponent(axis) : ball.rotation[axis - 3];
      let value = original;
      const step = axis < 3 ? 2 / (pass + 1) : 0.1 / (pass + 1);
      for (const sign of [-1, 1]) {
        const lo =
          axis < 3
            ? BALL_CENTER.getComponent(axis) - 10
            : [1.1, pitch.seam - 0.5, -0.6][axis - 3];
        const hi =
          axis < 3
            ? BALL_CENTER.getComponent(axis) + 10
            : [2.1, pitch.seam + 0.5, 0.2][axis - 3];
        const trial = Math.max(lo, Math.min(hi, original + sign * step));
        if (axis < 3) ball.position.setComponent(axis, trial);
        else ball.rotation[axis - 3] = trial;
        assignTargets();
        const score = gripObjective(fingers, ball).total;
        if (score < best) {
          best = score;
          value = trial;
        }
      }
      if (axis < 3) ball.position.setComponent(axis, value);
      else ball.rotation[axis - 3] = value;
      assignTargets();
    }
  }
  fingers.forEach((r) => optimizeFinger(r, fingers, ball, false));
  const solution = { fingers, ball, objective: gripObjective(fingers, ball) };
  if (solutionCache.size > 40) solutionCache.clear();
  solutionCache.set(key, solution);
  return solution;
}
export function solveFinger(
  name: Finger,
  m: Measurements,
  pitch: Pitch,
): FingerRig {
  return solveGrip(m, pitch).fingers.find((r) => r.name === name)!;
}
export type Landmark = { x: number; y: number; z: number };
export const LANDMARK_CHAINS: Record<Finger, number[]> = {
  thumb: [1, 2, 3, 4],
  index: [5, 6, 7, 8],
  middle: [9, 10, 11, 12],
  ring: [13, 14, 15, 16],
  pinky: [17, 18, 19, 20],
};
export function measureLandmarks(
  points: Landmark[],
  palmWidth: number,
  middleLength?: number,
): Measurements {
  if (
    points.length !== 21 ||
    points.some((p) => ![p.x, p.y, p.z].every(Number.isFinite))
  )
    throw new Error("Expected 21 valid hand landmarks.");
  const dist = (a: number, b: number) =>
    Math.hypot(
      points[a].x - points[b].x,
      points[a].y - points[b].y,
      points[a].z - points[b].z,
    );
  const detectedWidth = dist(5, 17);
  if (
    detectedWidth < 0.005 ||
    !Number.isFinite(palmWidth) ||
    palmWidth < 55 ||
    palmWidth > 115
  )
    throw new Error(
      "Use a palm width between 55 and 115 mm and show an open hand.",
    );
  const detectedMiddle = dist(9, 10) + dist(10, 11) + dist(11, 12);
  if (
    middleLength !== undefined &&
    (!Number.isFinite(middleLength) ||
      middleLength < 45 ||
      middleLength > 120 ||
      detectedMiddle < 0.005)
  )
    throw new Error(
      "Enter a measured middle finger length between 45 and 120 mm.",
    );
  // A measured long finger is a more stable scale anchor than a short/foreshortened palm span.
  const scale =
    middleLength === undefined
      ? palmWidth / detectedWidth
      : middleLength / detectedMiddle;
  const segments = {} as Measurements["segments"];
  for (const name of FINGERS) {
    const chain = LANDMARK_CHAINS[name];
    segments[name] = [0, 1, 2].map(
      (i) => dist(chain[i], chain[i + 1]) * scale,
    ) as [number, number, number];
    if (segments[name].some((n) => n < 7 || n > 65))
      throw new Error(
        `${name} segments (${segments[name].map((n) => n.toFixed(0)).join(" / ")} mm) look unreliable. Check the palm width and show a straight-on open hand.`,
      );
  }
  const palmLength = dist(0, 9) * scale;
  return {
    palmWidth,
    segments,
    palmLength: Math.max(50, Math.min(110, palmLength)),
    radii: Object.fromEntries(
      FINGERS.map((f) => [f, fingerRadius(f, { palmWidth, segments })]),
    ),
  };
}
export function medianMeasurements(samples: Measurements[]): Measurements {
  if (!samples.length)
    throw new Error(
      "No usable open-hand frames found. Try again with the whole hand visible.",
    );
  const median = (values: number[]) =>
    values.sort((a, b) => a - b)[Math.floor(values.length / 2)];
  return {
    palmWidth: samples[0].palmWidth,
    palmLength: median(samples.map((s) => s.palmLength ?? 72)),
    radii: samples[0].radii,
    segments: Object.fromEntries(
      FINGERS.map((f) => [
        f,
        [0, 1, 2].map((i) => median(samples.map((s) => s.segments[f][i]))),
      ]),
    ) as Measurements["segments"],
  };
}
