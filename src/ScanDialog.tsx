import { useEffect, useRef, useState } from "react";
import { Camera, Check, LoaderCircle, Upload, X, Hand } from "lucide-react";
import { recordFailure } from "./failureLog";
import { scanVideo } from "./scan";
import { FINGERS, LANDMARK_CHAINS } from "./grip";
import type { Measurements } from "./grip";
import type { ScanFeedback } from "./scanQuality";
export function ScanDialog({
  onClose,
  onComplete,
}: {
  onClose: () => void;
  onComplete: (
    m: Measurements,
    left: boolean,
    signal: AbortSignal,
  ) => Promise<void>;
}) {
  const [mode, setMode] = useState<"idle" | "camera" | "file">("idle");
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState<ScanFeedback>({
    progress: 0,
    accepted: 0,
    message: "",
  });
  const [selectedHand, setSelectedHand] = useState("Right");
  const [cameraLoading, setCameraLoading] = useState(false);
  const [mirrorPreview, setMirrorPreview] = useState(true);
  const [mirroredFile, setMirroredFile] = useState(false);
  const overlay = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = overlay.current,
      v = video.current;
    if (!canvas || !v) return;
    const context = canvas.getContext("2d");
    if (!context) return;
    canvas.width = canvas.clientWidth * 2;
    canvas.height = canvas.clientHeight * 2;
    context.clearRect(0, 0, canvas.width, canvas.height);
    if (feedback.ball) {
      const b = feedback.ball;
      context.strokeStyle = "#d8ff72";
      context.lineWidth = 3;
      context.beginPath();
      context.arc(
        oxForBall(canvas, v) +
          b.x *
            v.videoWidth *
            Math.min(
              canvas.width / v.videoWidth,
              canvas.height / v.videoHeight,
            ),
        oyForBall(canvas, v) +
          b.y *
            v.videoHeight *
            Math.min(
              canvas.width / v.videoWidth,
              canvas.height / v.videoHeight,
            ),
        b.radius *
          v.videoWidth *
          Math.min(canvas.width / v.videoWidth, canvas.height / v.videoHeight),
        0,
        Math.PI * 2,
      );
      context.stroke();
    }
    if (!feedback.landmarks) return;
    const fit = Math.min(
      canvas.width / v.videoWidth,
      canvas.height / v.videoHeight,
    );
    const width = v.videoWidth * fit,
      height = v.videoHeight * fit;
    const ox = (canvas.width - width) / 2,
      oy = (canvas.height - height) / 2;
    const point = (i: number) => [
      ox + feedback.landmarks![i].x * width,
      oy + feedback.landmarks![i].y * height,
    ];
    context.strokeStyle = feedback.hand ? "#d8ff72" : "#f6bc79";
    context.lineWidth = 3;
    for (const chain of Object.values(LANDMARK_CHAINS)) {
      context.beginPath();
      const start = point(0);
      context.moveTo(start[0], start[1]);
      for (const index of chain) {
        const p = point(index);
        context.lineTo(p[0], p[1]);
      }
      context.stroke();
    }
    for (let i = 0; i < 21; i++) {
      const p = point(i);
      context.beginPath();
      context.arc(p[0], p[1], 4, 0, Math.PI * 2);
      context.fillStyle = "#f7ffe9";
      context.fill();
    }
  }, [feedback]);
  const [error, setError] = useState("");
  const [result, setResult] = useState<Awaited<
    ReturnType<typeof scanVideo>
  > | null>(null);
  const video = useRef<HTMLVideoElement>(null),
    stream = useRef<MediaStream | null>(null),
    url = useRef("");
  const controller = useRef(new AbortController());
  const dialog = useRef<HTMLDialogElement>(null);
  const cameraPending = useRef(false);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => {
      controller.current.abort();
      stream.current?.getTracks().forEach((t) => t.stop());
      if (url.current) URL.revokeObjectURL(url.current);
      element?.close();
    };
  }, []);
  const camera = async () => {
    if (cameraPending.current) return;
    cameraPending.current = true;
    setCameraLoading(true);
    setFeedback({ progress: 0, accepted: 0, message: "" });
    setError("");
    try {
      if (!navigator.mediaDevices?.getUserMedia)
        throw new Error(
          "Camera access needs localhost or HTTPS. You can upload a video instead.",
        );
      const media = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: "environment" },
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
        audio: false,
      });
      if (controller.current.signal.aborted) {
        media.getTracks().forEach((t) => t.stop());
        return;
      }
      stream.current?.getTracks().forEach((t) => t.stop());
      stream.current = media;
      setMirrorPreview(
        media.getVideoTracks()[0]?.getSettings().facingMode !== "environment",
      );
      setResult(null);
      if (video.current) {
        video.current.srcObject = media;
        await video.current.play();
      }
      setMode("camera");
    } catch (e) {
      recordFailure("scan", e, { source: "camera" });
      setError(
        e instanceof Error
          ? e.message
          : "Camera access failed. Try uploading a video.",
      );
    } finally {
      cameraPending.current = false;
      if (!controller.current.signal.aborted) setCameraLoading(false);
    }
  };
  const upload = (file?: File) => {
    if (!file) return;
    setError("");
    setResult(null);
    setFeedback({ progress: 0, accepted: 0, message: "" });
    stream.current?.getTracks().forEach((t) => t.stop());
    stream.current = null;
    if (url.current) URL.revokeObjectURL(url.current);
    url.current = URL.createObjectURL(file);
    if (video.current) {
      video.current.srcObject = null;
      video.current.src = url.current;
      video.current.load();
    }
    setMode("file");
  };
  const analyze = async () => {
    if (!video.current) return;
    setBusy(true);
    setError("");
    setFeedback({ progress: 0, accepted: 0, message: "Preparing scan…" });
    try {
      if (
        video.current.readyState < 2 ||
        (mode === "file" &&
          (!Number.isFinite(video.current.duration) ||
            video.current.duration < 0.3))
      )
        throw new Error(
          "Wait for the video to load, or choose a supported MP4 / WebM file.",
        );
      const output = await scanVideo(
        video.current,
        setFeedback,
        controller.current.signal,
        mode === "camera",
      );
      if (controller.current.signal.aborted) return;
      setResult(output);
      setSelectedHand(
        mode === "file" && mirroredFile
          ? output.hand === "Left"
            ? "Right"
            : "Left"
          : output.hand,
      );
      stream.current?.getTracks().forEach((t) => t.stop());
      stream.current = null;
    } catch (e) {
      if (!controller.current.signal.aborted) {
        recordFailure("scan", e, {
          source: mode,
          diagnostics: e instanceof Error ? e.cause : undefined,
        });
        setError(
          e instanceof Error ? e.message : "Scan failed. Please try again.",
        );
      }
    } finally {
      if (!controller.current.signal.aborted) setBusy(false);
    }
  };
  return (
    <dialog
      ref={dialog}
      className="scan-dialog"
      onCancel={onClose}
      aria-labelledby="scan-title"
    >
      <button
        className="dialog-close icon-button"
        onClick={onClose}
        aria-label="Close hand scan"
      >
        <X size={20} />
      </button>
      <div className="eyebrow">MAKE IT YOURS</div>
      <h2 id="scan-title">Every hand has a story.</h2>
      <p>
        Show your open hand with a regulation baseball beside it. The ball sets
        the scale automatically.
      </p>
      <div
        className={`scan-preview ${mode === "camera" && mirrorPreview ? "camera-preview" : ""}`}
      >
        <video
          ref={video}
          muted
          playsInline
          controls={mode === "file" && !busy}
          onError={() =>
            setError(
              "This video could not be decoded. Try an MP4 or WebM file.",
            )
          }
        />
        <canvas ref={overlay} className="scan-landmarks" aria-hidden="true" />
        {mode !== "idle" && !result && (
          <div className="hand-guide" aria-hidden="true" />
        )}
        {mode === "idle" && (
          <div className="preview-placeholder">
            <Hand size={54} strokeWidth={1} />
            <span>Your open hand + a baseball, side by side.</span>
          </div>
        )}
        {busy && !result && (
          <div className="scan-progress">
            <LoaderCircle className="spin" />
            {feedback.progress === 0
              ? "Loading detector…"
              : `${feedback.accepted} clear frames · ${feedback.progress}%`}
          </div>
        )}
      </div>
      {busy && !result && (
        <p className="scan-feedback" role="status">
          {feedback.message}
        </p>
      )}
      {!result ? (
        <>
          <div className="scan-actions">
            <button
              className="secondary"
              onClick={camera}
              disabled={busy || cameraLoading}
            >
              <Camera size={16} />
              {cameraLoading ? "Opening camera…" : "Use camera"}
            </button>
            <label
              className={`secondary file-button ${busy || cameraLoading ? "disabled" : ""}`}
            >
              <Upload size={16} />
              Upload video
              <input
                type="file"
                accept="video/*"
                disabled={busy || cameraLoading}
                onChange={(e) => upload(e.target.files?.[0])}
              />
            </label>
          </div>
          {mode === "file" && (
            <label className="mirror-option">
              <input
                type="checkbox"
                checked={mirroredFile}
                disabled={busy}
                onChange={(e) => setMirroredFile(e.target.checked)}
              />
              This video was recorded with a mirror filter
            </label>
          )}
          <div className="reference-instructions">
            <strong>No ruler. No measurements to enter.</strong>
            <p>
              Place a regulation baseball (73 mm diameter) beside your open palm
              on a dark background. Keep the whole ball visible and your palm at
              the same distance from the camera. Keep both still and face the
              camera straight on.
            </p>
          </div>
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <button
            className="primary wide"
            disabled={mode === "idle" || busy || cameraLoading}
            onClick={analyze}
          >
            {busy
              ? "Scanning…"
              : mode === "camera"
                ? "Start guided scan"
                : "Analyze video"}
          </button>
        </>
      ) : (
        <div className="scan-success">
          <Check size={28} />
          <h3>Your proportions are ready.</h3>
          <p>
            {result.frames} stable frames · {selectedHand.toLowerCase()} hand ·{" "}
            {result.measurements.palmWidth.toFixed(0)} mm estimated palm
          </p>
          <div className="hand-review">
            <span>Confirm your throwing hand</span>
            <div>
              {["Right", "Left"].map((hand) => (
                <button
                  key={hand}
                  className={selectedHand === hand ? "active" : ""}
                  aria-pressed={selectedHand === hand}
                  onClick={() => setSelectedHand(hand)}
                >
                  {hand}
                </button>
              ))}
            </div>
          </div>
          <dl className="measurement-review">
            {FINGERS.map((f) => (
              <div key={f}>
                <dt>{f}</dt>
                <dd>
                  {result.measurements.segments[f]
                    .reduce((a, b) => a + b, 0)
                    .toFixed(0)}{" "}
                  mm
                </dd>
              </div>
            ))}
          </dl>
          <p className="small">
            Estimated from the baseball reference. Perspective and landmark
            detection can affect these measurements. Rescan if they look wrong.
          </p>
          <button
            className="secondary wide"
            onClick={() => {
              setResult(null);
              setMode("idle");
              setFeedback({ progress: 0, accepted: 0, message: "" });
            }}
          >
            Try another scan
          </button>
          {error && (
            <p className="error" role="alert">
              {error} Your previous hand is unchanged. Details are saved in the
              failure log.
            </p>
          )}
          <button
            className="primary wide"
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              setError("");
              try {
                await onComplete(
                  result.measurements,
                  selectedHand === "Left",
                  controller.current.signal,
                );
              } catch (e) {
                setError(
                  e instanceof Error ? e.message : "Model validation failed.",
                );
              } finally {
                setBusy(false);
              }
            }}
          >
            {busy ? "Checking all grip models…" : "Use my hand"}
          </button>
        </div>
      )}
      <p className="privacy">
        Video is processed in your browser and is never uploaded. First use
        loads the bundled MediaPipe model. Landmark proportions are approximate;
        skin shape and finger thickness are modeled.
      </p>
    </dialog>
  );
}

function oxForBall(c: HTMLCanvasElement, v: HTMLVideoElement) {
  const s = Math.min(c.width / v.videoWidth, c.height / v.videoHeight);
  return (c.width - v.videoWidth * s) / 2;
}
function oyForBall(c: HTMLCanvasElement, v: HTMLVideoElement) {
  const s = Math.min(c.width / v.videoWidth, c.height / v.videoHeight);
  return (c.height - v.videoHeight * s) / 2;
}
