import { useEffect, useRef, useState } from "react";
import { Activity, Dumbbell, Footprints } from "lucide-react";
import { addDays, dayKey, dateLabel, duration, number } from "./calendar";
import type { Day, Session } from "./data";
export const sportName = (kind: string) =>
  kind === "resistance"
    ? "Strength training"
    : kind === "walk"
      ? "Walk"
      : kind === "main"
        ? "Main sleep"
        : kind === "nap"
          ? "Nap"
          : "Activity";
export function SportIcon({
  kind,
  size = 19,
}: {
  kind: string;
  size?: number;
}) {
  const Icon =
    kind === "resistance" ? Dumbbell : kind === "walk" ? Footprints : Activity;
  return <Icon size={size} strokeWidth={1.5} aria-hidden="true" />;
}
export function sportTotals(rows: Session[]) {
  const totals = new Map<
    string,
    { kind: string; seconds: number; count: number }
  >();
  for (const row of rows) {
    const entry = totals.get(row.kind) ?? {
      kind: row.kind,
      seconds: 0,
      count: 0,
    };
    entry.seconds += Math.max(0, row.duration_s);
    entry.count++;
    totals.set(row.kind, entry);
  }
  return [...totals.values()].sort((a, b) => b.seconds - a.seconds);
}
export function BySport({ rows }: { rows: Session[] }) {
  const sports = sportTotals(rows),
    max = sports[0]?.seconds ?? 0;
  return sports.length ? (
    <div className="sports">
      {sports.map((s) => (
        <div className="sport" key={s.kind}>
          <SportIcon kind={s.kind} />
          <div>
            <div className="sport-heading">
              <span>{sportName(s.kind)}</span>
              <span className="count-pill">
                {s.count} {s.count === 1 ? "session" : "sessions"}
              </span>
              <strong>{duration(s.seconds)}</strong>
            </div>
            <div className="sport-track">
              <span
                style={{ width: `${max ? (s.seconds / max) * 100 : 0}%` }}
              />
            </div>
          </div>
        </div>
      ))}
    </div>
  ) : (
    <div className="empty">No workouts in this period</div>
  );
}
export function TrainingHeatmap({
  days,
  rows,
  tz,
  end,
  onOpen,
}: {
  days: Day[];
  rows: Session[];
  tz: string;
  end: string;
  onOpen: (day: string) => void;
}) {
  const first = addDays(end, -364),
    start = addDays(
      first,
      -((new Date(first + "T12:00:00Z").getUTCDay() + 6) % 7),
    );
  const count =
    Math.ceil(
      (new Date(end + "T12:00:00Z").getTime() -
        new Date(start + "T12:00:00Z").getTime()) /
        86400000,
    ) + 1;
  const cells = Array.from({ length: Math.ceil(count / 7) * 7 }, (_, i) =>
    addDays(start, i),
  );
  const byDay = new Map(days.map((d) => [d.day, d]));
  const sessions = new Map<string, Session[]>();
  for (const s of rows) {
    const d = dayKey(new Date(s.start_ts), tz);
    sessions.set(d, [...(sessions.get(d) ?? []), s]);
  }
  const [selected, setSelected] = useState<string | null>(null),
    [focused, setFocused] = useState(end);
  const scroll = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (scroll.current) scroll.current.scrollLeft = scroll.current.scrollWidth;
  }, [end]);
  const active = selected ? byDay.get(selected) : null,
    workouts = selected ? (sessions.get(selected) ?? []) : [];
  const level = (value: number | null | undefined) =>
    value == null
      ? "missing"
      : String(Math.min(5, Math.max(0, Math.ceil(value / 4.2))));
  return (
    <div className="heatmap-wrap">
      <div className="heatmap-layout">
        <div className="heatmap-weekdays" aria-hidden="true">
          {["Mon", "", "Wed", "", "Fri", "", ""].map((d, i) => (
            <span key={i}>{d}</span>
          ))}
        </div>
        <div className="heatmap-scroll" ref={scroll}>
          <div
            className="heatmap-months"
            aria-hidden="true"
            style={{ gridTemplateColumns: `repeat(${cells.length / 7},1fr)` }}
          >
            {cells.map((day, i) =>
              i === 0 || day.endsWith("-01") ? (
                <span key={day} style={{ gridColumn: Math.floor(i / 7) + 1 }}>
                  {dateLabel(day, { month: "short" })}
                </span>
              ) : null,
            )}
          </div>
          <div
            className="training-heatmap"
            role="group"
            aria-label="Daily activity, past year"
            style={{ gridTemplateColumns: `repeat(${cells.length / 7}, 1fr)` }}
          >
            {cells.map((day, i) => {
              const d = byDay.get(day),
                future = day > end;
              return (
                <button
                  key={day}
                  tabIndex={focused === day ? 0 : -1}
                  data-level={level(d?.load)}
                  className={future ? "future" : ""}
                  aria-label={`${dateLabel(day, { day: "numeric", month: "long", year: "numeric" })}, ${d?.load == null ? "No load recorded" : `Load ${number(d.load, 1)}`}, ${sessions.get(day)?.length ?? 0} workouts`}
                  aria-pressed={selected === day}
                  disabled={future}
                  onMouseEnter={() => setSelected(day)}
                  onMouseLeave={() => setSelected(null)}
                  onFocus={() => {
                    setSelected(day);
                    setFocused(day);
                  }}
                  onBlur={() => setSelected(null)}
                  onClick={() => {
                    setSelected(day);
                    onOpen(day);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Escape") {
                      setSelected(null);
                      return;
                    }
                    const delta = (
                      {
                        ArrowUp: -1,
                        ArrowDown: 1,
                        ArrowLeft: -7,
                        ArrowRight: 7,
                      } as Record<string, number>
                    )[e.key];
                    if (delta == null) return;
                    e.preventDefault();
                    const next = Math.max(0, Math.min(count - 1, i + delta));
                    const target =
                      scroll.current?.querySelectorAll<HTMLButtonElement>(
                        "button",
                      )[next];
                    target?.focus();
                  }}
                >
                  <span className="sr-only">{day}</span>
                </button>
              );
            })}
          </div>
        </div>
      </div>
      {selected && (
        <div className="heatmap-tooltip" role="tooltip">
          <strong>
            {dateLabel(selected, {
              weekday: "short",
              day: "numeric",
              month: "short",
            })}
          </strong>
          <div>
            <span className="muted">Load</span>
            <span>{number(active?.load, 1)}</span>
          </div>
          {workouts.slice(0, 3).map((s) => (
            <div key={s.id}>
              <span className="muted">
                <SportIcon kind={s.kind} size={14} />
                {sportName(s.kind)}
              </span>
              <span>{duration(s.duration_s)}</span>
            </div>
          ))}
          {workouts.length > 3 && (
            <span className="muted">+{workouts.length - 3} more</span>
          )}
        </div>
      )}
      <div className="heatmap-legend">
        <span>Low</span>
        {[0, 1, 2, 3, 4, 5].map((n) => (
          <i key={n} data-level={n} />
        ))}
        <span>High</span>
        <i data-level="missing" />
        <span>No data</span>
      </div>
    </div>
  );
}
