import { useId, useState } from "react";
import { ArrowUpRight } from "lucide-react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  ReferenceLine,
  ReferenceDot,
} from "recharts";
import { dateLabel, number } from "./calendar";
export interface Point {
  day: string;
  x: number;
  value: number | null;
}
export function Chart({
  data,
  color = "var(--text)",
  unit = "",
  bar = false,
  target,
  hourly = false,
  onOpen,
}: {
  data: Point[];
  color?: string;
  unit?: string;
  bar?: boolean;
  hourly?: boolean;
  target?: number | null;
  onOpen?: (day: string) => void;
}) {
  const [selected, setSelected] = useState<string | null>(null);
  const [hover, setHover] = useState<string | null>(null);
  const id = useId();
  const valid = data.filter((p) => p.value != null);
  const point = valid.find((p) => p.day === (hover ?? selected));
  const label = (key: string) =>
    hourly
      ? new Date(key).toLocaleTimeString(undefined, {
          hour: "2-digit",
          minute: "2-digit",
        })
      : dateLabel(key, { day: "numeric", month: "short", year: "numeric" });
  const axisLabel = (x: number) =>
    hourly
      ? new Date(x).toLocaleTimeString(undefined, {
          hour: "2-digit",
          minute: "2-digit",
        })
      : dateLabel(new Date(x).toISOString().slice(0, 10));
  const ChartType = bar ? BarChart : LineChart;
  const pick = (x: unknown) =>
    data.find((p) => p.x === Number(x) && p.value != null)?.day ?? null;
  const pct =
    point && data.length > 1
      ? (100 * (point.x - data[0].x)) / (data.at(-1)!.x - data[0].x)
      : 50;
  if (!valid.length)
    return <div className="empty chart-empty">No readings for this period</div>;
  return (
    <div
      className="chart-frame"
      tabIndex={0}
      role="group"
      aria-label={`${unit || "Measurement"} history`}
      aria-describedby={id}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget)) setSelected(null);
      }}
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          setSelected(null);
          setHover(null);
          return;
        }
        if (e.key === "Enter" && point && onOpen) {
          e.preventDefault();
          onOpen(point.day);
          return;
        }
        if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) return;
        e.preventDefault();
        setHover(null);
        const current = valid.findIndex((p) => p.day === selected);
        const next =
          e.key === "Home"
            ? 0
            : e.key === "End"
              ? valid.length - 1
              : current < 0
                ? valid.length - 1
                : Math.max(
                    0,
                    Math.min(
                      valid.length - 1,
                      current + (e.key === "ArrowLeft" ? -1 : 1),
                    ),
                  );
        setSelected(valid[next].day);
      }}
    >
      <span className="sr-only" id={id}>
        Use arrow keys to select a reading.
        {onOpen ? " Press Enter to open its day." : ""}
      </span>
      <div className="chart">
        <ResponsiveContainer width="100%" height={168}>
          <ChartType
            data={data}
            accessibilityLayer={false}
            margin={{ left: 0, right: 12, top: 12, bottom: 0 }}
            onMouseMove={(s) => setHover(pick(s?.activeLabel))}
            onMouseLeave={() => setHover(null)}
            onClick={(s) => setSelected(pick(s?.activeLabel))}
          >
            <CartesianGrid
              vertical={false}
              stroke="var(--grid)"
              strokeDasharray="3 4"
            />
            <XAxis
              dataKey="x"
              type="number"
              domain={["dataMin", "dataMax"]}
              scale="time"
              padding={bar ? { left: 12, right: 12 } : undefined}
              tickFormatter={axisLabel}
              tick={{ fill: "var(--muted)", fontSize: 11 }}
              axisLine={false}
              tickLine={false}
              minTickGap={50}
            />
            <YAxis
              width={52}
              domain={bar ? [0, "auto"] : ["auto", "auto"]}
              tickCount={3}
              tick={{ fill: "var(--muted)", fontSize: 11 }}
              tickFormatter={(v) => number(v, 1)}
              axisLine={false}
              tickLine={false}
            />
            {target != null && (
              <ReferenceLine
                y={target}
                stroke="var(--muted)"
                strokeDasharray="4 4"
                ifOverflow="extendDomain"
                label={({ viewBox }) => {
                  const box = viewBox as {
                    x: number;
                    y: number;
                    width: number;
                  };
                  return (
                    <text
                      x={box.x + box.width - 4}
                      y={box.y - 10}
                      textAnchor="end"
                      fill="var(--muted)"
                      fontSize={11}
                    >
                      Target {number(target, 1)}
                    </text>
                  );
                }}
              />
            )}
            {bar ? (
              <Bar
                dataKey="value"
                fill={color}
                radius={[3, 3, 0, 0]}
                maxBarSize={24}
                isAnimationActive={false}
              />
            ) : (
              <Line
                dataKey="value"
                type="linear"
                stroke={color}
                strokeWidth={2}
                strokeLinecap="round"
                connectNulls={false}
                dot={valid.length < 5 ? { r: 3, fill: color } : false}
                activeDot={false}
                isAnimationActive={false}
              />
            )}
            {point && (
              <ReferenceLine
                x={point.x}
                stroke="var(--muted)"
                strokeWidth={1}
              />
            )}
            {point && (
              <ReferenceDot
                x={point.x}
                y={point.value!}
                r={4}
                fill={color}
                stroke="var(--panel)"
                strokeWidth={2}
              />
            )}
          </ChartType>
        </ResponsiveContainer>
      </div>
      {point && (
        <div
          className="chart-tooltip"
          style={{
            left: `clamp(8px, calc(${pct}% - 85px), calc(100% - 170px))`,
          }}
        >
          <strong>{label(point.day)}</strong>
          <div>
            <span className="muted">{unit || "Value"}</span>
            <span>
              {number(point.value, 1)}
              {onOpen && (
                <button
                  className="tooltip-open"
                  aria-label={`Open ${label(point.day)}`}
                  onClick={() => onOpen(point.day)}
                >
                  <ArrowUpRight size={15} />
                </button>
              )}
            </span>
          </div>
        </div>
      )}
      <span className="sr-only" aria-live="polite">
        {selected && point
          ? `${label(point.day)}: ${number(point.value, 1)} ${unit}`
          : ""}
      </span>
      <div className="sr-only">
        <table>
          <caption>{unit || "Measurement"} history</caption>
          <thead>
            <tr>
              <th>Date</th>
              <th>Value</th>
            </tr>
          </thead>
          <tbody>
            {valid.map((p) => (
              <tr key={p.day}>
                <td>{label(p.day)}</td>
                <td>
                  {number(p.value, 1)} {unit}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
