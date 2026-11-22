import { useId, useState, type ReactNode } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ReferenceLine,
  ResponsiveContainer,
  XAxis,
  YAxis,
} from "recharts";
import { addDays, dateLabel, number } from "./calendar";
import { endpoint, type Recovery } from "./data";
import { useRead } from "./hooks";
import { LoadingBar } from "./Loading";
import { recoveryScoreReading } from "./recovery";

export interface RecoveryDay {
  day: string;
  recovery: Pick<Recovery, "version" | "method" | "state" | "score" | "band">;
  hrv_ms?: number | null;
  resting_hr?: number | null;
}

export function recoveryPoints(
  rows: RecoveryDay[],
  from: string,
  days: number,
) {
  const byDay = new Map(rows.map((row) => [row.day, row]));
  return Array.from({ length: days }, (_, i) => {
    const day = addDays(from, i),
      row = byDay.get(day);
    return { day, row, ...recoveryScoreReading(row?.recovery) };
  });
}

export function RecoveryHistory({
  device,
  date,
  tz,
  refresh,
}: {
  device: string;
  date: string;
  tz: string;
  refresh: number;
}) {
  const [days, setDays] = useState(90);
  const [retry, setRetry] = useState(0);
  const from = addDays(date, 1 - days);
  const history = useRead<RecoveryDay[]>(
    endpoint(
      device,
      `recovery?from=${from}&to=${date}&tz=${encodeURIComponent(tz)}`,
    ),
    refresh + retry,
  );
  return (
    <RecoveryCard
      rows={history.data}
      from={from}
      days={days}
      loading={history.loading}
      error={history.error ?? undefined}
      retry={() => setRetry((value) => value + 1)}
      controls={
        <div
          className="recovery-period"
          role="group"
          aria-label="Recovery period"
        >
          {[30, 90].map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={days === value}
              onClick={() => setDays(value)}
            >
              {value} days
            </button>
          ))}
        </div>
      }
    />
  );
}
export function RecoveryCard({
  rows,
  from,
  days,
  loading = false,
  error,
  retry,
  controls,
}: {
  rows: RecoveryDay[] | null;
  from: string;
  days: number;
  loading?: boolean;
  error?: string;
  retry?: () => void;
  controls?: ReactNode;
}) {
  const points = recoveryPoints(rows ?? [], from, days);
  const counts = { high: 0, moderate: 0, low: 0 };
  for (const point of points) {
    if (point.score != null && point.row?.recovery.band)
      counts[point.row.recovery.band]++;
  }
  const id = useId();
  return (
    <section className="panel recovery-history" aria-labelledby={id}>
      <div className="panel-head">
        <h2 id={id}>Daily recovery</h2>
        <div className="recovery-history-controls">
          {controls}
          {rows && (
            <div className="recovery-counts" aria-label="Recovery days by band">
              {(["high", "moderate", "low"] as const).map((band) => (
                <span
                  key={band}
                  aria-label={`${counts[band]} ${band} recovery days`}
                  title={`${counts[band]} ${band} recovery days`}
                >
                  <i
                    aria-hidden="true"
                    style={{ background: `var(--recovery-${band})` }}
                  />
                  {counts[band]}
                </span>
              ))}
            </div>
          )}
        </div>
      </div>
      {loading && <LoadingBar label="Loading recovery history" />}
      {error && (
        <div role="alert" className="error small">
          Recovery history unavailable.{" "}
          <button type="button" onClick={retry}>
            Retry
          </button>
        </div>
      )}
      {!rows && loading ? (
        <div className="recovery-chart-placeholder" aria-hidden="true" />
      ) : (
        rows && <RecoveryPlot key={from} points={points} />
      )}
    </section>
  );
}

