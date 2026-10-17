import { useEffect, useRef, useState } from "react";
import { Camera, Check, LoaderCircle, Upload, X } from "lucide-react";
import { scanVideo } from "./scan";
import type { Measurements } from "./grip";
export function ScanDialog({
  onClose,
  onComplete,
}: {
  onClose: () => void;
  onComplete: (m: Measurements, left: boolean) => void;
}) {
  const [width, setWidth] = useState(82);
  const [mode, setMode] = useState<"idle" | "camera" | "file">("idle");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(0);
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
    setError("");
    try {
      if (!navigator.mediaDevices?.getUserMedia)
        throw new Error(
          "Camera access needs localhost or HTTPS. You can upload a video instead.",
        );
      const media = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: 720 },
        audio: false,
      });
      if (controller.current.signal.aborted) {
        media.getTracks().forEach((t) => t.stop());
        return;
      }
      stream.current?.getTracks().forEach((t) => t.stop());
      stream.current = media;
      if (video.current) {
        video.current.srcObject = media;
        await video.current.play();
      }
      setMode("camera");
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "Camera access failed. Try uploading a video.",
      );
    } finally {
      cameraPending.current = false;
    }
  };
  const upload = (file?: File) => {
    if (!file) return;
    setError("");
    setResult(null);
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
    setProgress(0);
    try {
      if (!Number.isFinite(width) || width < 55 || width > 115)
        throw new Error("Enter a palm width between 55 and 115 mm.");
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
        width,
        setProgress,
        controller.current.signal,
        mode === "camera",
      );
      if (controller.current.signal.aborted) return;
      setResult(output);
      stream.current?.getTracks().forEach((t) => t.stop());
      stream.current = null;
    } catch (e) {
      if (!controller.current.signal.aborted)
        setError(
          e instanceof Error ? e.message : "Scan failed. Please try again.",
        );
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
        Show one open hand, fingers spread, in good light. Use a short
        palm-facing video or scan with your camera.
      </p>
      <div className="scan-preview">
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
        {mode === "idle" && (
          <div className="preview-placeholder">
            <Camera size={36} />
            <span>Your hand, your grip.</span>
          </div>
        )}
        {busy && (
          <div className="scan-progress">
            <LoaderCircle className="spin" />
            {progress === 0
              ? "Loading hand detector…"
              : `Reading your hand… ${progress}%`}
          </div>
        )}
      </div>
      {!result ? (
        <>
          <div className="scan-actions">
            <button className="secondary" onClick={camera} disabled={busy}>
              <Camera size={16} />
              Use camera
            </button>
            <label
              className={`secondary file-button ${busy ? "disabled" : ""}`}
            >
              <Upload size={16} />
              Upload video
              <input
                type="file"
                accept="video/*"
                disabled={busy}
                onChange={(e) => upload(e.target.files?.[0])}
              />
            </label>
          </div>
          <label className="calibration">
            Palm width <span>mm</span>
            <input
              type="number"
              min={55}
              max={115}
              value={width}
              disabled={busy}
              onChange={(e) => setWidth(Number(e.target.value))}
            />
          </label>
          <p className="small">
            Measure across the knuckles, from the index to pinky joint,
            excluding the thumb. This sets the model’s real-world scale.
          </p>
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <button
            className="primary wide"
            disabled={mode === "idle" || busy}
            onClick={analyze}
          >
            {busy
              ? "Scanning…"
              : mode === "camera"
                ? "Scan for 4 seconds"
                : "Analyze video"}
          </button>
        </>
      ) : (
        <div className="scan-success">
          <Check size={28} />
          <h3>Your proportions are ready.</h3>
          <p>
            {result.frames} clear frames · {result.hand.toLowerCase()} hand ·{" "}
            {result.measurements.palmWidth} mm palm
          </p>
          <button
            className="primary wide"
            onClick={() =>
              onComplete(result.measurements, result.hand === "Left")
            }
          >
            Use my hand
          </button>
        </div>
      )}
      <p className="privacy">
        Video is processed in your browser and is never uploaded. First use
        downloads the MediaPipe model. Landmark proportions are approximate;
        skin shape and finger thickness are modeled.
      </p>
    </dialog>
  );
}
