import { duration, number } from "./calendar";
import type { SleepSummary } from "./SleepTimeline";
export function SleepStages({
  sleep,
  tz,
}: {
  sleep: SleepSummary | undefined;
  tz: string;
}) {
  if (!sleep?.sleep?.stages)
    return <div className="empty">No sleep stages recorded</div>;
  const s = sleep.sleep;
  const totals = s.stages!;
  const stages = [
    ["Deep", totals.deep_s, "var(--sleep)"],
    ["REM", totals.rem_s, "#555f89"],
    ["Light", totals.light_s, "#33394d"],
    ["Awake", totals.wake_s, "#3b3b3b"],
  ] as const;
  const total = totals.deep_s + totals.rem_s + totals.light_s;
  return (
    <>
      <div className="stage-bar" aria-label="Sleep stages">
        {stages.map(([name, v, c]) => (
          <span key={name} style={{ flex: v || 0, background: c }} />
        ))}
      </div>
      <div className="stage-grid">
        {stages.map(([name, v, c]) => (
          <div key={name}>
            <p>
              <i style={{ background: c }} />
              {name}
            </p>
            <strong>{duration(v)}</strong>{" "}
            <span className="muted">
              {name !== "Awake" && total > 0
                ? `${Math.round((v / total) * 100)}%`
                : ""}
            </span>
          </div>
        ))}
      </div>
      <div className="sleep-times">
        {[
          ["Fell asleep", s.window.onset ?? sleep.start_ts],
          ["Woke up", s.window.offset ?? sleep.end_ts],
        ].map(([label, time]) => (
          <div key={label}>
            <span>{label}</span>
            <strong>
              {new Date(time).toLocaleTimeString(undefined, {
                timeZone: sleep.timezone ?? tz,
                hour: "2-digit",
                minute: "2-digit",
              })}
            </strong>
          </div>
        ))}
      </div>
      {s.partial && <p className="muted small">Partial recording</p>}
    </>
  );
}

export interface NightMetricsData {
  resting_hr?: number | null;
  hrv_rmssd_ms?: number | null;
  respiratory_rate?: number | null;
  efficiency?: number | null;
  partial?: boolean | null;
}
export function NightMetrics({
  metrics: m,
}: {
  metrics?: NightMetricsData | null;
}) {
  return (
    <div className="metrics">
      {[
        ["Resting heart rate", number(m?.resting_hr), "bpm"],
        ["HRV", number(m?.hrv_rmssd_ms), "ms"],
        [
          "Efficiency",
          m?.efficiency != null && !m.partial
            ? number(m.efficiency * 100)
            : "—",
          "%",
        ],
        ["Breathing", number(m?.respiratory_rate, 1), "/ min"],
      ].map(([label, value, unit]) => (
        <div className="metric" key={label}>
          <span>{label}</span>
          <p>
            {value} <small>{unit}</small>
          </p>
        </div>
      ))}
    </div>
  );
}
