import { useState } from "react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
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
  if (!data.some((p) => p.value != null))
    return <div className="empty">No readings for this period</div>;
  const label = (key: string) =>
    hourly
      ? new Date(key).toLocaleTimeString(undefined, {
          hour: "2-digit",
          minute: "2-digit",
        })
      : dateLabel(key);
  const ChartType = bar ? BarChart : LineChart;
  const valid = data.filter((p) => p.value != null);
  const point = valid.find((p) => p.day === selected);
  return (
    <div>
      <div className="chart" aria-label={`${unit || "Measurement"} history`}>
        <ResponsiveContainer width="100%" height={180}>
          <ChartType
            data={data}
            margin={{ left: 0, right: 12, top: 12, bottom: 0 }}
            onClick={(state) => {
              const label = state?.activeLabel;
              const p = data.find((p) => p.x === Number(label));
              if (p?.value != null) setSelected(p.day);
            }}
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
              tickFormatter={(x) =>
                label(
                  hourly
                    ? new Date(x).toISOString()
                    : new Date(x).toISOString().slice(0, 10),
                )
              }
              tick={{ fill: "var(--muted)", fontSize: 11 }}
              axisLine={false}
              tickLine={false}
              minTickGap={50}
            />
            <YAxis
              width={38}
              domain={bar ? [0, "auto"] : ["auto", "auto"]}
              tickCount={3}
              tick={{ fill: "var(--muted)", fontSize: 11 }}
              tickFormatter={(v) => number(v, 1)}
              axisLine={false}
              tickLine={false}
            />
            <Tooltip
              labelFormatter={(x) =>
                label(
                  hourly
                    ? new Date(Number(x)).toISOString()
                    : new Date(Number(x)).toISOString().slice(0, 10),
                )
              }
              formatter={(v) => [`${number(Number(v), 1)} ${unit}`, ""]}
              contentStyle={{
                background: "#202020",
                border: "1px solid #383838",
                borderRadius: 10,
                color: "#fafafa",
              }}
            />
            {target != null && (
              <ReferenceLine
                y={target}
                stroke="var(--muted)"
                strokeDasharray="4 4"
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
                ifOverflow="extendDomain"
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
                connectNulls={false}
                dot={valid.length < 5 ? { r: 3, fill: color } : false}
                activeDot={{ r: 4 }}
                isAnimationActive={false}
              />
            )}
          </ChartType>
        </ResponsiveContainer>
      </div>
      {point && (
        <button
          className="reading"
          onClick={() => onOpen?.(point.day)}
          disabled={!onOpen}
        >
          {label(point.day)} · {number(point.value, 1)} {unit}
          {onOpen ? " →" : ""}
        </button>
      )}
      <details className="data-disclosure">
        <summary>Readings</summary>
        <table>
          <thead>
            <tr>
              <th>Date</th>
              <th>{unit || "Value"}</th>
            </tr>
          </thead>
          <tbody>
            {valid.map((p) => (
              <tr key={p.day}>
                <td>
                  {onOpen ? (
                    <button
                      className="text-button"
                      onClick={() => onOpen(p.day)}
                    >
                      {label(p.day)}
                    </button>
                  ) : (
                    label(p.day)
                  )}
                </td>
                <td>{number(p.value, 1)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </div>
  );
}
