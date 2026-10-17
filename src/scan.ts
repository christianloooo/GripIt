import { medianMeasurements } from "./grip";
import type { Measurements } from "./grip";
import { assessDetection, stableMeasurements } from "./scanQuality";
import type { Detection, ScanFeedback } from "./scanQuality";

function detectorClient(signal: AbortSignal) {
  // Classic worker: MediaPipe's WASM loader uses importScripts, which module workers reject.
  const worker = new Worker(
    new URL(
      `${import.meta.env.BASE_URL}mediapipe/scan-worker.js`,
      location.origin,
    ),
  );
  let nextId = 0;
  const pending = new Map<
    number,
    {
      resolve: (value: Detection) => void;
      reject: (error: Error) => void;
      timer: ReturnType<typeof setTimeout>;
    }
  >();
  const fail = (error: Error) => {
    for (const entry of pending.values()) {
      clearTimeout(entry.timer);
      entry.reject(error);
    }
    pending.clear();
  };
  worker.onmessage = (event) => {
    const entry = pending.get(event.data.id);
    if (!entry) return;
    pending.delete(event.data.id);
    clearTimeout(entry.timer);
    if (event.data.error) entry.reject(new Error(event.data.error));
    else entry.resolve(event.data.result);
  };
  worker.onerror = () =>
    fail(
      new Error(
        "The hand detector could not start. Reload the page, or try another browser.",
      ),
    );
  const abort = () => {
    fail(new Error("Scan cancelled."));
    worker.terminate();
  };
  signal.addEventListener("abort", abort, { once: true });
  const call = (data: Record<string, unknown>, transfer: Transferable[] = []) =>
    new Promise<Detection>((resolve, reject) => {
      if (signal.aborted) {
        reject(new Error("Scan cancelled."));
        return;
      }
      const id = nextId++;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(
          new Error(
            "Hand detection timed out. Check that the local model files loaded, then try again.",
          ),
        );
      }, 30000);
      pending.set(id, { resolve, reject, timer });
      worker.postMessage({ ...data, id }, transfer);
    });
  return {
    call,
    close: () => {
      signal.removeEventListener("abort", abort);
      abort();
    },
  };
}
export async function scanVideo(
  video: HTMLVideoElement,
  onFeedback: (feedback: ScanFeedback) => void,
  signal: AbortSignal,
  live: boolean,
) {
  if (!live) video.pause();
  const client = detectorClient(signal);
  const rejections: Record<string, number> = {};
  const samples: { measurements: Measurements; hand: string }[] = [];
  const total = live
    ? 60
    : Math.min(60, Math.max(20, Math.floor(video.duration * 6)));
  const sleep = (ms: number) =>
    new Promise((resolve) => setTimeout(resolve, ms));
  try {
    onFeedback({
      progress: 0,
      accepted: 0,
      message: "Loading the hand detector on your device…",
    });
    await client.call({
      type: "init",
      baseUrl: new URL(import.meta.env.BASE_URL, location.href).href,
    });
    let lastTime = -1;
    let frozenFrames = 0;
    for (let i = 0; i < total; i++) {
      if (signal.aborted) throw new Error("Scan cancelled.");
      if (!live) {
        const time = Math.min(
          video.duration - 0.02,
          ((i + 0.5) / total) * Math.min(video.duration, 12),
        );
        if (Math.abs(video.currentTime - time) > 0.001)
          await new Promise<void>((resolve, reject) => {
            const cleanup = () => {
              clearTimeout(timer);
              video.removeEventListener("seeked", done);
              signal.removeEventListener("abort", cancel);
            };
            const done = () => {
              cleanup();
              resolve();
            };
            const cancel = () => {
              cleanup();
              reject(new Error("Scan cancelled."));
            };
            const timer = setTimeout(() => {
              cleanup();
              reject(
                new Error("Could not decode this video. Try MP4 or WebM."),
              );
            }, 4000);
            video.addEventListener("seeked", done, { once: true });
            signal.addEventListener("abort", cancel, { once: true });
            video.currentTime = time;
          });
      } else {
        await sleep(100);
        if (video.currentTime === lastTime) {
          if (++frozenFrames > 30)
            throw new Error(
              "Camera frames stopped. Restart the camera and try again.",
            );
          i--;
          continue;
        }
        frozenFrames = 0;
        lastTime = video.currentTime;
      }
      if (signal.aborted) throw new Error("Scan cancelled.");
      const bitmap = await createImageBitmap(video);
      const result = await client.call(
        { type: "frame", bitmap, timestamp: performance.now() },
        [bitmap],
      );
      const assessment = assessDetection(result);
      if (assessment.measurements && assessment.hand)
        samples.push({
          measurements: assessment.measurements,
          hand: assessment.hand,
        });
      if (!assessment.measurements)
        rejections[assessment.message] =
          (rejections[assessment.message] ?? 0) + 1;
      onFeedback({
        progress: Math.round(((i + 1) / total) * 100),
        accepted: samples.length,
        message: assessment.message,
        landmarks: assessment.landmarks,
        hand: assessment.hand,
        ball: result.ball,
      });
      if (
        live &&
        samples.length >= 25 &&
        stableMeasurements(samples.slice(-20).map((s) => s.measurements))
      )
        break;
    }
    const rightCount = samples.filter((s) => s.hand === "Right").length;
    const hand = rightCount >= samples.length / 2 ? "Right" : "Left";
    const consistent = samples
      .filter((s) => s.hand === hand)
      .map((s) => s.measurements);
    if (consistent.length < 8)
      throw new Error(
        `Only ${consistent.length} usable frames. Show one open hand and a complete baseball side by side, against a dark background.`,
      );
    if (!stableMeasurements(consistent))
      throw new Error(
        "The measurements changed too much during the scan. Hold your palm still and face the camera.",
      );
    return {
      measurements: medianMeasurements(consistent),
      hand,
      frames: consistent.length,
    };
  } catch (error) {
    throw new Error(error instanceof Error ? error.message : "Scan failed", {
      cause: { acceptedFrames: samples.length, rejections },
    });
  } finally {
    client.close();
  }
}
