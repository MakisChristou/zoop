import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import {
  ChevronLeft,
  ChevronRight,
  RefreshCw,
  Dumbbell,
  Footprints,
  Activity as ActivityIcon,
  LogOut,
  Shield,
  LoaderCircle,
} from "lucide-react";
import {
  api,
  endpoint,
  type Identity,
  type Session,
  type Insights,
  type AdminStats,
} from "./data";
import { useDataset, useRead, type Dataset } from "./hooks";
import {
  bounds,
  movePeriod,
  dateLabel,
  number,
  duration,
  dayKey,
  addDays,
  atDay,
  dailyWeights,
  series,
  type Period,
} from "./calendar";
import { Chart } from "./Chart";
const pages = ["Today", "Activity", "Sleep", "Trends", "Goals"] as const;
type Page = (typeof pages)[number] | "Admin";
function currentPage(): Page {
  const p = decodeURIComponent(location.hash.slice(1));
  return [...pages, "Admin"].includes(p) ? (p as Page) : "Today";
}
export function App() {
  const [identity, setIdentity] = useState<Identity | null>(null),
    [checking, setChecking] = useState(true),
    [error, setError] = useState("");
  const [page, setPage] = useState<Page>(currentPage),
    [menu, setMenu] = useState(false),
    [device, setDevice] = useState("");
  useEffect(() => {
    const c = new AbortController();
    api<Identity>("/v1/auth/me", c.signal)
      .then(setIdentity)
      .catch((e) => {
        if (!c.signal.aborted && e.status !== 401) setError(e.message);
      })
      .finally(() => {
        if (!c.signal.aborted) setChecking(false);
      });
    return () => c.abort();
  }, []);
  useEffect(() => {
    const expired = () => {
      setIdentity(null);
      setDevice("");
      setMenu(false);
    };
    const hash = () => {
      setPage(currentPage());
      setMenu(false);
    };
    window.addEventListener("zoop:unauthorized", expired);
    window.addEventListener("hashchange", hash);
    return () => {
      window.removeEventListener("zoop:unauthorized", expired);
      window.removeEventListener("hashchange", hash);
    };
  }, []);
  async function logout() {
    try {
      await api("/v1/auth/logout", undefined, {});
      setIdentity(null);
      setDevice("");
      setMenu(false);
      location.hash = "Today";
    } catch (e) {
      setError((e as Error).message);
    }
  }
  if (checking)
    return (
      <div className="shell">
        <header>
          <a className="brand" href="#Today">
            zoop
          </a>
        </header>
        <Loading />
      </div>
    );
  if (!identity)
    return (
      <Login
        onLogin={async () => {
          setIdentity(await api<Identity>("/v1/auth/me"));
          setError("");
        }}
        connectionError={error}
      />
    );
  const selected = identity.devices.includes(device)
    ? device
    : identity.devices[0];
  return (
    <div className="shell">
      <a className="skip" href="#content">
        Skip to content
      </a>
      <header>
        <a className="brand" href="#Today">
          zoop
        </a>
        <nav aria-label="Main navigation">
          {pages.map((p) => (
            <a
              href={"#" + p}
              key={p}
              aria-current={page === p ? "page" : undefined}
            >
              {p}
            </a>
          ))}
        </nav>
        <div className="account">
          <button
            aria-label="Account menu"
            className="avatar"
            aria-expanded={menu}
            onClick={() => setMenu(!menu)}
          >
            {identity.account.email.slice(0, 2).toUpperCase()}
          </button>
          {menu && (
            <div className="menu">
              <span className="email">{identity.account.email}</span>
              {identity.account.is_admin && (
                <a href="#Admin" onClick={() => setMenu(false)}>
                  <Shield size={16} /> Admin
                </a>
              )}
              <button onClick={logout}>
                <LogOut size={16} /> Sign out
              </button>
            </div>
          )}
        </div>
      </header>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <main id="content">
        {page === "Admin" ? (
          identity.account.is_admin ? (
            <Admin />
          ) : (
            <Empty>No access to this page.</Empty>
          )
        ) : !selected ? (
          <Empty>
            No device linked yet. Ask your server administrator to link your
            strap.
          </Empty>
        ) : (
          <Dashboard
            key={selected}
            page={page}
            device={selected}
            picker={
              identity.devices.length > 1 ? (
                <label className="device-picker">
                  Device
                  <select
                    value={selected}
                    onChange={(e) => setDevice(e.target.value)}
                  >
                    {identity.devices.map((d) => (
                      <option key={d}>{d}</option>
                    ))}
                  </select>
                </label>
              ) : null
            }
          />
        )}
      </main>
      <footer>
        <span>Zoop</span>
        <span>Read-only · Your data, your server</span>
      </footer>
    </div>
  );
}
function Login({
  onLogin,
  connectionError,
}: {
  onLogin: () => Promise<void>;
  connectionError: string;
}) {
  const [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fields = new FormData(e.currentTarget);
    setBusy(true);
    setError("");
    try {
      await api("/v1/auth/login", undefined, {
        email: fields.get("email"),
        password: fields.get("password"),
      });
      await onLogin();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="shell">
      <header>
        <span className="brand">zoop</span>
      </header>
      <main className="login">
        <h1>Sign in to Zoop</h1>
        <form onSubmit={submit}>
          <label>
            Email
            <input
              name="email"
              type="email"
              autoComplete="username"
              required
              maxLength={254}
            />
          </label>
          <label>
            Password
            <input
              name="password"
              type="password"
              autoComplete="current-password"
              required
              maxLength={256}
            />
          </label>
          {(error || connectionError) && (
            <p className="error" role="alert">
              {error || connectionError}
            </p>
          )}
          <button className="primary" disabled={busy}>
            {busy ? "Signing in…" : "Sign in"}
          </button>
        </form>
        <details>
          <summary>Need access?</summary>
          <p>Ask your server administrator for an account or password reset.</p>
        </details>
      </main>
    </div>
  );
}
function Panel({
  title,
  aside,
  children,
  wide = false,
}: {
  title: string;
  aside?: ReactNode;
  children: ReactNode;
  wide?: boolean;
}) {
  return (
    <section className={"panel" + (wide ? " wide" : "")}>
      <div className="panel-head">
        <h2>{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}
function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}
function Loading() {
  return (
    <div className="loading" role="status">
      <LoaderCircle className="spinner" size={20} /> Loading your data
    </div>
  );
}
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
function Ring({
  label,
  value,
  color,
  fraction,
}: {
  label: string;
  value: string;
  color: string;
  fraction?: number;
}) {
  return (
    <div className="ring-item">
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
          {fraction != null ? (
            <circle
              cx="70"
              cy="70"
              r="61"
              fill="none"
              stroke={color}
              strokeWidth="7"
              strokeLinecap="round"
              strokeDasharray={`${383 * Math.max(0, Math.min(1, fraction))} 383`}
            />
          ) : (
            <circle cx="131" cy="70" r="4" fill={color} />
          )}
        </svg>
        <strong>{value}</strong>
      </div>
      <span>{label}</span>
    </div>
  );
}
function Dashboard({
  page,
  device,
  picker,
}: {
  page: Page;
  device: string;
  picker: ReactNode;
}) {
  const [refresh, setRefresh] = useState(0);
  const { data, loading, error } = useDataset(device, refresh);
  const [selected, setSelected] = useState(""),
    [period, setPeriod] = useState<Period>("Month"),
    [detail, setDetail] = useState<Session | null>(null);
  const tz = data?.tz ?? "UTC",
    today = dayKey(new Date(), tz),
    date = selected || today;
  const insights = useRead<Insights>(
    data
      ? endpoint(device, `days/${date}/insights?tz=${encodeURIComponent(tz)}`)
      : null,
    refresh,
  );
  const [start, end] = bounds(date, period),
    earliest = addDays(today, -365);
  const previous =
      page === "Today" || page === "Sleep"
        ? addDays(date, -1)
        : movePeriod(date, period, -1),
    next =
      page === "Today" || page === "Sleep"
        ? addDays(date, 1)
        : movePeriod(date, period, 1);
  const cycle = (n: number) => {
    setSelected(n < 0 ? previous : next);
    setDetail(null);
  };
  if (detail)
    return (
      <>
        <div className="page-head">
          <button className="text-button" onClick={() => setDetail(null)}>
            <ChevronLeft size={17} /> Back
          </button>
          <span>
            {dateLabel(dayKey(new Date(detail.start_ts), tz), {
              day: "numeric",
              month: "long",
              year: "numeric",
            })}
          </span>
        </div>
        <Panel title={title(detail.kind)}>
          <div className="metrics">
            <Metric label="Duration" value={duration(detail.duration_s)} />
            <Metric label="Load" value={number(detail.load, 1)} />
            <Metric
              label="Average heart rate"
              value={number(detail.avg_hr)}
              unit="bpm"
            />
            <Metric
              label="Peak heart rate"
              value={number(detail.max_hr)}
              unit="bpm"
            />
          </div>
        </Panel>
      </>
    );
  return (
    <>
      <div className="page-head">
        <h1>{page}</h1>
        <div className="page-controls">
          {picker}
          <button
            className="icon-button"
            onClick={() => setRefresh((x) => x + 1)}
            aria-label="Refresh data"
            disabled={loading}
          >
            <RefreshCw size={16} />
          </button>
        </div>
      </div>
      {page !== "Goals" && (
        <div className="period-row">
          <div className="date-control">
            <button
              aria-label="Previous period"
              disabled={previous < earliest}
              onClick={() => cycle(-1)}
            >
              <ChevronLeft size={18} />
            </button>
            <span>
              {page === "Today" || page === "Sleep"
                ? dateLabel(date, {
                    day: "numeric",
                    month: "long",
                    year: "numeric",
                  })
                : `${dateLabel(start)} – ${dateLabel(addDays(end, -1), { day: "numeric", month: "short", year: "numeric" })}`}
            </span>
            <button
              aria-label="Next period"
              disabled={next > today}
              onClick={() => cycle(1)}
            >
              <ChevronRight size={18} />
            </button>
          </div>
          {page !== "Today" && page !== "Sleep" && (
            <div className="periods" aria-label="Chart period">
              {(["Week", "Month", "3 months", "Year"] as Period[]).map((p) => (
                <button
                  key={p}
                  aria-pressed={period === p}
                  onClick={() => setPeriod(p)}
                >
                  {p}
                </button>
              ))}
            </div>
          )}
          {date !== today && (
            <button className="text-button" onClick={() => setSelected(today)}>
              Today
            </button>
          )}
        </div>
      )}
      {loading ? (
        <Loading />
      ) : error ? (
        <div role="alert" className="error">
          {error}{" "}
          <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
        </div>
      ) : (
        data && (
          <>
            {page === "Today" && insights.error && (
              <p role="alert" className="error small">
                Outlook unavailable. {insights.error}
              </p>
            )}
            <DataView
              page={page}
              data={data}
              date={date}
              start={start}
              end={end}
              insight={insights.data}
              insightLoading={insights.loading}
              onDetail={setDetail}
              onDay={(day) => setSelected(day)}
            />
            <p className="updated">
              Updated{" "}
              {data.loadedAt.toLocaleTimeString(undefined, {
                hour: "2-digit",
                minute: "2-digit",
              })}{" "}
              · {tz}
            </p>
          </>
        )
      )}
    </>
  );
}
function title(kind: string) {
  return (
    (
      {
        resistance: "Strength training",
        walk: "Walk",
        activity: "Activity",
        main: "Main sleep",
        nap: "Nap",
      } as Record<string, string>
    )[kind] ?? kind
  );
}
function Workouts({
  tz,
  rows,
  onDetail,
}: {
  tz: string;
  rows: Session[];
  onDetail: (s: Session) => void;
}) {
  return rows.length ? (
    <div className="timeline">
      {rows.map((s) => (
        <button className="workout" key={s.id} onClick={() => onDetail(s)}>
          <span className="workout-icon">
            {s.kind === "resistance" ? (
              <Dumbbell size={19} />
            ) : s.kind === "walk" ? (
              <Footprints size={19} />
            ) : (
              <ActivityIcon size={19} />
            )}
          </span>
          <span className="workout-title">
            {title(s.kind)}
            <small>
              {new Date(s.start_ts).toLocaleDateString(undefined, {
                timeZone: tz,
              })}{" "}
              · {duration(s.duration_s)}
            </small>
          </span>
          <span className="load-track">
            <span
              style={{ width: `${Math.min(100, ((s.load ?? 0) / 21) * 100)}%` }}
            />
          </span>
          <span>{number(s.load, 1)}</span>
        </button>
      ))}
    </div>
  ) : (
    <Empty>No workouts in this period</Empty>
  );
}
function SleepStages({
  sleep,
  tz,
}: {
  sleep: Session | undefined;
  tz: string;
}) {
  if (!sleep?.sleep) return <Empty>No sleep recorded</Empty>;
  const s = sleep.sleep;
  const stages = [
    ["Deep", s.stages.deep_s, "var(--sleep)"],
    ["REM", s.stages.rem_s, "#555f89"],
    ["Light", s.stages.light_s, "#33394d"],
    ["Awake", s.stages.wake_s, "#3b3b3b"],
  ] as const;
  const total = stages.reduce((n, [, v]) => n + v, 0);
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
              {total > 0 ? `${Math.round((v / total) * 100)}%` : ""}
            </span>
          </div>
        ))}
      </div>
      <div className="sleep-times">
        {[
          ["Asleep", sleep.start_ts],
          ["Awake", sleep.end_ts],
        ].map(([label, time]) => (
          <div key={label}>
            <span>{label}</span>
            <strong>
              {new Date(time).toLocaleTimeString(undefined, {
                timeZone: tz,
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
function DataView({
  page,
  data,
  date,
  start,
  end,
  insight,
  insightLoading,
  onDetail,
  onDay,
}: {
  page: Page;
  data: Dataset;
  date: string;
  start: string;
  end: string;
  insight: Insights | null;
  insightLoading: boolean;
  onDetail: (s: Session) => void;
  onDay: (day: string) => void;
}) {
  const { tz, days, sleeps, workouts, goal } = data;
  const main = sleeps
    .filter((s) => s.kind === "main" && s.sleep)
    .sort((a, b) => a.end_ts.localeCompare(b.end_ts));
  const night = main.find((s) => dayKey(new Date(s.end_ts), tz) === date),
    daily = days.find((d) => d.day === date);
  const sleepSeries = main.map((s) => ({
    day: dayKey(new Date(s.end_ts), tz),
    value: s.sleep!.window.asleep_s / 3600,
  }));
  const weightSeries = dailyWeights(data.weights, tz),
    latest = weightSeries.filter((w) => w.day <= date).at(-1);
  const chartStart =
      page === "Today"
        ? addDays(date, -29)
        : page === "Sleep"
          ? bounds(date, "Month")[0]
          : start,
    chartEnd =
      page === "Today"
        ? addDays(date, 1)
        : page === "Sleep"
          ? bounds(date, "Month")[1]
          : end;
  const stepSeries = series(
    days.map((d) => ({ day: d.day, value: d.steps })),
    chartStart,
    chartEnd,
  );
  const sleepChart = (
    <Chart
      data={series(sleepSeries, chartStart, chartEnd)}
      color="var(--sleep)"
      unit="h"
      onOpen={onDay}
    />
  );
  const weightChart = (
    <Chart
      data={series(weightSeries, chartStart, chartEnd)}
      unit="kg"
      target={
        goal?.goal?.active ? goal.summary?.progress?.target_weight_kg : null
      }
      onOpen={onDay}
    />
  );
  const error = (key: string) =>
    data.errors[key] ? (
      <p role="alert" className="error small">
        {data.errors[key]}
      </p>
    ) : null;
  if (page === "Today")
    return (
      <>
        <div className="rings">
          <Ring
            label="Sleep"
            value={duration(night?.sleep?.window.asleep_s)}
            color="var(--sleep)"
          />
          <Ring
            label="Outlook"
            value={insightLoading ? "…" : outlook(insight?.outlook.state)}
            color={
              insight?.outlook.state === "good"
                ? "var(--green)"
                : insight?.outlook.state === "low"
                  ? "var(--red)"
                  : "var(--muted)"
            }
          />
          <Ring
            label="Load"
            value={number(daily?.load, 1)}
            color="var(--blue)"
            fraction={daily?.load != null ? daily.load / 21 : undefined}
          />
        </div>
        <div className="grid">
          <Panel
            title="Weight"
            aside={<span className="muted small">30 days</span>}
          >
            {error("weights")}
            <p className="number">
              {number(latest?.value, 1)} <small>kg</small>
            </p>
            {weightChart}
          </Panel>
          <Panel
            title="Time asleep"
            aside={<span className="muted small">30 days</span>}
          >
            {error("sleeps")}
            {sleepChart}
          </Panel>
          <Panel title="Recent activities">
            {error("workouts")}
            <Workouts
              tz={tz}
              rows={workouts
                .filter((s) => dayKey(new Date(s.start_ts), tz) <= date)
                .slice(0, 4)}
              onDetail={onDetail}
            />
          </Panel>
          <Panel
            title="Steps"
            aside={
              goal?.goal?.daily_steps_goal ? (
                <span className="muted small">
                  Goal {number(goal.goal.daily_steps_goal)}
                </span>
              ) : null
            }
          >
            {error("days")}
            <p className="number">{number(daily?.steps)}</p>
            <Chart
              data={series(
                days.map((d) => ({ day: d.day, value: d.steps })),
                addDays(date, -6),
                addDays(date, 1),
              )}
              color="var(--blue)"
              bar
              unit="steps"
              onOpen={onDay}
            />
          </Panel>
        </div>
      </>
    );
  if (page === "Sleep")
    return (
      <div className="grid">
        <Panel title="Sleep stages">
          {error("sleeps")}
          <SleepStages sleep={night} tz={tz} />
        </Panel>
        <Panel
          title="Time asleep"
          aside={
            <span className="muted small">
              {dateLabel(date, { month: "long", year: "numeric" })}
            </span>
          }
        >
          {sleepChart}
        </Panel>
        <Panel title="Nightly metrics" wide>
          <div className="metrics">
            <Metric
              label="Resting heart rate"
              value={number(night?.sleep?.physiology.resting_hr)}
              unit="bpm"
            />
            <Metric
              label="HRV"
              value={number(night?.sleep?.physiology.hrv_rmssd_ms)}
              unit="ms"
            />
            <Metric
              label="Efficiency"
              value={
                night?.sleep?.window.efficiency != null && !night.sleep.partial
                  ? number(night.sleep.window.efficiency * 100)
                  : "—"
              }
              unit="%"
            />
            <Metric
              label="Breathing"
              value={number(night?.sleep?.physiology.respiratory_rate, 1)}
              unit="/ min"
            />
          </div>
        </Panel>
      </div>
    );
  if (page === "Activity")
    return (
      <div className="grid">
        <Panel title="Daily load">
          {error("days")}
          <Chart
            data={series(
              days.map((d) => ({ day: d.day, value: d.load })),
              start,
              end,
            )}
            color="var(--blue)"
            bar
            unit="load"
            onOpen={onDay}
          />
        </Panel>
        <Panel title="Steps">
          <Chart
            data={stepSeries}
            color="var(--blue)"
            bar
            unit="steps"
            onOpen={onDay}
          />
        </Panel>
        <Panel title="Workouts" wide>
          {error("workouts")}
          <Workouts
            tz={tz}
            rows={workouts.filter((s) => {
              const d = dayKey(new Date(s.start_ts), tz);
              return d >= start && d < end;
            })}
            onDetail={onDetail}
          />
        </Panel>
      </div>
    );
  if (page === "Trends")
    return (
      <div className="grid">
        <Panel title="Time asleep">
          {error("sleeps")}
          {sleepChart}
        </Panel>
        <Panel title="Weight">
          {error("weights")}
          {weightChart}
        </Panel>
        {(["resting_hr", "hrv_rmssd_ms"] as const).map((key, i) => (
          <Panel key={key} title={i ? "HRV" : "Resting heart rate"}>
            <Chart
              data={series(
                main.map((s) => ({
                  day: dayKey(new Date(s.end_ts), tz),
                  value: s.sleep!.physiology[key],
                })),
                start,
                end,
              )}
              unit={i ? "ms" : "bpm"}
              onOpen={onDay}
            />
          </Panel>
        ))}
      </div>
    );
  return (
    <>
      {error("goal")}
      <GoalView data={data} />
    </>
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
        no_sleep: "No sleep",
      } as Record<string, string>
    )[state ?? ""] ?? "—"
  );
}
function GoalView({ data }: { data: Dataset }) {
  const [week, setWeek] = useState<number | null>(null);
  const g = data.goal?.goal,
    s = data.goal?.summary,
    p = s?.progress;
  if (!g?.active)
    return (
      <Panel title="No active goal">
        <Empty>No active goal. Set one in the iPhone app.</Empty>
      </Panel>
    );
  const today = dayKey(new Date(), g.timezone),
    begin = dayKey(new Date(g.started_at), g.timezone),
    finish = g.finish_date;
  const daysLeft = finish
    ? Math.max(
        0,
        Math.round(
          (atDay(finish).getTime() - atDay(today).getTime()) / 86400000,
        ),
      )
    : null;
  const elapsed = finish
    ? Math.max(
        0,
        Math.min(
          100,
          ((atDay(today).getTime() - atDay(begin).getTime()) /
            (atDay(finish).getTime() - atDay(begin).getTime())) *
            100,
        ),
      )
    : null;
  const progress =
    p?.starting_weight_kg != null &&
    p.target_weight_kg != null &&
    p.current_weight_kg != null &&
    p.starting_weight_kg > p.target_weight_kg
      ? Math.max(
          0,
          Math.min(
            100,
            ((p.starting_weight_kg - p.current_weight_kg) /
              (p.starting_weight_kg - p.target_weight_kg)) *
              100,
          ),
        )
      : null;
  const allWeeks = s?.weeks.filter((w) => w.end >= begin) ?? [];
  const index = Math.min(week ?? allWeeks.length - 1, allWeeks.length - 1),
    w = allWeeks[index];
  const observations =
    p?.weigh_ins.filter((v) => w && v.day >= w.start && v.day <= w.end) ?? [];
  return (
    <div className="grid">
      <Panel
        title="Cut"
        aside={
          <span className="muted">
            {daysLeft != null ? `${daysLeft} days left` : ""}
          </span>
        }
      >
        <p className="number">
          {number(
            p?.total_lost_kg == null ? null : Math.abs(p.total_lost_kg),
            1,
          )}{" "}
          <small>kg {(p?.total_lost_kg ?? 0) < 0 ? "gained" : "lost"}</small>
        </p>
        {p?.total_lost_kg == null && (
          <p className="muted small">Waiting for weigh-ins</p>
        )}
        <div className="progress-track">
          <span style={{ width: `${progress ?? 0}%` }} />
        </div>
        <div className="spread muted small">
          <span>{number(p?.starting_weight_kg, 1)} kg</span>
          <span>Target {number(p?.target_weight_kg, 1)} kg</span>
        </div>
        {elapsed != null && (
          <div className="time-progress">
            <span className="muted small">
              Time elapsed · {number(elapsed)}%
            </span>
            <div className="progress-track">
              <span
                style={{ width: `${elapsed}%`, background: "var(--muted)" }}
              />
            </div>
          </div>
        )}
      </Panel>
      <Panel
        title="Weekly progress"
        aside={
          <div className="date-control">
            <button
              aria-label="Previous goal week"
              disabled={index <= 0}
              onClick={() => setWeek(index - 1)}
            >
              <ChevronLeft size={16} />
            </button>
            <span>Week {index + 1}</span>
            <button
              aria-label="Next goal week"
              disabled={index >= allWeeks.length - 1}
              onClick={() => setWeek(index + 1)}
            >
              <ChevronRight size={16} />
            </button>
          </div>
        }
      >
        {w ? (
          <>
            <Chart
              data={series(
                observations.map((o) => ({ day: o.day, value: o.kg })),
                w.start,
                addDays(w.end, 1),
              )}
              unit="kg"
              target={p?.target_weight_kg}
            />
            <div className="spread muted small">
              <span>Median {number(w.median_kg, 1)} kg</span>
              <span>{w.count} weigh-ins</span>
            </div>
          </>
        ) : (
          <Empty>Waiting for the first week</Empty>
        )}
      </Panel>
      {g.daily_steps_goal && (
        <Panel title="Daily steps" wide>
          <p className="number">
            {number(data.days.find((d) => d.day === today)?.steps)}{" "}
            <small>/ {number(g.daily_steps_goal)}</small>
          </p>
          <div className="progress-track">
            <span
              style={{
                width: `${Math.min(100, ((data.days.find((d) => d.day === today)?.steps ?? 0) / g.daily_steps_goal) * 100)}%`,
                background: "var(--blue)",
              }}
            />
          </div>
        </Panel>
      )}
    </div>
  );
}
function Admin() {
  const [refresh, setRefresh] = useState(0),
    { data, loading, error } = useRead<AdminStats>("/v1/admin/stats", refresh);
  return (
    <>
      <div className="page-head">
        <h1>Admin</h1>
        <button
          className="icon-button"
          aria-label="Refresh admin stats"
          onClick={() => setRefresh((x) => x + 1)}
          disabled={loading}
        >
          <RefreshCw size={17} />
        </button>
      </div>
      {loading ? (
        <Loading />
      ) : error ? (
        <p className="error" role="alert">
          {error}
        </p>
      ) : (
        data && (
          <>
            <Panel
              title="Backend"
              aside={<span className="muted small">Read-only</span>}
            >
              <div className="metrics">
                <Metric
                  label="Frames · last 24h"
                  value={number(data.pipeline.frames_24h)}
                />
                <Metric
                  label="API p95 · recent requests"
                  value={number(data.http.p95_ms_recent_2048, 1)}
                  unit="ms"
                />
                <Metric
                  label="Analysis queued"
                  value={number(data.pipeline.pending_analysis)}
                />
                <Metric
                  label="Analysis failures"
                  value={number(data.pipeline.failed_analysis)}
                />
              </div>
            </Panel>
            <div className="grid below">
              <Panel
                title="Ingestion"
                aside={<span className="muted small">Last 24 hours</span>}
              >
                <div className="metrics">
                  <Metric
                    label="Pending decode"
                    value={number(data.pipeline.pending_decode)}
                  />
                  <Metric
                    label="Decode failures"
                    value={number(data.pipeline.failed_decode)}
                  />
                </div>
                <Chart
                  bar
                  hourly
                  unit="frames"
                  color="var(--blue)"
                  data={Array.from({ length: 25 }, (_, i) => {
                    const x =
                      Math.floor(Date.now() / 3600000) * 3600000 -
                      (24 - i) * 3600000;
                    return {
                      day: new Date(x).toISOString(),
                      x,
                      value:
                        data.pipeline.ingestion.find(
                          (r) => new Date(r.hour).getTime() === x,
                        )?.frames ?? 0,
                    };
                  })}
                />
              </Panel>
              <Panel title="Services">
                <table>
                  <thead>
                    <tr>
                      <th>Service</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td>Database</td>
                      <td>{data.pipeline.database}</td>
                    </tr>
                    {["decoder", "analysis"].map((name) => {
                      const w = data.pipeline.workers.find(
                        (w) => w.name === name,
                      );
                      return (
                        <tr key={name}>
                          <td>{name === "decoder" ? "Decoder" : "Analysis"}</td>
                          <td className={w?.healthy ? "positive" : ""}>
                            {!w
                              ? "Not reported"
                              : w.paused
                                ? "Paused"
                                : w.has_error
                                  ? "Error"
                                  : w.healthy
                                    ? "Healthy"
                                    : "Stale heartbeat"}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
                <p className="muted small">
                  HTTP counters since restart ·{" "}
                  {duration(data.http.uptime_seconds)}
                </p>
                <div className="metrics below">
                  <Metric
                    label="Requests"
                    value={number(data.http.requests_since_start)}
                  />
                  <Metric
                    label="Server errors"
                    value={number(data.http.server_errors_since_start)}
                  />
                </div>
              </Panel>
              <Panel title="Recent completed jobs" wide>
                <table>
                  <thead>
                    <tr>
                      <th>Job</th>
                      <th>Completed</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.pipeline.recent_jobs.map((j, i) => (
                      <tr key={i}>
                        <td>
                          {j.kind === "sleep"
                            ? "Sleep analysis"
                            : "Workout analysis"}
                        </td>
                        <td>{new Date(j.completed_at).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {!data.pipeline.recent_jobs.length && (
                  <Empty>No completed jobs yet</Empty>
                )}
              </Panel>
            </div>
          </>
        )
      )}
    </>
  );
}
