import { FilesetResolver, HandLandmarker } from "@mediapipe/tasks-vision";
import { measureLandmarks, medianMeasurements } from "./grip";
import type { Measurements } from "./grip";
export async function createDetector() {
  const vision = await FilesetResolver.forVisionTasks(
    "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm",
  );
  return HandLandmarker.createFromOptions(vision, {
    baseOptions: {
      modelAssetPath:
        "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task",
      delegate: "CPU",
    },
    runningMode: "VIDEO",
    numHands: 1,
    minHandDetectionConfidence: 0.65,
    minHandPresenceConfidence: 0.65,
  });
}
export async function scanVideo(
  video: HTMLVideoElement,
  palmWidth: number,
  onProgress: (n: number) => void,
  signal: AbortSignal,
  live: boolean,
) {
  if (!live) video.pause();
  const detector = await createDetector();
  const samples: { measurements: Measurements; hand: string }[] = [];
  const total = live
    ? 32
    : Math.min(40, Math.max(8, Math.floor(video.duration * 5)));
  const sleep = (ms: number) =>
    new Promise((resolve) => setTimeout(resolve, ms));
  try {
    for (let i = 0; i < total; i++) {
      if (signal.aborted) throw new Error("Scan cancelled.");
      if (!live) {
        const time = Math.min(
          video.duration - 0.02,
          ((i + 0.5) / total) * Math.min(video.duration, 12),
        );
        await new Promise<void>((resolve, reject) => {
          const done = () => {
            clearTimeout(timer);
            video.removeEventListener("seeked", done);
            resolve();
          };
          const timer = setTimeout(() => {
            video.removeEventListener("seeked", done);
            reject(
              new Error("Could not read this video. Try an MP4 or WebM file."),
            );
          }, 4000);
          video.addEventListener("seeked", done);
          video.currentTime = time;
        });
      } else await sleep(125);
      if (signal.aborted) throw new Error("Scan cancelled.");
      const result = detector.detectForVideo(video, performance.now());
      if (result.worldLandmarks[0]) {
        // Reject visibly folded fingers: calibration needs an open, relaxed hand.
        const p = result.worldLandmarks[0];
        const distance = (a: number, b: number) =>
          Math.hypot(p[a].x - p[b].x, p[a].y - p[b].y, p[a].z - p[b].z);
        const open = [5, 9, 13, 17].every(
          (base) =>
            distance(base, base + 3) >
            (distance(base, base + 1) +
              distance(base + 1, base + 2) +
              distance(base + 2, base + 3)) *
              0.8,
        );
        if (open)
          try {
            samples.push({
              measurements: measureLandmarks(p, palmWidth),
              hand: result.handedness[0]?.[0]?.categoryName ?? "Right",
            });
          } catch {
            /* Skip poor detections rather than corrupting the median. */
          }
      }
      onProgress(Math.round(((i + 1) / total) * 100));
      await sleep(0);
    }
    const rightCount = samples.filter((s) => s.hand === "Right").length;
    const hand = rightCount >= samples.length / 2 ? "Right" : "Left";
    const consistent = samples.filter((s) => s.hand === hand);
    if (consistent.length < 5)
      throw new Error(
        "Not enough clear frames. Show one open hand, keep it still, and try brighter lighting.",
      );
    return {
      measurements: medianMeasurements(consistent.map((s) => s.measurements)),
      hand,
      frames: consistent.length,
    };
  } finally {
    detector.close();
  }
}