function RecoveryPlot({
  points,
}: {
  points: ReturnType<typeof recoveryPoints>;
}) {
  const [selected, setSelected] = useState<string | null>(null);
  const [hover, setHover] = useState<string | null>(null);
  const id = useId();
  const valid = points.filter((p) => p.score != null);
  const showHrv = points.some((p) => p.row?.hrv_ms !== undefined);
  const showRhr = points.some((p) => p.row?.resting_hr !== undefined);
  const point = valid.find((p) => p.day === (hover ?? selected));
  const pick = (day: unknown) => valid.find((p) => p.day === day)?.day ?? null;
  const date = (day: string) =>
    dateLabel(day, {
      weekday: "short",
      day: "numeric",
      month: "short",
      year: "numeric",
    });
  const pct = point
    ? (100 * points.indexOf(point)) / Math.max(1, points.length - 1)
    : 50;
  if (!valid.length)
    return (
      <div className="empty recovery-chart-placeholder">
        No recovery readings for this period
      </div>
    );
  return (
    <div
      className="chart-frame recovery-plot"
      role="group"
      tabIndex={0}
      aria-label="Daily recovery history"
      aria-describedby={id}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) {
          setSelected(null);
          setHover(null);
        }
      }}
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          setSelected(null);
          setHover(null);
          return;
        }
        if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key))
          return;
        event.preventDefault();
        setHover(null);
        const current = valid.findIndex((p) => p.day === selected);
        const next =
          event.key === "Home"
            ? 0
            : event.key === "End" || current < 0
              ? valid.length - 1
              : Math.max(
                  0,
                  Math.min(
                    valid.length - 1,
                    current + (event.key === "ArrowLeft" ? -1 : 1),
                  ),
                );
        setSelected(valid[next].day);
      }}
    >
      <span className="sr-only" id={id}>
        Use arrow keys to select a day. Escape dismisses the reading.
      </span>
      <div className="chart" dir="ltr">
        <ResponsiveContainer width="100%" height={244}>
          <BarChart
            data={points}
            accessibilityLayer={false}
            margin={{ left: 0, right: 4, top: 12, bottom: 0 }}
            barCategoryGap="18%"
            onMouseMove={(state) => setHover(pick(state?.activeLabel))}
            onMouseLeave={() => setHover(null)}
            onClick={(state) => setSelected(pick(state?.activeLabel))}
          >
            <CartesianGrid
              vertical={false}
              stroke="var(--grid)"
              strokeDasharray="3 4"
            />
            <XAxis
              dataKey="day"
              tickFormatter={(day) => dateLabel(day)}
              minTickGap={65}
              axisLine={false}
              tickLine={false}
              tick={{ fill: "var(--muted)", fontSize: 11 }}
            />
            <YAxis
              domain={[0, 100]}
              ticks={[0, 33, 67, 100]}
              width={42}
              tickFormatter={(value) => `${value}%`}
              axisLine={false}
              tickLine={false}
              tick={{ fill: "var(--muted)", fontSize: 11 }}
            />
            <Bar
              dataKey="score"
              radius={[2, 2, 0, 0]}
              maxBarSize={24}
              minPointSize={2}
              isAnimationActive={false}
            >
              {points.map((p) => (
                <Cell key={p.day} fill={p.color} />
              ))}
            </Bar>
            {point && <ReferenceLine x={point.day} stroke="var(--muted)" />}
          </BarChart>
        </ResponsiveContainer>
      </div>
      {point && (
        <div
          className="chart-tooltip recovery-tooltip"
          style={{
            left: `clamp(0px, calc(${pct}% - 100px), calc(100% - 200px))`,
          }}
        >
          <strong>{date(point.day)}</strong>
          <div>
            <span className="muted">Recovery</span>
            <span>{point.score}%</span>
          </div>
          {point.row?.hrv_ms !== undefined && (
            <div>
              <span className="muted">HRV</span>
              <span>
                {number(point.row?.hrv_ms)}
                {point.row?.hrv_ms != null ? " ms" : ""}
              </span>
            </div>
          )}
          {point.row?.resting_hr !== undefined && (
            <div>
              <span className="muted">Resting HR</span>
              <span>
                {number(point.row?.resting_hr)}
                {point.row?.resting_hr != null ? " bpm" : ""}
              </span>
            </div>
          )}
        </div>
      )}
      <span className="sr-only" aria-live="polite">
        {selected && point
          ? `${date(point.day)}: ${point.score}%, ${point.row?.recovery.band} recovery.${showHrv ? ` HRV ${number(point.row?.hrv_ms)} milliseconds.` : ""}${showRhr ? ` Resting heart rate ${number(point.row?.resting_hr)} beats per minute.` : ""}`
          : ""}
      </span>
      <div className="sr-only">
        <table>
          <caption>Daily recovery readings</caption>
          <thead>
            <tr>
              <th>Date</th>
              <th>Recovery</th>
              <th>Band</th>
              {showHrv && <th>HRV</th>}
              {showRhr && <th>Resting HR</th>}
            </tr>
          </thead>
          <tbody>
            {points.map((p) => (
              <tr key={p.day}>
                <td>{date(p.day)}</td>
                <td>{p.score == null ? "No reading" : `${p.score}%`}</td>
                <td>{p.score == null ? "—" : p.row?.recovery.band}</td>
                {showHrv && <td>{number(p.row?.hrv_ms)} ms</td>}
                {showRhr && <td>{number(p.row?.resting_hr)} bpm</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
