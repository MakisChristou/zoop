import { useId } from "react";
import { ChevronRight } from "lucide-react";
import { duration } from "./calendar";
import type { SleepData } from "./data";

export interface SleepSummary {
  start_ts: string;
  end_ts: string;
  timezone?: string;
  sleep?: {
    window: Pick<SleepData["window"], "onset" | "offset" | "asleep_s">;
  } & Partial<Pick<SleepData, "stages" | "segments" | "partial">>;
}
const stages = [
  ["wake", "Awake", "#696969"],
  ["rem", "REM", "#555f89"],
  ["light", "Light", "#33394d"],
  ["deep", "Deep", "var(--sleep)"],
] as const;

export function SleepTimeline({
  sleep,
  tz,
  onOpen,
}: {
  sleep?: SleepSummary;
  tz: string;
  onOpen?: () => void;
}) {
  const descriptionId = useId();
  const start = Date.parse(sleep?.sleep?.window.onset ?? sleep?.start_ts ?? ""),
    end = Date.parse(sleep?.sleep?.window.offset ?? sleep?.end_ts ?? "");
  const validWindow = Number.isFinite(start) && end > start;
  const segments = validWindow
    ? (sleep?.sleep?.segments ?? []).filter(
        (s) =>
          stages.some(([key]) => key === s.stage) &&
          Date.parse(s.end) > Math.max(start, Date.parse(s.start)) &&
          Date.parse(s.start) < end,
      )
    : [];
  const time = (ms: number) =>
    new Date(ms).toLocaleTimeString(undefined, {
      timeZone: sleep?.timezone ?? tz,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    });
  const axisTimes: number[] = [];
  if (validWindow) {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: sleep?.timezone ?? tz,
      minute: "2-digit",
      second: "2-digit",
    }).formatToParts(new Date(start));
    const minutes = Number(parts.find((p) => p.type === "minute")?.value ?? 0);
    const seconds = Number(parts.find((p) => p.type === "second")?.value ?? 0);
    const firstHour =
      start -
      seconds * 1000 -
      (start % 1000) +
      (minutes || seconds || start % 1000 ? 60 - minutes : 0) * 60000;
    const step = Math.max(1, Math.ceil((end - start) / 10800000)) * 3600000;
    for (
      let tick = firstHour;
      tick <= end && axisTimes.length < 4;
      tick += step
    )
      axisTimes.push(tick);
    if (!axisTimes.length) axisTimes.push(start, end);
  }
  const content = (
    <>
      <span className="sleep-night-heading">
        <span>Time asleep</span>
        {onOpen && <ChevronRight size={18} aria-hidden="true" />}
      </span>
      <span id={descriptionId} className="sleep-night-duration">
        {duration(sleep?.sleep?.window.asleep_s)}
      </span>
      {segments.length ? (
        <div className="sleep-timeline" dir="ltr">
          <div className="sleep-stage-labels" aria-hidden="true">
            {stages.map(([key, label]) => (
              <span key={key}>{label}</span>
            ))}
          </div>
          <div className="sleep-stage-plot">
            <svg
              viewBox="0 0 600 112"
              preserveAspectRatio="none"
              role="img"
              aria-label={`Sleep stages from ${time(start)} to ${time(end)}`}
            >
              {stages.map(([key], row) => (
                <line
                  key={key}
                  x1="0"
                  x2="600"
                  y1={row * 28 + 14}
                  y2={row * 28 + 14}
                  stroke="var(--grid)"
                  strokeDasharray="3 3"
                  vectorEffect="non-scaling-stroke"
                />
              ))}
              {segments.map((s, i) => {
                const row = stages.findIndex(([key]) => key === s.stage),
                  x =
                    ((Math.max(start, Date.parse(s.start)) - start) /
                      (end - start)) *
                    600,
                  width =
                    ((Math.min(end, Date.parse(s.end)) -
                      Math.max(start, Date.parse(s.start))) /
                      (end - start)) *
                    600;
                return (
                  <rect
                    key={i}
                    x={x}
                    y={row * 28 + 10}
                    width={Math.max(1, Math.min(600 - x, width))}
                    height="8"
                    rx="3"
                    fill={stages[row][2]}
                  >
                    <title>
                      {stages[row][1]} · {time(Date.parse(s.start))}–
                      {time(Date.parse(s.end))}
                    </title>
                  </rect>
                );
              })}
            </svg>
            <div className="sleep-stage-times" aria-hidden="true">
              {axisTimes.map((t) => (
                <span
                  key={t}
                  style={{
                    left: `clamp(20px, ${((t - start) / (end - start)) * 100}%, calc(100% - 20px))`,
                  }}
                >
                  {time(t)}
                </span>
              ))}
            </div>
          </div>
        </div>
      ) : (
        <span className="sleep-night-empty">
          {sleep?.sleep ? "Stages unavailable" : "No sleep recorded"}
        </span>
      )}
      <span className="sr-only">
        {segments.map((s, i) => (
          <span key={i}>
            {stages.find(([key]) => key === s.stage)?.[1]}{" "}
            {time(Date.parse(s.start))} to {time(Date.parse(s.end))}.{" "}
          </span>
        ))}
      </span>
    </>
  );
  return (
    <section className="panel sleep-night">
      {onOpen && sleep?.sleep ? (
        <button
          className="sleep-night-open"
          onClick={onOpen}
          aria-label="Open sleep details"
          aria-describedby={descriptionId}
        >
          {content}
        </button>
      ) : (
        <div className="sleep-night-content">{content}</div>
      )}
    </section>
  );
}
