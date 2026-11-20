import {
  useEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ArrowDownRight,
  ArrowUpRight,
  ArrowRight,
  Clock,
  Footprints,
  MoreHorizontal,
  ChevronLeft,
  ChevronRight,
  LoaderCircle,
  X,
} from "lucide-react";
import { api, ApiError, endpoint, type Goal } from "./data";
import { useRead, type Dataset } from "./hooks";
import {
  addDays,
  atDay,
  dailyWeights,
  dateLabel,
  dayKey,
  number,
  series,
} from "./calendar";
import { Chart } from "./Chart";
import { LoadingBar } from "./Loading";

type Settings = NonNullable<Goal["goal"]>;
const phaseTitle = (g: Settings | null) =>
  g?.phase === "bulk"
    ? "Bulk"
    : g?.phase === "maintenance"
      ? "Maintenance"
      : "Cut";
const rangeBand = (s: Goal["summary"]): [number, number] | null =>
  s?.maintenance_lower_kg != null && s?.maintenance_upper_kg != null
    ? [s.maintenance_lower_kg, s.maintenance_upper_kg]
    : null;
export function outlookTitle(state?: string) {
  return (
    (
      {
        stable: "Stable",
        building_trend: "Building trend",
        watching: "Watching",
        drifting_up: "Drifting up",
        drifting_down: "Drifting down",
        above_range: "Above range",
        below_range: "Below range",
        on_pace: "On pace",
        below_pace: "Below pace",
        above_pace: "Above pace",
        possible_stall: "Possible stall",
      } as Record<string, string>
    )[state ?? ""] ?? "Building trend"
  );
}
export interface GoalPeriod {
  id: number;
  goal: Settings;
  ended_at: string;
  end_reason: string;
  summary: NonNullable<Goal["summary"]>;
}
interface History {
  items: GoalPeriod[];
  next_cursor: number | null;
}
export function goalOutcome(period: GoalPeriod) {
  const p = period.summary.progress;
  if (p?.current_weight_kg == null) return "No weigh-ins";
  if (
    p.target_weight_kg != null &&
    (period.goal.phase === "bulk"
      ? p.current_weight_kg >= p.target_weight_kg
      : p.current_weight_kg <= p.target_weight_kg)
  )
    return "Target reached";
  return period.end_reason === "manual"
    ? period.goal.finish_date
      ? "Ended early"
      : "Ended"
    : period.end_reason === "legacy"
      ? "Ended"
      : "Finished";
}
function periodDates(period: GoalPeriod) {
  const start = dayKey(new Date(period.goal.started_at), period.goal.timezone);
  const end = dayKey(
    new Date(new Date(period.ended_at).getTime() - 1),
    period.goal.timezone,
  );
  const thisYear = dayKey(new Date(), period.goal.timezone).slice(0, 4);
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
    ...(start.slice(0, 4) !== thisYear || end.slice(0, 4) !== thisYear
      ? { year: "numeric" as const }
      : {}),
  }).formatRange(atDay(start), atDay(end));
}
const days = (from: string, to: string) =>
  Math.round((atDay(to).getTime() - atDay(from).getTime()) / 86400000);
