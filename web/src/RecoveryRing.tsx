import { useEffect, useRef, useState } from "react";
import { Clock, LoaderCircle, X } from "lucide-react";
import { duration, number } from "./calendar";
import type { Insights } from "./data";
import { recoveryReading } from "./recovery";

export function RecoveryRing({
  insight,
  loading,
}: {
  insight: Insights | null;
  loading: boolean;
}) {
  const [open, setOpen] = useState(false);
  loading = loading || insight?.recovery?.state === "updating";
  const reading = recoveryReading(insight);
  return (
    <>
      <button
        type="button"
        className="ring-item recovery-ring"
        aria-label={`Recovery: ${reading.score ?? (loading ? "loading" : reading.status)}`}
        aria-busy={loading}
        aria-haspopup="dialog"
        onClick={() => setOpen(true)}
      >
        <RecoveryRingFace reading={reading} loading={loading} />
      </button>
      {open && (
        <RecoveryDetail
          insight={insight}
          loading={loading}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}

function RecoveryDetail({
  insight,
  loading,
  onClose,
}: {
  insight: Insights | null;
  loading: boolean;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const reading = recoveryReading(insight);
  useEffect(() => {
    const opener =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const dialog = ref.current;
    dialog?.showModal();
    return () => {
      dialog?.close();
      if (opener?.isConnected) opener.focus();
    };
  }, []);
  const metrics = [
    { key: "sleep", label: "Sleep", unit: "" },
    { key: "hrv", label: "HRV", unit: "ms" },
    { key: "resting_hr", label: "Resting heart rate", unit: "bpm" },
  ];
  return (
    <dialog
      ref={ref}
      className="goal-dialog recovery-dialog"
      aria-label="Recovery"
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
    >
      <header>
        <h2>Recovery</h2>
        <button type="button" aria-label="Close" onClick={onClose}>
          <X size={18} />
        </button>
      </header>
      <div className="recovery-score">
        <strong>{reading.score ?? "—"}</strong>
        <span style={{ color: reading.color }}>
          {loading && reading.score == null ? "Updating" : reading.status}
        </span>
        {loading && (
          <LoaderCircle
            className="spinner"
            size={16}
            role="status"
            aria-label="Updating recovery"
          />
        )}
      </div>
      {reading.score != null && (
        <>
          <dl className="recovery-metrics">
            {metrics.map(({ key, label, unit }) => {
              const value = insight?.metrics.find(
                (metric) => metric.key === key,
              )?.value;
              const valid = typeof value === "number" && Number.isFinite(value);
              return (
                <div key={key}>
                  <dt>{label}</dt>
                  <dd>
                    {valid
                      ? key === "sleep"
                        ? duration(value)
                        : number(value, 0)
                      : "—"}
                    {valid && unit && <small> {unit}</small>}
                  </dd>
                </div>
              );
            })}
          </dl>
          {reading.influences.length > 0 && (
            <p className="recovery-influence">
              <span>Main influence</span>
              {reading.influences.join(" · ")}
            </p>
          )}
          {reading.conflict && <p className="muted small">Mixed signals</p>}
        </>
      )}
      <details className="recovery-about">
        <summary>About recovery</summary>
        <p>
          Overnight HRV and resting heart rate, relative to your baseline, with
          last night’s and recent sleep. Sleep uses an eight-hour reference.
        </p>
      </details>
    </dialog>
  );
}

export function RecoveryRingFace({
  reading,
  loading = false,
}: {
  reading: {
    score: number | null;
    fraction: number | null;
    color: string;
    waiting?: boolean;
  };
  loading?: boolean;
}) {
  return (
    <>
      <div className="ring">
        <svg viewBox="0 0 140 140" aria-hidden="true">
          <circle
            cx="70"
            cy="70"
            r="61"
            fill="none"
            stroke="var(--track)"
            strokeWidth="7"
          />
          {reading.fraction != null && reading.fraction > 0 && (
            <circle
              cx="70"
              cy="70"
              r="61"
              fill="none"
              stroke={reading.color}
              strokeWidth="7"
              strokeLinecap="round"
              strokeDasharray={`${383 * reading.fraction} 383`}
            />
          )}
        </svg>
        <div className="ring-reading">
          <strong>
            {loading && reading.score == null ? (
              <LoaderCircle
                className="spinner"
                size={20}
                role="status"
                aria-label="Loading recovery"
              />
            ) : reading.waiting ? (
              <Clock size={20} aria-label="Waiting for sync" />
            ) : (
              (reading.score ?? "—")
            )}
          </strong>
        </div>
      </div>
      <span>
        {reading.waiting && !loading ? "Recovery · Waiting" : "Recovery"}
        {loading && reading.score != null && (
          <LoaderCircle
            className="spinner recovery-refresh"
            size={12}
            role="status"
            aria-label="Updating recovery"
          />
        )}
      </span>
    </>
  );
}
