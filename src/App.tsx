import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import {
  ChevronLeft,
  ChevronRight,
  RefreshCw,
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
import { GoalView } from "./Goals";
import { LoadingBar, LoadingCards } from "./Loading";
import { BySport, TrainingHeatmap, SportIcon } from "./Training";
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
  const [signingOut, setSigningOut] = useState(false);
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
    if (signingOut) return;
    setSigningOut(true);
    try {
      await api("/v1/auth/logout", undefined, {});
      setIdentity(null);
      setDevice("");
      setMenu(false);
      location.hash = "Today";
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSigningOut(false);
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
              <button onClick={logout} disabled={signingOut}>
                {signingOut ? (
                  <LoaderCircle className="spinner" size={16} />
                ) : (
                  <LogOut size={16} />
                )}{" "}
                Sign out
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
    <div className="loading">
      <LoadingBar />
      <LoadingCards />
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
  loading = false,
}: {
  label: string;
  value: string;
  color: string;
  fraction?: number;
  loading?: boolean;
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
        <strong>
          {loading ? (
            <LoaderCircle
              className="spinner"
              size={20}
              aria-label="Loading outlook"
            />
          ) : (
            value
          )}
        </strong>
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
  const { data, loading, error, completed } = useDataset(device, refresh);
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
            <RefreshCw className={loading ? "spinner" : undefined} size={16} />
          </button>
        </div>
      </div>
      {page !== "Goals" && (
        <div className={`period-row${page === "Today" ? " today-period" : ""}`}>
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
      <div className="refresh-slot">
        {loading && <LoadingBar value={completed} total={6} />}
      </div>
      {error && data && (
        <p className="error" role="alert">
          {error}{" "}
          <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
        </p>
      )}
      {loading && !data ? (
        <LoadingCards />
      ) : error && !data ? (
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
              device={device}
              onGoalSaved={() => setRefresh((x) => x + 1)}
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
  pageSize,
}: {
  tz: string;
  rows: Session[];
  pageSize?: number;
  onDetail: (s: Session) => void;
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
          const day = dayKey(new Date(session.start_ts), tz);
          const previous =
            index > 0
              ? dayKey(new Date(visible[index - 1].start_ts), tz)
              : null;
          const today = dayKey(new Date(), tz);
          return (
            <div className="timeline-entry" key={session.id}>
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
              <button className="workout" onClick={() => onDetail(session)}>
                <span className="workout-icon">
                  <SportIcon kind={session.kind} />
                </span>
                <span className="workout-title">
                  {title(session.kind)}
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
              </button>
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
  device,
  onGoalSaved,
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
  device: string;
  onGoalSaved: () => void;
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
            loading={insightLoading}
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
        <div className="grid today-grid">
          <Panel
            title="Weight"
            aside={
              <span className="panel-value">
                {number(latest?.value, 1)} <small>kg</small>
              </span>
            }
          >
            {error("weights")}
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
                .slice(0, 3)}
              onDetail={onDetail}
            />
          </Panel>
          <Panel
            title="Steps"
            aside={<span className="panel-value">{number(daily?.steps)}</span>}
          >
            {error("days")}
            <Chart
              data={series(
                days.map((d) => ({ day: d.day, value: d.steps })),
                addDays(date, -6),
                addDays(date, 1),
              )}
              color="var(--blue)"
              bar
              unit="steps"
              target={goal?.goal?.active ? goal.goal.daily_steps_goal : null}
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
  if (page === "Activity") {
    const selectedWorkouts = workouts.filter((s) => {
      const d = dayKey(new Date(s.start_ts), tz);
      return d >= start && d < end;
    });
    return (
      <>
        <div className="section-heading">
          <h2>Training</h2>
          <span>
            {selectedWorkouts.length} workouts ·{" "}
            {duration(
              selectedWorkouts.reduce((sum, s) => sum + s.duration_s, 0),
            )}
          </span>
        </div>
        <div className="grid training-grid">
          <Panel
            title="Every day"
            wide
            aside={<span className="muted small">Past year</span>}
          >
            {error("days")}
            <TrainingHeatmap
              days={days}
              rows={workouts}
              tz={tz}
              end={dayKey(new Date(), tz)}
              onOpen={onDay}
            />
          </Panel>
          <Panel title="By sport">
            {error("workouts")}
            <BySport rows={selectedWorkouts} />
          </Panel>
          <Panel title="Recent activities">
            <Workouts
              key={`${start}:${end}`}
              pageSize={6}
              tz={tz}
              rows={selectedWorkouts}
              onDetail={onDetail}
            />
          </Panel>
          <Panel title="Daily load">
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
        </div>
      </>
    );
  }
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
      <GoalView
        key={device}
        device={device}
        data={data}
        onSaved={onGoalSaved}
      />
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
          <RefreshCw className={loading ? "spinner" : undefined} size={17} />
        </button>
      </div>
      <div className="refresh-slot">
        {loading && <LoadingBar label="Loading admin stats" />}
      </div>
      {error && (
        <p className="error" role="alert">
          {error}{" "}
          <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
        </p>
      )}
      {loading && !data ? (
        <LoadingCards />
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
