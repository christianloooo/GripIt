import { lazy, Suspense, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowDownToLine,
  ArrowRight,
  Check,
  CircleHelp,
  Fingerprint,
  Hand,
  Layers3,
  Maximize2,
  Move,
  RotateCcw,
  ScanLine,
  SlidersHorizontal,
  Target,
  X,
  ZoomIn,
} from "lucide-react";
import { Scene } from "./Scene";
const ScanDialog = lazy(() =>
  import("./ScanDialog").then((module) => ({ default: module.ScanDialog })),
);
import { DEFAULT_MEASUREMENTS, FINGERS, PITCHES, solveGrip } from "./grip";
import type { Measurements } from "./grip";
const copyMeasurements = () => structuredClone(DEFAULT_MEASUREMENTS);
export default function App() {
  const [measurements, setMeasurements] =
    useState<Measurements>(copyMeasurements);
  const [pitchIndex, setPitchIndex] = useState(0),
    [left, setLeft] = useState(false),
    [annotations, setAnnotations] = useState(true),
    [exploded, setExploded] = useState(false),
    [reset, setReset] = useState(0);
  const [scan, setScan] = useState(false),
    [tab, setTab] = useState<"grip" | "hand">("grip"),
    [personalized, setPersonalized] = useState(false),
    [help, setHelp] = useState(false),
    [toast, setToast] = useState("");
  const pitch = PITCHES[pitchIndex];
  const solution = useMemo(
    () => solveGrip(measurements, pitch),
    [measurements, pitch],
  );
  const rigs = solution.fingers;
  const unresolved = rigs.filter((r) => r.error > 8 || r.clearance < -1).length;
  const download = () => {
    const payload = {
      version: 1,
      units: "mm",
      pitch: pitch.id,
      handedness: left ? "Left" : "Right",
      measurements,
      ball: {
        radius: 36.5,
        position: solution.ball.position.toArray(),
        rotation: solution.ball.rotation,
      },
      objective: solution.objective,
      canonicalHand: "Right",
      mirrorX: left,
      fingers: rigs.map((r) => ({
        name: r.name,
        root: r.root.toArray(),
        baseYawRadians: r.yaw,
        anglesRadians: r.angles,
        target: r.target.toArray(),
        targetErrorMm: r.error,
        minimumClearanceMm: r.clearance,
      })),
      note: "Geometric fit only. Index/middle targets lie on the rendered seam curve. Coordinates describe the canonical right hand; mirror X for a left hand.",
    };
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(payload, null, 2)], {
        type: "application/json",
      }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = `gripit-${pitch.id}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    setToast("Grip configuration downloaded.");
    setTimeout(() => setToast(""), 3500);
  };
  return (
    <div className="app">
      <header className="header">
        <a className="brand" href="./" aria-label="GripIt home">
          <span className="brand-ball">✳</span>grip<span>it</span>
          <span className="brand-period">.</span>
        </a>
        <nav aria-label="Main navigation">
          <span className="nav-active">Grip studio</span>
          <button onClick={() => setHelp(true)}>
            How it works <ArrowRight size={14} />
          </button>
        </nav>
        <div className="header-right">
          <span className="prototype">
            <i />
            PROTOTYPE / 01
          </span>
          <button
            className="help-button"
            onClick={() => setHelp(true)}
            aria-label="Help"
          >
            <CircleHelp size={20} />
          </button>
        </div>
      </header>
      <main>
        <div className="intro">
          <div>
            <div className="eyebrow">
              <span className="tiny-line" />
              BUILT AROUND YOU
            </div>
            <h1>
              Great pitches start
              <br />
              with the right <em>grip.</em>
            </h1>
            <p>
              Get a feel for your next pitch. Explore a 3D grip
              <br className="desktop-break" /> shaped to your hand, down to the
              fingertips.
            </p>
          </div>
          <div className="intro-note">
            <span className="note-symbol">↗</span>
            <p>
              Your hand.
              <br />
              Your mechanics.
              <br />
              <strong>Your next edge.</strong>
            </p>
          </div>
        </div>
        <div className="workspace">
          <aside className="sidebar">
            <div className="panel-heading">
              <span>YOUR SETUP</span>
              <SlidersHorizontal size={16} />
            </div>
            <div className="tabs" role="tablist" aria-label="Setup">
              <button
                role="tab"
                aria-selected={tab === "grip"}
                onClick={() => setTab("grip")}
              >
                <Target size={15} />
                The pitch
              </button>
              <button
                role="tab"
                aria-selected={tab === "hand"}
                onClick={() => setTab("hand")}
              >
                <Hand size={15} />
                Your hand
              </button>
            </div>
            {tab === "grip" ? (
              <div className="setup-content">
                <div className="section-title">
                  <span>01</span>
                  <h2>Pick your pitch</h2>
                </div>
                <p className="muted">A starting point for your next session.</p>
                <div className="pitch-list">
                  {PITCHES.map((p, i) => (
                    <button
                      key={p.id}
                      className={`pitch-card ${i === pitchIndex ? "selected" : ""}`}
                      onClick={() => setPitchIndex(i)}
                      aria-pressed={i === pitchIndex}
                    >
                      <span className={`pitch-mark pitch-mark-${i}`}>
                        {p.short}
                      </span>
                      <span className="pitch-name">
                        <small>{p.family}</small>
                        <strong>{p.name}</strong>
                      </span>
                      <span className="radio">
                        {i === pitchIndex && <span />}
                      </span>
                    </button>
                  ))}
                </div>
                <div className="handedness">
                  <span>Throwing hand</span>
                  <div>
                    <button
                      className={!left ? "active" : ""}
                      onClick={() => setLeft(false)}
                    >
                      Right
                    </button>
                    <button
                      className={left ? "active" : ""}
                      onClick={() => setLeft(true)}
                    >
                      Left
                    </button>
                  </div>
                </div>
              </div>
            ) : (
              <div className="setup-content">
                <div className="section-title">
                  <span>02</span>
                  <h2>Shape your hand</h2>
                </div>
                <p className="muted">
                  {personalized
                    ? "Measured automatically from your baseball scan."
                    : "Sample dimensions. Scan to measure your hand."}
                </p>
                <div className="scan-dimension">
                  <span>Palm width</span>
                  <strong>{measurements.palmWidth.toFixed(0)} mm</strong>
                </div>
                {FINGERS.map((f) => (
                  <div className="scan-dimension" key={f}>
                    <span className="capitalize">{f}</span>
                    <strong>
                      {measurements.segments[f]
                        .reduce((a, b) => a + b, 0)
                        .toFixed(0)}{" "}
                      mm
                    </strong>
                  </div>
                ))}
                <p className="small">
                  {personalized
                    ? "73 mm baseball reference · Estimated geometry"
                    : "Place a baseball beside your open hand. No manual measurements needed."}
                </p>
                <button
                  className="text-button"
                  onClick={() => {
                    setMeasurements(copyMeasurements());
                    setPersonalized(false);
                  }}
                >
                  Use sample hand
                </button>
              </div>
            )}
            <div className="scan-card">
              <div className="scan-icon">
                <Fingerprint size={26} />
              </div>
              <span className="tag">PERSONALIZE YOUR GRIP</span>
              <h3>A hand like yours.</h3>
              <p>
                Scan your open hand beside a baseball. We’ll measure the
                proportions.
              </p>
              <button onClick={() => setScan(true)} className="primary">
                {personalized ? "Rescan my hand" : "Scan my hand"}
                <ArrowRight size={16} />
              </button>
              <span className="local-note">
                <span />
                Private. Processed on your device.
              </span>
            </div>
          </aside>
          <section className="viewer" aria-label="Interactive 3D grip viewer">
            <div className="viewer-top">
              <div>
                <span className="live-dot" />
                LIVE GRIP VIEW
              </div>
              <span className="model-pill">
                <Hand size={13} />
                {personalized ? "Your proportions" : "Sample hand"}
                <span>·</span>
                {left ? "L" : "R"}
              </span>
            </div>
            <div className="scene">
              <Scene
                measurements={measurements}
                pitch={pitch}
                left={left}
                annotations={annotations}
                exploded={exploded}
                reset={reset}
              />
            </div>
            <div className="viewer-caption">
              <span className="caption-number">
                0{pitchIndex + 1} / GRIP STUDY
              </span>
              <h2>{pitch.name}</h2>
              <p>{pitch.subtitle}</p>
            </div>
            <div className="viewer-tools">
              <button
                className={annotations ? "on" : ""}
                aria-label="Toggle finger labels"
                aria-pressed={annotations}
                title="Finger labels"
                onClick={() => setAnnotations(!annotations)}
              >
                <ScanLine size={19} />
              </button>
              <button
                className={exploded ? "on" : ""}
                aria-label="Separate hand and ball"
                aria-pressed={exploded}
                title="Separate hand and ball"
                onClick={() => setExploded(!exploded)}
              >
                <Layers3 size={19} />
              </button>
              <span />
              <button
                aria-label="Reset camera"
                title="Reset camera"
                onClick={() => setReset((n) => n + 1)}
              >
                <RotateCcw size={18} />
              </button>
              <button
                aria-label="Expand viewer"
                title="Full screen"
                onClick={() => {
                  const el = document.querySelector(".viewer");
                  if (document.fullscreenElement)
                    void document.exitFullscreen();
                  else
                    void el
                      ?.requestFullscreen()
                      .catch(() =>
                        setToast("Full screen is unavailable in this browser."),
                      );
                }}
              >
                <Maximize2 size={18} />
              </button>
            </div>
            <div className="viewer-bottom">
              <div>
                <Move size={14} />
                Drag to rotate<span>·</span>
                <ZoomIn size={14} />
                Scroll to zoom<span>·</span>Right-drag to pan
              </div>
              <span>3D / MILLIMETERS</span>
            </div>
          </section>
        </div>
        <section className="grip-details">
          <div className="detail-intro">
            <span className="eyebrow">THE FEEL OF IT</span>
            <h2>
              Small details.
              <br />A different pitch.
            </h2>
          </div>
          <div className="detail-body">
            <p>{pitch.description}</p>
            <div className="cue-list">
              {pitch.cues.map((cue, i) => (
                <span key={cue}>
                  <b>{i + 1}</b>
                  {cue}
                </span>
              ))}
            </div>
            <p className="model-note">
              Approximate geometric fit ·{" "}
              {unresolved
                ? `${unresolved} contact${unresolved > 1 ? "s" : ""} unresolved`
                : "Contact fit estimated"}{" "}
              · Largest target gap:{" "}
              {Math.max(...rigs.map((r) => r.error)).toFixed(1)} mm. Hand
              thickness is modeled.
            </p>
          </div>
          <button className="export-button" onClick={download}>
            <ArrowDownToLine size={17} />
            Export grip
            <ArrowRight size={16} />
          </button>
        </section>
        <div className="asset-credit">
          Ball:{" "}
          <a
            href="https://sketchfab.com/3d-models/worn-baseball-ball-fdf3de6ae225421ea78961b897b9608a"
            target="_blank"
            rel="noreferrer"
          >
            Worn Baseball Ball by Alex Bes
          </a>{" "}
          · CC BY 4.0 · Rescaled to 73 mm. Hand positions are approximate
          geometric fits.
        </div>
        <footer>
          <span>MADE FOR THE FEEL OF THE GAME.</span>
          <span>
            GripIt studio <span className="footer-dot">●</span> A work in
            progress.
          </span>
        </footer>
      </main>
      {scan && (
        <Suspense
          fallback={
            <div className="toast" role="status">
              Loading hand scanner…
            </div>
          }
        >
          <ScanDialog
            onClose={() => setScan(false)}
            onComplete={(m, isLeft) => {
              setMeasurements(m);
              setLeft(isLeft);
              setPersonalized(true);
              setScan(false);
              setTab("hand");
            }}
          />
        </Suspense>
      )}
      {help && (
        <HelpDialog onClose={() => setHelp(false)}>
          <button
            className="dialog-close icon-button"
            aria-label="Close help"
            onClick={() => setHelp(false)}
          >
            <X size={20} />
          </button>
          <span className="eyebrow">WELCOME TO THE STUDIO</span>
          <h2 id="help-title">Find your feel.</h2>
          <p>1. Choose a pitch to explore its illustrative grip.</p>
          <p>
            2. Scan one open hand with a regulation baseball beside it. The ball
            sets the scale automatically; no measurements to type.
          </p>
          <p>
            3. Rotate, zoom, and pan to inspect the finger positions. Export the
            dimensions and joint angles as JSON.
          </p>
          <p className="small">
            This prototype uses an authored, rigged hand mesh and constrained
            numerical finger positioning. It does not reconstruct exact skin
            geometry, predict pitch movement, or optimize performance. Some
            proportions cannot reach every target; the studio reports these fits
            below the viewer.
          </p>
          <button className="primary" onClick={() => setHelp(false)}>
            Got it
            <Check size={16} />
          </button>
        </HelpDialog>
      )}
      {toast && (
        <div className="toast" role="status">
          {toast}
          <button
            onClick={() => setToast("")}
            aria-label="Dismiss notification"
          >
            <X size={15} />
          </button>
        </div>
      )}
    </div>
  );
}

function HelpDialog({
  onClose,
  children,
}: {
  onClose: () => void;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    ref.current?.showModal();
  }, []);
  return (
    <dialog
      ref={ref}
      className="help-modal"
      aria-labelledby="help-title"
      onCancel={onClose}
    >
      {children}
    </dialog>
  );
}