export function goalWeekNumber(goal: Settings, weekStart: string) {
  const start = dayKey(new Date(goal.started_at), goal.timezone);
  const monday = addDays(start, -((atDay(start).getUTCDay() + 6) % 7));
  return Math.max(1, Math.floor(days(monday, weekStart) / 7) + 1);
}
export function goalProgress(g: Settings, summary: Goal["summary"], now: Date) {
  const start = dayKey(new Date(g.started_at), g.timezone),
    today = dayKey(now, g.timezone);
  const total = g.finish_date ? days(start, g.finish_date) : null;
  const elapsed = Math.max(0, Math.min(total ?? Infinity, days(start, today)));
  const p = summary?.progress;
  const planned =
    p?.starting_weight_kg != null && p.target_weight_kg != null
      ? p.starting_weight_kg - p.target_weight_kg
      : null;
  return {
    remaining: total == null ? null : Math.max(0, total - elapsed),
    elapsed,
    time: total != null && total > 0 ? elapsed / total : null,
    weight:
      planned != null &&
      (g.phase === "bulk" ? planned < 0 : planned > 0) &&
      p?.total_lost_kg != null
        ? Math.min(1, Math.max(0, p.total_lost_kg / planned))
        : null,
  };
}
function Card({
  title,
  aside,
  headline,
  children,
  className = "",
}: {
  title: string;
  aside?: ReactNode;
  headline?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={"panel goals-card " + className}>
      <header>
        <div>
          <h2>{title}</h2>
          {headline}
        </div>
        {aside}
      </header>
      {children}
    </section>
  );
}
function ProgressRow({
  label,
  icon,
  badge,
  value,
  fraction,
  color,
}: {
  label: string;
  icon: ReactNode;
  badge?: string;
  value: string;
  fraction: number | null;
  color?: string;
}) {
  return (
    <div className="goal-progress-row">
      <div>
        <span className="goal-row-label">
          {icon}
          {label}
          {badge && <small>{badge}</small>}
        </span>
        <span>{value}</span>
      </div>
      {fraction != null && (
        <div
          className="progress-track"
          role="progressbar"
          aria-label={label}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(fraction * 100)}
        >
          <span
            style={{
              width: Math.min(100, Math.max(0, fraction * 100)) + "%",
              background: color,
            }}
          />
        </div>
      )}
    </div>
  );
}
function Progress({
  goal,
  summary,
  now,
  steps,
}: {
  goal: Settings;
  summary: Goal["summary"];
  now: Date;
  steps?: number | null;
}) {
  const p = summary?.progress,
    t = goalProgress(goal, summary, now);
  return (
    <Card title="Progress" className="goal-progress">
      {goal.phase === "maintenance" ? (
        <ProgressRow
          label="Maintaining"
          icon={<Clock size={18} />}
          value={t.elapsed + " days"}
          fraction={null}
        />
      ) : (
        <ProgressRow
          label={(p?.total_lost_kg ?? 0) < 0 ? "Weight gained" : "Weight lost"}
          icon={
            (p?.total_lost_kg ?? 0) < 0 ? (
              <ArrowUpRight size={18} />
            ) : (
              <ArrowDownRight size={18} />
            )
          }
          badge={t.weight == null ? undefined : number(t.weight * 100) + "%"}
          value={
            p?.total_lost_kg == null
              ? "—"
              : number(Math.abs(p.total_lost_kg), 1) + " kg"
          }
          fraction={t.weight}
        />
      )}
      {t.time != null && (
        <ProgressRow
          label="Time"
          icon={<Clock size={18} />}
          value={number(t.time * 100) + "%"}
          fraction={t.time}
        />
      )}
      {goal.active && goal.daily_steps_goal && steps != null && (
        <ProgressRow
          label="Steps today"
          icon={<Footprints size={18} className="goal-steps-icon" />}
          value={number(steps) + " / " + number(goal.daily_steps_goal)}
          fraction={Math.min(1, steps / goal.daily_steps_goal)}
          color="var(--blue)"
        />
      )}
      <div className="goal-values">
        <div>
          <span>{goal.phase === "maintenance" ? "Lower range" : "Start"}</span>
          <strong>
            {number(
              goal.phase === "maintenance"
                ? summary?.maintenance_lower_kg
                : p?.starting_weight_kg,
              1,
            )}{" "}
            kg
          </strong>
        </div>
        <div>
          <span>{goal.phase === "maintenance" ? "Upper range" : "Target"}</span>
          <strong>
            {goal.phase === "maintenance"
              ? number(summary?.maintenance_upper_kg, 1) + " kg"
              : p?.target_weight_kg == null
                ? "—"
                : number(p.target_weight_kg, 1) + " kg"}
          </strong>
        </div>
        {goal.finish_date && (
          <div>
            <span>Finish</span>
            <strong>{dateLabel(goal.finish_date)}</strong>
          </div>
        )}
      </div>
    </Card>
  );
}
function Modal({
  title,
  children,
  onClose,
  busy = false,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  busy?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const node = ref.current;
    const opener =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const menuTrigger = opener?.closest("details")?.querySelector("summary");
    node?.showModal();
    return () => {
      node?.close();
      const visible = (el: HTMLElement | null | undefined) =>
        el?.isConnected && el.getClientRects().length;
      const target = visible(menuTrigger)
        ? menuTrigger
        : visible(opener)
          ? opener
          : document.querySelector<HTMLElement>(
              ".goals-page .goal-options > summary, .goals-page .goal-section button",
            );
      target?.focus();
    };
  }, []);
  return (
    <dialog
      className="goal-dialog"
      ref={ref}
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) onClose();
      }}
      aria-label={title}
    >
      <header>
        <h2>{title}</h2>
        <button
          type="button"
          aria-label="Close"
          disabled={busy}
          onClick={onClose}
        >
          <X size={18} />
        </button>
      </header>
      {children}
    </dialog>
  );
}
function Editor({
  goal,
  tz,
  device,
  onClose,
  onSaved,
}: {
  goal: Settings | null;
  tz: string;
  device: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [phase, setPhase] = useState<"cut" | "bulk" | "maintenance">(
    goal?.phase ?? "cut",
  );
  const [reference, setReference] = useState(
    String(goal?.maintenance_reference_kg ?? ""),
  );
  const [range, setRange] = useState(String(goal?.maintenance_range_pct ?? 1));
  const [rate, setRate] = useState(String(goal?.weekly_loss_kg ?? 0.3));
  const [finish, setFinish] = useState(
    goal?.active
      ? (goal.finish_date ?? "")
      : addDays(dayKey(new Date(), tz), 56),
  );
  const [steps, setSteps] = useState(String(goal?.daily_steps_goal ?? ""));
  const [reminder, setReminder] = useState(goal?.reminder_enabled ?? true);
  const [weekday, setWeekday] = useState(goal?.reminder_weekday ?? 1);
  const [minute, setMinute] = useState(goal?.reminder_minute ?? 1200);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [conflict, setConflict] = useState(false);
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  async function save(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    setConflict(false);
    try {
      await api(
        endpoint(device, "weight-goal"),
        undefined,
        {
          revision: goal?.revision ?? 0,
          active: true,
          timezone: goal?.timezone ?? tz,
          phase,
          maintenance_reference_kg:
            phase === "maintenance"
              ? reference !== ""
                ? Number(reference)
                : goal?.maintenance_reference_kg != null
                  ? null
                  : undefined
              : undefined,
          maintenance_range_pct:
            phase === "maintenance" ? Number(range) : undefined,
          weekly_loss_kg: phase === "maintenance" ? 0 : Number(rate),
          finish_date: phase === "maintenance" ? null : finish || null,
          daily_steps_goal: steps === "" ? null : Number(steps),
          reminder_enabled: reminder,
          reminder_weekday: weekday,
          reminder_minute: minute,
        },
        "PUT",
      );
      if (mounted.current) onSaved();
    } catch (e) {
      if (mounted.current) {
        setError((e as Error).message);
        setConflict(e instanceof ApiError && e.status === 409);
      }
    } finally {
      if (mounted.current) setBusy(false);
    }
  }
  return (
    <Modal
      title={goal?.active ? "Edit goal" : "Start a goal"}
      onClose={onClose}
      busy={busy}
    >
      <form onSubmit={save}>
        <label htmlFor="goal-phase">Goal</label>
        <select
          id="goal-phase"
          value={phase}
          disabled={busy}
          onChange={(e) => {
            const next = e.target.value as typeof phase;
            setPhase(next);
            const same = next === (goal?.phase ?? "cut");
            setRate(
              String(
                same
                  ? (goal?.weekly_loss_kg ?? 0.3)
                  : next === "bulk"
                    ? 0.2
                    : 0.3,
              ),
            );
            setSteps(same ? String(goal?.daily_steps_goal ?? "") : "");
            setFinish(
              same
                ? (goal?.finish_date ?? "")
                : addDays(dayKey(new Date(), tz), 56),
            );
            setReference(
              same ? String(goal?.maintenance_reference_kg ?? "") : "",
            );
            setRange(same ? String(goal?.maintenance_range_pct ?? 1) : "1");
          }}
        >
          <option value="cut">Cut</option>
          <option value="bulk">Bulk</option>
          <option value="maintenance">Maintenance</option>
        </select>
        {phase === "maintenance" ? (
          <>
            <label htmlFor="goal-reference">Reference · kg</label>
            <input
              id="goal-reference"
              type="number"
              min="20"
              max="400"
              step="any"
              placeholder="Learning"
              value={reference}
              onChange={(e) => setReference(e.target.value)}
              disabled={busy}
            />
            <label htmlFor="goal-range">Range · ±%</label>
            <input
              id="goal-range"
              type="number"
              min="0.5"
              max="5"
              step="any"
              required
              value={range}
              onChange={(e) => setRange(e.target.value)}
              disabled={busy}
            />
          </>
        ) : (
          <>
            <label htmlFor="goal-rate">
              {phase === "bulk" ? "Weekly gain · kg" : "Weekly loss · kg"}
            </label>
            <input
              id="goal-rate"
              type="number"
              required
              min="0.05"
              max="1"
              step="any"
              value={rate}
              onChange={(e) => setRate(e.target.value)}
              disabled={busy}
            />
            <label htmlFor="goal-finish">Finish date</label>
            <input
              id="goal-finish"
              type="date"
              required={!goal?.active || phase !== (goal.phase ?? "cut")}
              value={finish}
              onChange={(e) => setFinish(e.target.value)}
              disabled={busy}
            />
          </>
        )}
        <label htmlFor="goal-steps">Daily steps</label>
        <input
          id="goal-steps"
          type="number"
          min="1"
          max="100000"
          step="1"
          placeholder="Off"
          value={steps}
          onChange={(e) => setSteps(e.target.value)}
          disabled={busy}
        />
        <details>
          <summary>Reminders</summary>
          <label className="goal-checkbox">
            <input
              type="checkbox"
              checked={reminder}
              onChange={(e) => setReminder(e.target.checked)}
              disabled={busy}
            />
            Weekly outlook on iPhone
          </label>
          {reminder && (
            <>
              <label htmlFor="goal-weekday">Day</label>
              <select
                id="goal-weekday"
                value={weekday}
                onChange={(e) => setWeekday(Number(e.target.value))}
                disabled={busy}
              >
                {[
                  "Sunday",
                  "Monday",
                  "Tuesday",
                  "Wednesday",
                  "Thursday",
                  "Friday",
                  "Saturday",
                ].map((d, i) => (
                  <option key={d} value={i + 1}>
                    {d}
                  </option>
                ))}
              </select>
              <label htmlFor="goal-minute">Time</label>
              <input
                id="goal-minute"
                type="time"
                required
                value={
                  String(Math.floor(minute / 60)).padStart(2, "0") +
                  ":" +
                  String(minute % 60).padStart(2, "0")
                }
                onChange={(e) => {
                  const [h, m] = e.target.value.split(":").map(Number);
                  setMinute(h * 60 + m);
                }}
                disabled={busy}
              />
            </>
          )}
        </details>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        {conflict && (
          <button type="button" className="goal-more" onClick={onSaved}>
            Discard edits and reload
          </button>
        )}
        <button className="primary goal-save" disabled={busy || conflict}>
          {busy && <LoaderCircle size={16} className="spinner" />}
          {goal?.active && (goal.phase ?? "cut") === phase
            ? "Save"
            : "Start goal"}
        </button>
      </form>
    </Modal>
  );
}
function Weekly({
  goal,
  summary,
  controls,
}: {
  goal: Settings;
  summary: Goal["summary"];
  controls?: ReactNode;
}) {
  const available = (summary?.weeks ?? []).filter(
    (w) => w.end >= dayKey(new Date(goal.started_at), goal.timezone),
  );
  const [selectedWeek, setSelectedWeek] = useState<string | null>(null);
  const matched = available.findIndex((week) => week.start === selectedWeek);
  const index = matched >= 0 ? matched : available.length - 1;
  const w = available[index];
  if (!w)
    return controls ? (
      <Card title="Weight" aside={controls} className="goal-weight">
        <p className="empty">No weekly readings</p>
      </Card>
    ) : (
      <p className="empty">No weekly readings</p>
    );
  const points = (summary?.progress?.weigh_ins ?? []).filter(
    (p) => p.day >= w.start && p.day <= w.end,
  );
  const content = (
    <>
      <div className="goal-week-nav">
        <button
          aria-label="Previous goal week"
          disabled={index <= 0}
          onClick={() => setSelectedWeek(available[index - 1].start)}
        >
          <ChevronLeft size={18} />
        </button>
        <span>Week {goalWeekNumber(goal, w.start)}</span>
        <button
          aria-label="Next goal week"
          disabled={index >= available.length - 1}
          onClick={() =>
            setSelectedWeek(
              index + 1 === available.length - 1
                ? null
                : available[index + 1].start,
            )
          }
        >
          <ChevronRight size={18} />
        </button>
      </div>
      <Chart
        data={series(
          points.map((p) => ({ day: p.day, value: p.kg })),
          w.start,
          addDays(w.end, 1),
        )}
        unit="kg"
        band={rangeBand(summary)}
      />
      {w.start === summary?.start && summary.state !== "starting" && (
        <p
          className="small"
          style={{
            color:
              summary.state === "on_pace" ? "var(--green)" : "var(--muted)",
          }}
        >
          {outlookTitle(summary.state)}
        </p>
      )}
      <div className="goal-week-stats">
        {!controls && (
          <div>
            <span>Weekly median</span>
            <strong>{number(w.median_kg, 1)} kg</strong>
          </div>
        )}
        {w.start === summary?.start && summary.trend_kg_per_week != null && (
          <div>
            <span>Pace</span>
            <strong>
              {summary.trend_kg_per_week > 0 ? "+" : ""}
              {number(summary.trend_kg_per_week, 2)} kg / week
            </strong>
          </div>
        )}
        <div>
          <span>
            {w.end < dayKey(new Date(goal.pace_started_at), goal.timezone)
              ? "Pace"
              : "Target pace"}
          </span>
          <strong>
            {w.end < dayKey(new Date(goal.pace_started_at), goal.timezone)
              ? "Previous pace"
              : goal.phase === "maintenance"
                ? "Maintain weight"
                : `${goal.phase === "bulk" ? "+" : "−"}${number(goal.weekly_loss_kg, 2)} kg / week`}
          </strong>
        </div>
      </div>
    </>
  );
  return controls ? (
    <Card
      title="Weekly median"
      headline={
        <div className="goal-current-weight">
          {number(w.median_kg, 1)} <small>kg</small>
        </div>
      }
      aside={controls}
      className="goal-weight"
    >
      {content}
    </Card>
  ) : (
    content
  );
}
export function GoalView({
  device,
  data,
  onSaved,
}: {
  device: string;
  data: Dataset;
  onSaved: () => void;
}) {
  const [refresh, setRefresh] = useState(0),
    [mode, setMode] = useState<"edit" | "end" | null>(null);
  const [chartMode, setChartMode] = useState<"phase" | "weekly">("phase");
  const pageRef = useRef<HTMLDivElement>(null);
  const previousMode = useRef(chartMode);
  useEffect(() => {
    if (previousMode.current !== chartMode) {
      pageRef.current
        ?.querySelector<HTMLButtonElement>(
          '.goal-chart-mode button[aria-pressed="true"]',
        )
        ?.focus();
      previousMode.current = chartMode;
    }
  }, [chartMode]);
  useEffect(() => {
    setCursor(null);
    setRefresh((x) => x + 1);
  }, [data.loadedAt]);
  const current = useRead<Goal>(endpoint(device, "weight-goal"), refresh);
  const response = current.data ?? data.goal,
    g = response?.goal ?? null,
    s = response?.summary ?? null;
  const [items, setItems] = useState<GoalPeriod[]>([]),
    [next, setNext] = useState<number | null>(null),
    [cursor, setCursor] = useState<number | null>(null);
  const [historyError, setHistoryError] = useState(""),
    [historyLoading, setHistoryLoading] = useState(true);
  const [selected, setSelected] = useState<number | null>(null);
  const historical = useRead<GoalPeriod>(
    selected == null ? null : endpoint(device, "weight-goals/" + selected),
    refresh,
  );
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  useEffect(() => {
    const ctrl = new AbortController();
    setHistoryLoading(true);
    setHistoryError("");
    api<History>(
      endpoint(
        device,
        "weight-goals" + (cursor == null ? "" : "?before=" + cursor),
      ),
      ctrl.signal,
    )
      .then((page) => {
        if (ctrl.signal.aborted) return;
        setItems((old) =>
          cursor == null
            ? page.items
            : [
                ...old,
                ...page.items.filter((p) => !old.some((x) => x.id === p.id)),
              ],
        );
        setNext(page.next_cursor);
      })
      .catch((e) => {
        if (!ctrl.signal.aborted) setHistoryError(e.message);
      })
      .finally(() => {
        if (!ctrl.signal.aborted) setHistoryLoading(false);
      });
    return () => ctrl.abort();
  }, [device, cursor, refresh]);
  function saved() {
    setMode(null);
    setError("");
    setCursor(null);
    setRefresh((x) => x + 1);
    onSaved();
  }
  async function end() {
    if (!g || busy) return;
    setBusy(true);
    setError("");
    try {
      await api(
        endpoint(device, "weight-goal"),
        undefined,
        { ...g, active: false },
        "PUT",
      );
      if (mounted.current) saved();
    } catch (e) {
      if (mounted.current) setError((e as Error).message);
    } finally {
      if (mounted.current) setBusy(false);
    }
  }
  const active = g?.active === true,
    now = new Date(),
    tz = g?.timezone ?? data.tz;
  const t = g ? goalProgress(g, s, now) : null;
  const rows = active
    ? (s?.progress?.weigh_ins?.map((r) => ({ day: r.day, value: r.kg })) ?? [])
    : dailyWeights(data.weights, tz).filter(
        (r) =>
          r.day >= addDays(dayKey(now, tz), -29) && r.day <= dayKey(now, tz),
      );
  const chartData = rows.length
    ? series(rows, rows[0].day, addDays(rows.at(-1)!.day, 1))
    : [];
  const chartControls = (
    <div
      className="goal-chart-mode"
      role="group"
      aria-label="Weight chart period"
    >
      <button
        aria-pressed={chartMode === "phase"}
        onClick={() => setChartMode("phase")}
      >
        Phase
      </button>
      <button
        aria-pressed={chartMode === "weekly"}
        onClick={() => setChartMode("weekly")}
      >
        Weekly
      </button>
    </div>
  );
  return (
    <div className="goals-page" ref={pageRef}>
      <div className="goal-section">
        <div className="goal-phase-label">
          <h2>{active ? phaseTitle(g) : "Maintenance"}</h2>
          {s && chartMode === "phase" && (
            <span
              className={
                "goal-status" +
                (["stable", "on_pace"].includes(s.state) ? " goal-success" : "")
              }
            >
              <span aria-hidden="true" />
              {outlookTitle(s.state)}
            </span>
          )}
        </div>
        <div className="goal-section-actions">
          {active ? (
            <>
              <span>
                {t?.remaining != null ? t.remaining + " days left" : ""}
              </span>
              <button className="goal-edit" onClick={() => setMode("edit")}>
                Edit goal
              </button>
              <details
                className={
                  "goal-options" +
                  (g?.phase === "maintenance"
                    ? " goal-options-maintenance"
                    : "")
                }
              >
                <summary aria-label="Goal options">
                  <MoreHorizontal size={20} />
                </summary>
                <div
                  onClick={(event) => {
                    const menu = event.currentTarget.closest("details");
                    menu?.querySelector("summary")?.focus();
                    menu?.removeAttribute("open");
                  }}
                >
                  <button
                    className="goal-menu-edit"
                    onClick={() => setMode("edit")}
                  >
                    Edit goal
                  </button>
                  {g?.phase !== "maintenance" && (
                    <button onClick={() => setMode("end")}>End goal</button>
                  )}
                </div>
              </details>
            </>
          ) : (
            <button
              className="primary"
              disabled={current.loading || !!current.error}
              onClick={() => setMode("edit")}
            >
              Start a goal
            </button>
          )}
        </div>
      </div>
      {current.loading && <LoadingBar label="Loading goal" />}
      {current.error && (
        <p className="error" role="alert">
          {current.error}{" "}
          <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
        </p>
      )}
      <div className={"goal-overview" + (!active ? " single" : "")}>
        {chartMode === "weekly" && active && g ? (
          <Weekly key={g.id} goal={g} summary={s} controls={chartControls} />
        ) : (
          <Card
            title="Weight"
            headline={
              <div className="goal-current-weight">
                {number(rows.at(-1)?.value, 1)} <small>kg</small>
              </div>
            }
            aside={active && chartControls}
            className="goal-weight"
          >
            <Chart
              data={chartData}
              unit="kg"
              height={200}
              latestMarker
              target={
                active && g?.phase !== "maintenance"
                  ? s?.progress?.target_weight_kg
                  : null
              }
              targetLabel="Target"
              band={rangeBand(s)}
            />
          </Card>
        )}
        {active && g && (
          <Progress
            goal={g}
            summary={s}
            now={now}
            steps={data.days.find((d) => d.day === dayKey(now, tz))?.steps}
          />
        )}
      </div>
      {(items.length > 0 || historyLoading || historyError) && (
        <Card title="Past goals" className="goal-history">
          <div className="goal-timeline">
            {items.map((p) => (
              <div key={p.id} className="goal-period">
                <button
                  onClick={() => setSelected(p.id)}
                  className="goal-period-row"
                >
                  <span className="goal-period-icon">
                    {p.goal.phase === "bulk" ? (
                      <ArrowUpRight size={18} />
                    ) : p.goal.phase === "maintenance" ? (
                      <ArrowRight size={18} />
                    ) : (
                      <ArrowDownRight size={18} />
                    )}
                  </span>
                  <span>
                    {phaseTitle(p.goal)}
                    <small
                      className={
                        goalOutcome(p) === "Target reached"
                          ? "goal-success"
                          : ""
                      }
                    >
                      <span className="goal-period-date">{periodDates(p)}</span>
                      {" · "}
                      <span className="goal-outcome">{goalOutcome(p)}</span>
                    </small>
                  </span>
                  <strong>
                    {p.summary.progress?.total_lost_kg == null
                      ? "—"
                      : new Intl.NumberFormat(undefined, {
                          maximumFractionDigits: 1,
                          signDisplay: "exceptZero",
                        }).format(-p.summary.progress.total_lost_kg) + " kg"}
                  </strong>
                  <ChevronRight
                    size={16}
                    className="goal-history-chevron"
                    aria-hidden="true"
                  />
                </button>
              </div>
            ))}
          </div>
          {historyLoading && <LoadingBar label="Loading past goals" />}
          {historyError && (
            <p className="error" role="alert">
              {historyError}{" "}
              <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
            </p>
          )}
          {next != null && (
            <button
              className="goal-more"
              disabled={historyLoading}
              onClick={() => setCursor(next)}
            >
              More goals
            </button>
          )}
        </Card>
      )}
      {mode === "edit" && (
        <Editor
          goal={g}
          tz={data.tz}
          device={device}
          onClose={() => setMode(null)}
          onSaved={saved}
        />
      )}
      {mode === "end" && (
        <Modal title="End this goal?" busy={busy} onClose={() => setMode(null)}>
          <p className="muted">Maintenance starts next. Your history stays.</p>
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <button className="primary goal-save" disabled={busy} onClick={end}>
            {busy && <LoaderCircle size={16} className="spinner" />}End goal
          </button>
          <button
            className="goal-more"
            disabled={busy}
            onClick={() => setMode(null)}
          >
            Keep going
          </button>
        </Modal>
      )}
      {selected != null && (
        <Modal
          title={historical.data ? phaseTitle(historical.data.goal) : "Goal"}
          onClose={() => setSelected(null)}
        >
          {historical.loading && <LoadingBar label="Loading past goal" />}
          {historical.error && (
            <p className="error" role="alert">
              {historical.error}
              <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
            </p>
          )}
          {historical.data && <Archived period={historical.data} />}
        </Modal>
      )}
    </div>
  );
}
function Archived({ period: p }: { period: GoalPeriod }) {
  const rows = p.summary.progress?.weigh_ins ?? [];
  return (
    <div className="goal-archive">
      <p className="muted small">{goalOutcome(p)}</p>
      <Chart
        unit="kg"
        data={
          rows.length
            ? series(
                rows.map((r) => ({ day: r.day, value: r.kg })),
                rows[0].day,
                addDays(rows.at(-1)!.day, 1),
              )
            : []
        }
        target={p.summary.progress?.target_weight_kg}
        band={rangeBand(p.summary)}
        targetLabel="Target"
        latestMarker
      />
      <Progress
        goal={{ ...p.goal, active: false }}
        summary={p.summary}
        now={new Date(new Date(p.ended_at).getTime() - 1)}
      />
      <details>
        <summary>Weekly pace</summary>
        <Weekly goal={p.goal} summary={p.summary} />
      </details>
    </div>
  );
}
