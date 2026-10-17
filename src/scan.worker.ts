/// <reference lib="webworker" />
import { FilesetResolver, HandLandmarker } from "@mediapipe/tasks-vision";
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
      bitmap.close();
      self.postMessage({ id, result });
    }
  } catch (error) {
    bitmap?.close();
    self.postMessage({
      id,
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
