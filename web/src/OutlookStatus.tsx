import { LoaderCircle, ChevronRight } from "lucide-react";
import { duration, number } from "./calendar";
import type { Insights } from "./data";
function Metric({
  label,
  value,
  unit,
}: {
  label: string;
  value: string;
  unit?: string;
}) {
  return (
    <div className="metric">
      <span>{label}</span>
      <p>
        {value} <small>{unit}</small>
      </p>
    </div>
  );
}
export function OutlookStatus({
  insight,
  loading,
  privateLink = true,
}: {
  insight: Insights | null;
  loading: boolean;
  privateLink?: boolean;
}) {
  const state =
    insight?.state === "ready" ? insight.outlook?.state : insight?.state;
  const tone =
    state === "good"
      ? "var(--green)"
      : state === "low"
        ? "var(--red)"
        : state === "average" || state === "mixed"
          ? "var(--muted)"
          : "var(--muted)";
  const metrics = (insight?.metrics ?? []).filter(
    (m) => m.value != null && ["sleep", "hrv", "resting_hr"].includes(m.key),
  );
  return (
    <details className="outlook-status">
      <summary>
        <span className="muted">Outlook</span>
        {loading ? (
          <LoaderCircle
            className="spinner"
            size={13}
            aria-label="Updating outlook"
          />
        ) : (
          <span className="outlook-dot" style={{ background: tone }} />
        )}
        <span>{loading && !insight ? "Updating" : outlook(state)}</span>
        <ChevronRight
          size={13}
          className="outlook-chevron"
          aria-hidden="true"
        />
      </summary>
      <div className="outlook-detail">
        {metrics.length ? (
          <div className="metrics">
            {metrics.map((m) => {
              const comparison = m.comparison;
              const delta = comparison?.delta;
              const unit =
                m.key === "hrv" ? "ms" : m.key === "resting_hr" ? "bpm" : "";
              const deltaText =
                delta == null
                  ? null
                  : `${delta > 0 ? "+" : delta < 0 ? "−" : ""}${comparison?.unit === "seconds" ? duration(Math.abs(delta)) : number(Math.abs(delta), 0)}${comparison?.unit === "percent" ? "%" : comparison?.unit === "bpm" ? " bpm" : ""}`;
              return (
                <div key={m.key}>
                  <Metric
                    label={
                      m.key === "sleep"
                        ? "Time asleep"
                        : m.key === "hrv"
                          ? "HRV"
                          : "Resting HR"
                    }
                    value={
                      m.key === "sleep" ? duration(m.value) : number(m.value)
                    }
                    unit={unit}
                  />
                  {deltaText && (
                    <span
                      className="small"
                      style={{
                        color:
                          comparison?.signal === "favourable"
                            ? "var(--green)"
                            : comparison?.signal === "unfavourable"
                              ? "var(--red)"
                              : "var(--muted)",
                      }}
                    >
                      {deltaText}
                    </span>
                  )}
                </div>
              );
            })}
          </div>
        ) : (
          <p className="muted small">
            {loading ? "Updating" : "No comparisons yet"}
          </p>
        )}
        {privateLink && (
          <a href="#Sleep" className="text-button">
            View sleep
          </a>
        )}
      </div>
    </details>
  );
}
function outlook(state: string | undefined) {
  return (
    (
      {
        good: "Good",
        average: "Average",
        low: "Low",
        mixed: "Mixed",
        limited: "Limited",
        learning: "Learning",
        updating: "Updating",
        insufficient: "Learning",
        awaiting_sync: "Updating",
        no_sleep: "No sleep",
      } as Record<string, string>
    )[state ?? ""] ?? "—"
  );
}
