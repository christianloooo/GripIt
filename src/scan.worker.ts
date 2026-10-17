/// <reference lib="webworker" />
import { FilesetResolver, HandLandmarker } from "@mediapipe/tasks-vision";
import { detectBaseball } from "./ballReference";
let detector: HandLandmarker | null = null;
self.onmessage = async (event: MessageEvent) => {
  const { type, id, bitmap, baseUrl } = event.data;
  try {
    if (type === "init") {
      const files = await FilesetResolver.forVisionTasks(
        `${baseUrl}mediapipe/wasm`,
      );
      detector = await HandLandmarker.createFromOptions(files, {
        baseOptions: {
          modelAssetPath: `${baseUrl}mediapipe/hand_landmarker.task`,
          delegate: "CPU",
        },
        runningMode: "VIDEO",
        numHands: 2,
        minHandDetectionConfidence: 0.55,
        minHandPresenceConfidence: 0.55,
        minTrackingConfidence: 0.55,
      });
      self.postMessage({ id, ready: true });
    } else if (type === "frame") {
      if (!detector) throw new Error("The hand detector has not loaded.");
      const result = detector.detectForVideo(bitmap, event.data.timestamp);
      const width = Math.min(480, bitmap.width),
        height = Math.round((bitmap.height * width) / bitmap.width);
      const canvas = new OffscreenCanvas(width, height),
        context = canvas.getContext("2d", { willReadFrequently: true })!;
      context.drawImage(bitmap, 0, 0, width, height);
      const ball = detectBaseball(
        context.getImageData(0, 0, width, height).data,
        width,
        height,
        result.landmarks[0] ?? [],
      );
      bitmap.close();
      self.postMessage({ id, result: { ...result, ball } });
    }
  } catch (error) {
    bitmap?.close();
    self.postMessage({
      id,
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
