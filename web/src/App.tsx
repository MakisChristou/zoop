import { Sharing } from "./SharingSettings";
import { Settings, type SettingsTab } from "./Settings";
import { ConnectAgent } from "./ConnectAgent";
import { Plug } from "lucide-react";
import { AgentAuthorization } from "./AgentConnections";
import { OutlookStatus } from "./OutlookStatus";
import { SleepStages, NightMetrics } from "./NightWidgets";
import {
  useDashboardPreference,
  PrivateDashboardEditor,
  CustomDashboard,
} from "./PrivateDashboard";
import { SleepRing } from "./SleepRing";
import { Ring } from "./Ring";
import {
  useEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ChevronLeft,
  ChevronRight,
  RefreshCw,
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
import { AccountMenu } from "./AccountMenu";
import { Chart } from "./Chart";
import { SleepTimeline } from "./SleepTimeline";
import { GoalView } from "./Goals";
import { recoveryPending } from "./recovery";
import { RecoveryRing } from "./RecoveryRing";
import { RecoveryHistory } from "./RecoveryHistory";
import { stepsTarget } from "./summary";
import { LoadingBar, LoadingCards, LoadingRings } from "./Loading";
import {
  BySport,
  TrainingHeatmap,
  activityRows,
  RecentActivities,
} from "./Training";
import { SharedDashboard } from "./SharedDashboard";
import { publicToken } from "./sharing";
const pages = ["Today", "Activity", "Sleep", "Trends", "Goals"] as const;
type Page =
  | (typeof pages)[number]
  | "Admin"
  | "Shares"
  | "Agents"
  | "Settings"
  | "AgentAuthorization";
function currentPage(): Page {
  if (location.hash.startsWith("#agent-authorize?"))
    return "AgentAuthorization";
  if (location.hash === "#Settings/shares") return "Shares";
  if (location.hash.startsWith("#Settings")) return "Settings";
  const p = decodeURIComponent(location.hash.slice(1));
  return [...pages, "Admin", "Shares", "Agents"].includes(p)
    ? (p as Page)
    : "Today";
}
export function App() {
  const [token, setToken] = useState(() => publicToken(location.hash));
  useEffect(() => {
    const changed = () => setToken(publicToken(location.hash));
    window.addEventListener("hashchange", changed);
    return () => window.removeEventListener("hashchange", changed);
  }, []);
  return token !== null ? (
    <SharedDashboard key={token} token={token} />
  ) : (
    <PrivateApp />
  );
}
function PrivateApp() {
  const [identity, setIdentity] = useState<Identity | null>(null),
    [checking, setChecking] = useState(true),
    [error, setError] = useState("");
  const [connecting, setConnecting] = useState(false);
  const [settingsTab, setSettingsTab] = useState<SettingsTab>(() =>
    location.hash.endsWith("/profile")
      ? "profile"
      : location.hash.endsWith("/shares")
        ? "shares"
        : "agents",
  );
  const [signingOut, setSigningOut] = useState(false);
  const [page, setPage] = useState<Page>(currentPage),
    [device, setDevice] = useState("");
  const [agentQuery, setAgentQuery] = useState(
    () => location.hash.split("?")[1] || "",
  );
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
      setConnecting(false);
      setDevice("");
    };
    const hash = () => {
      setPage(currentPage());
      setSettingsTab(
        location.hash.endsWith("/profile")
          ? "profile"
          : location.hash.endsWith("/shares") || location.hash === "#Shares"
            ? "shares"
            : "agents",
      );
      setAgentQuery(location.hash.split("?")[1] || "");
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
      setConnecting(false);
      setDevice("");
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
  const availableDevices = identity.devices.filter(
    (d) => !identity.pending_devices?.includes(d),
  );
  const selected = availableDevices.includes(device)
    ? device
    : availableDevices[0];
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
        <button
          aria-label="Connect your agent"
          className="connect-agent-trigger"
          onClick={() => setConnecting(true)}
        >
          <Plug size={16} />
          <span>Connect your agent</span>
        </button>
        <AccountMenu
          key={identity.account.id + ":" + selected}
          account={identity.account}
          device={selected}
          signingOut={signingOut}
          logout={logout}
        />
      </header>
      {connecting && (
        <ConnectAgent
          key={identity.account.id}
          onClose={() => setConnecting(false)}
        />
      )}
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <main id="content">
        {page === "Agents" || page === "Settings" ? (
          <Settings
            key={identity.account.id + ":" + selected}
            tab={page === "Agents" ? "agents" : settingsTab}
            account={identity.account}
            devices={availableDevices}
            device={selected}
            connect={() => setConnecting(true)}
          />
        ) : page === "AgentAuthorization" ? (
          <AgentAuthorization
            devices={availableDevices}
            key={identity.account.id + ":" + selected + ":" + agentQuery}
            device={selected}
          />
        ) : page === "Admin" ? (
          identity.account.is_admin ? (
            <Admin />
          ) : (
            <Empty>No access to this page.</Empty>
          )
        ) : !selected ? (
          <section className="panel onboarding">
            <h1>Connect your iPhone</h1>
            <p>
              {identity.pending_devices?.length
                ? "Your band is linked. Open Zoop on your iPhone to upload its first recordings."
                : "Link your band from the server, then sign in on your iPhone."}
            </p>
            <button className="primary" onClick={() => location.reload()}>
              Check for recordings
            </button>
          </section>
        ) : page === "Shares" ? (
          <Sharing
            key={identity.account.id + ":" + selected}
            device={selected}
          />
        ) : (
          <Dashboard
            key={identity.account.id + ":" + selected}
            page={page}
            device={selected}
            picker={
              availableDevices.length > 1 ? (
                <label className="device-picker">
                  Device
                  <select
                    value={selected}
                    onChange={(e) => setDevice(e.target.value)}
                  >
                    {availableDevices.map((d) => (
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
  const [setup, setSetup] = useState<boolean | null>(null);
  const [checkError, setCheckError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const c = new AbortController();
    setCheckError(false);
    api<{ available: boolean }>("/v1/setup", c.signal)
      .then((status) => setSetup(status.available === true))
      .catch((e) => {
        if (c.signal.aborted) return;
        if (e.status === 404) setSetup(false);
        else setCheckError(true);
      });
    return () => c.abort();
  }, [attempt]);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fields = new FormData(e.currentTarget);
    setBusy(true);
    setError("");
    try {
      if (setup) {
        await api("/v1/setup", undefined, {
          code: fields.get("code"),
          email: fields.get("email"),
          password: fields.get("password"),
          device: fields.get("device") || null,
        });
        setSetup(false);
      }
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
        <h1>{setup ? "Set up Zoop" : "Sign in to Zoop"}</h1>
        {setup === null && !checkError && (
          <LoadingBar label="Checking server" />
        )}
        {checkError && (
          <p className="error" role="alert">
            Couldn’t check this server.{" "}
            <button type="button" onClick={() => setAttempt((n) => n + 1)}>
              Retry
            </button>
          </p>
        )}
        <form onSubmit={submit}>
          {setup && (
            <div>
              <label htmlFor="setup-code">Setup code</label>
              <input
                id="setup-code"
                name="code"
                type="password"
                autoComplete="off"
                required
                maxLength={256}
                aria-describedby="setup-code-help"
              />
              <p id="setup-code-help">From the server’s setup command.</p>
            </div>
          )}
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
              autoComplete={setup ? "new-password" : "current-password"}
              minLength={setup ? 12 : undefined}
              required
              maxLength={256}
            />
          </label>
          {setup && (
            <details>
              <summary>Connect a band (optional)</summary>
              <label>
                Strap serial
                <input name="device" autoComplete="off" maxLength={128} />
              </label>
              <p>You can assign a band later from the server.</p>
            </details>
          )}
          {(error || connectionError) && (
            <p className="error" role="alert">
              {error || connectionError}
            </p>
          )}
          <button
            className="primary"
            disabled={busy || setup === null || checkError}
          >
            {busy
              ? setup
                ? "Creating account…"
                : "Signing in…"
              : setup
                ? "Create admin account"
                : "Sign in"}
          </button>
        </form>
        {!setup && (
          <details>
            <summary>Need access?</summary>
            <p>
              Ask your server administrator for an account or password reset.
            </p>
          </details>
        )}
        {location.protocol === "http:" && (
          <p className="muted">
            HTTP connection · Use a trusted network or VPN.
          </p>
        )}
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
function Dashboard({
  page,
  device,
  picker,
}: {
  page: Page;
  device: string;
  picker: ReactNode;
}) {
  const preference = useDashboardPreference(device);
  const [editingDashboard, setEditingDashboard] = useState(false);
  const [refresh, setRefresh] = useState(0);
  const { data, loading, error, completed } = useDataset(device, refresh);
  const [selected, setSelected] = useState(""),
    [period, setPeriod] = useState<Period>("Month"),
    [detail, setDetail] = useState<Session | null>(null);
  const tz = data?.tz ?? "UTC",
    today = dayKey(new Date(), tz),
    date = selected || today;
  const [insightRefresh, setInsightRefresh] = useState(0);
  const insightPoll = useRef({ key: "", count: 0 });
  const insights = useRead<Insights>(
    data
      ? endpoint(device, `days/${date}/insights?tz=${encodeURIComponent(tz)}`)
      : null,
    refresh + insightRefresh,
  );
  useEffect(() => {
    const key = `${device}:${date}:${tz}:${refresh}`;
    if (insightPoll.current.key !== key)
      insightPoll.current = { key, count: 0 };
    if (
      page !== "Today" ||
      insights.loading ||
      insights.error ||
      !recoveryPending(insights.data)
    )
      return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const schedule = () => {
      clearTimeout(timer);
      if (document.visibilityState !== "visible") return;
      const awaiting =
        insights.data?.state === "awaiting_sync" ||
        insights.data?.recovery?.state === "awaiting_sync";
      timer = setTimeout(
        () => {
          insightPoll.current.count += 1;
          setInsightRefresh((value) => value + 1);
        },
        awaiting || insightPoll.current.count >= 6 ? 30_000 : 5_000,
      );
    };
    schedule();
    document.addEventListener("visibilitychange", schedule);
    return () => {
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", schedule);
    };
  }, [
    device,
    date,
    tz,
    refresh,
    page,
    insights.data,
    insights.loading,
    insights.error,
  ]);
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
  if (page === "Today" && editingDashboard && preference.value)
    return (
      <PrivateDashboardEditor
        device={device}
        preference={preference.value}
        close={() => setEditingDashboard(false)}
        saved={(v) => {
          preference.setValue(v);
          setEditingDashboard(false);
        }}
      />
    );
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
        {detail.sleep ? (
          <div className="grid">
            <SleepTimeline sleep={detail} tz={tz} />
            <Panel title="Sleep stages">
              <SleepStages sleep={detail} tz={tz} />
            </Panel>
          </div>
        ) : (
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
        )}
      </>
    );
  return (
    <>
      <div className="page-head">
        <h1>{page}</h1>
        <div className="page-controls">
          {picker}
          {page === "Today" && (
            <button
              disabled={!preference.value}
              onClick={() => setEditingDashboard(true)}
            >
              Edit dashboard
            </button>
          )}
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
      {page === "Today" && preference.error && (
        <p className="error" role="alert">
          Could not load your layout.{" "}
          <button onClick={preference.retry}>Retry layout</button>
        </p>
      )}
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
        {loading && <LoadingBar value={completed} total={7} />}
      </div>
      {error && data && (
        <p className="error" role="alert">
          {error}{" "}
          <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
        </p>
      )}
      {loading && !data ? (
        <>
          {page === "Today" && <LoadingRings />}
          <LoadingCards />
        </>
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
                Morning data unavailable. {insights.error}
              </p>
            )}
            {page === "Today" && preference.value?.config ? (
              <CustomDashboard
                key={date}
                device={device}
                config={preference.value.config}
                date={date}
                refresh={refresh + insightRefresh}
              />
            ) : (
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
                dataLoading={loading}
                onDetail={setDetail}
                onDay={(day) => setSelected(day)}
              />
            )}
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
  return (
    <RecentActivities
      rows={activityRows(rows, tz).map((r) => ({ ...r, label: title(r.kind) }))}
      today={dayKey(new Date(), tz)}
      pageSize={pageSize}
      onDetail={(row) => {
        const session = rows.find((s) => s.id === row.key);
        if (session) onDetail(session);
      }}
    />
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
  dataLoading,
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
  dataLoading: boolean;
  onDetail: (s: Session) => void;
  onDay: (day: string) => void;
}) {
  const { tz, days, sleeps, workouts, goal } = data;
  const stepTarget = stepsTarget(goal?.goal ?? null, date, tz);
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
          <SleepRing
            loading={dataLoading}
            seconds={night?.sleep?.window.asleep_s}
            goalMinutes={data.sleepGoal?.minutes}
          />
          <RecoveryRing
            key={`${device}:${date}:${tz}`}
            insight={insight}
            loading={insightLoading || dataLoading}
          />
          <Ring
            loading={dataLoading}
            label="Load"
            value={number(daily?.load, 1)}
            color="var(--blue)"
            fraction={daily?.load != null ? daily.load / 21 : undefined}
          />
        </div>
        {error("sleepGoal")}
        <OutlookStatus key={date} insight={insight} loading={insightLoading} />
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
              target={stepTarget}
              onOpen={onDay}
            />
          </Panel>
        </div>
      </>
    );
  if (page === "Sleep")
    return (
      <div className="grid sleep-grid">
        <div className="sleep-night-slot">
          {error("sleeps")}
          <SleepTimeline
            sleep={night}
            tz={tz}
            onOpen={night ? () => onDetail(night) : undefined}
          />
        </div>
        <Panel title="Sleep stages">
          {error("sleeps")}
          <SleepStages sleep={night} tz={tz} />
        </Panel>
        <Panel
          title="Sleep duration"
          aside={
            <span className="muted small">
              {dateLabel(date, { month: "long", year: "numeric" })}
            </span>
          }
        >
          {sleepChart}
        </Panel>
        <Panel title="Nightly metrics" wide>
          <NightMetrics
            metrics={
              night?.sleep
                ? {
                    ...night.sleep.physiology,
                    efficiency: night.sleep.window.efficiency,
                    partial: night.sleep.partial,
                  }
                : undefined
            }
          />
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
              rows={activityRows(workouts, tz)}
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
        <RecoveryHistory
          key={device}
          device={device}
          date={date}
          tz={tz}
          refresh={data.loadedAt.getTime()}
        />
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
      <GoalView
        key={device}
        device={device}
        data={data}
        onSaved={onGoalSaved}
      />
    </>
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
