import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type CSSProperties,
} from "react";
import {
  Activity,
  Dumbbell,
  Footprints,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
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
export interface ActivityRow {
  key: string | number;
  day: string;
  kind: string;
  duration_s: number;
  load?: number | null;
  avg_hr?: number | null;
  label?: string;
  count?: number;
}
export interface SportTotal {
  kind: string;
  seconds: number;
  count: number;
}
export function activityRows(rows: Session[], tz: string): ActivityRow[] {
  return rows.map((s) => ({
    key: s.id,
    day: dayKey(new Date(s.start_ts), tz),
    kind: s.kind,
    duration_s: s.duration_s,
    load: s.load,
    avg_hr: s.avg_hr,
  }));
}
export function sportTotals(rows: Pick<Session, "kind" | "duration_s">[]) {
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
export function BySport({
  rows = [],
  totals,
}: {
  rows?: Pick<Session, "kind" | "duration_s">[];
  totals?: SportTotal[];
}) {
  const sports = totals ?? sportTotals(rows),
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
  end,
  from,
  onOpen,
}: {
  days: Pick<Day, "day" | "load">[];
  rows: ActivityRow[];
  end: string;
  from?: string;
  onOpen?: (day: string) => void;
}) {
  const first = from ?? addDays(end, -364),
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
  const sessions = new Map<string, ActivityRow[]>();
  for (const s of rows) {
    const d = s.day;
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
    <div
      className={`heatmap-wrap${from ? " heatmap-scoped" : ""}`}
      style={
        from
          ? ({ "--heatmap-weeks": cells.length / 7 } as CSSProperties)
          : undefined
      }
    >
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
            {Array.from({ length: cells.length / 7 }, (_, week) => {
              const dates = cells
                .slice(week * 7, week * 7 + 7)
                .filter((day) => day >= first && day <= end);
              const label =
                dates.find((day) => day.endsWith("-01")) ??
                (week === 0 ? dates[0] : undefined);
              return label ? (
                <span key={week} style={{ gridColumn: week + 1, gridRow: 1 }}>
                  {dateLabel(label, { month: "short" })}
                </span>
              ) : null;
            })}
          </div>
          <div
            className="training-heatmap"
            role="group"
            aria-label={
              from
                ? "Daily activity, shared period"
                : "Daily activity, past year"
            }
            style={{ gridTemplateColumns: `repeat(${cells.length / 7}, 1fr)` }}
          >
            {cells.map((day, i) => {
              const d = byDay.get(day),
                future = day > end || day < first;
              return (
                <button
                  key={day}
                  tabIndex={focused === day ? 0 : -1}
                  data-level={level(d?.load)}
                  className={future ? "future" : ""}
                  aria-label={`${dateLabel(day, { day: "numeric", month: "long", year: "numeric" })}, ${d?.load == null ? "No load recorded" : `Load ${number(d.load, 1)}`}, ${sessions.get(day)?.reduce((sum, s) => sum + (s.count ?? 1), 0) ?? 0} workouts`}
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
                    onOpen?.(day);
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
                    const next = Math.max(
                      cells.indexOf(first),
                      Math.min(count - 1, i + delta),
                    );
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
            <div key={s.key}>
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

function ActivityItem({
  row,
  onDetail,
  children,
}: {
  row: ActivityRow;
  onDetail?: (row: ActivityRow) => void;
  children: ReactNode;
}) {
  return onDetail ? (
    <button className="workout" onClick={() => onDetail(row)}>
      {children}
    </button>
  ) : (
    <div className="workout">{children}</div>
  );
}
export function RecentActivities({
  rows,
  today,
  pageSize,
  onDetail,
}: {
  rows: ActivityRow[];
  today: string;
  pageSize?: number;
  onDetail?: (row: ActivityRow) => void;
}) {
  const [pageIndex, setPageIndex] = useState(0);
  const size = pageSize ?? Math.max(1, rows.length);
  const lastPage = Math.max(0, Math.ceil(rows.length / size) - 1);
  const currentPage = Math.min(pageIndex, lastPage);
  const first = currentPage * size;
  return rows.length ? (
    <>
      <div className="timeline">
        {rows.slice(first, first + size).map((session, index, visible) => {
          const day = session.day;
          const previous = index > 0 ? visible[index - 1].day : null;
          return (
            <div className="timeline-entry" key={session.key}>
              {day !== previous && (
                <div className="timeline-date">
                  <span />
                  {day === today
                    ? "Today"
                    : day === addDays(today, -1)
                      ? "Yesterday"
                      : dateLabel(day, {
                          weekday: "short",
                          day: "numeric",
                          month: "short",
                        })}
                </div>
              )}
              <ActivityItem row={session} onDetail={onDetail}>
                <span className="workout-icon">
                  <SportIcon kind={session.kind} />
                </span>
                <span className="workout-title">
                  {session.label ?? sportName(session.kind)}
                  <small>
                    {duration(session.duration_s)}
                    {session.avg_hr != null
                      ? ` · ${number(session.avg_hr)} bpm`
                      : ""}
                  </small>
                </span>
                <span className="load-track">
                  <span
                    style={{
                      width: `${Math.min(100, Math.max(0, ((session.load ?? 0) / 21) * 100))}%`,
                    }}
                  />
                </span>
                <span className="workout-load">{number(session.load, 1)}</span>
              </ActivityItem>
            </div>
          );
        })}
      </div>
      {rows.length > size && (
        <div className="workout-paging">
          <span className="muted small" aria-live="polite">
            {first + 1}–{Math.min(first + size, rows.length)} of {rows.length}
          </span>
          <div>
            <button
              className="icon-button"
              aria-label="Previous workouts"
              disabled={currentPage === 0}
              onClick={() => setPageIndex(currentPage - 1)}
            >
              <ChevronLeft size={18} />
            </button>
            <button
              className="icon-button"
              aria-label="Next workouts"
              disabled={currentPage === lastPage}
              onClick={() => setPageIndex(currentPage + 1)}
            >
              <ChevronRight size={18} />
            </button>
          </div>
        </div>
      )}
    </>
  ) : (
    <div className="empty">No workouts in this period</div>
  );
}
