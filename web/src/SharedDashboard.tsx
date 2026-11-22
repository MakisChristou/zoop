import { recoveryScoreReading } from "./recovery";
import { Ring } from "./Ring";
import { RecoveryRingFace } from "./RecoveryRing";
import { layoutFor, type Placement } from "./shareLayout";
import { useEffect, useState, useRef, type FormEvent } from "react";
import { BySport, TrainingHeatmap, RecentActivities } from "./Training";
import { SharedCell, visualOrder } from "./SharedGrid";
import { Chart } from "./Chart";
import { LoaderCircle } from "lucide-react";
import { LoadingBar, LoadingCards } from "./Loading";
import { dateLabel, number, duration, dayKey } from "./calendar";
import {
  chartPoints,
  sharingRequest,
  widgets,
  type PublicDashboard,
  type SharedWidget,
} from "./sharing";
export function SharedDashboard({ token }: { token: string }) {
  const [data, setData] = useState<PublicDashboard | null>(null),
    [password, setPassword] = useState(""),
    [submitted, setSubmitted] = useState(""),
    [locked, setLocked] = useState(false),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(true),
    [year, setYear] = useState<number>(),
    [attempt, setAttempt] = useState(0);
  const poll = useRef({ scope: "", count: 0 });
  useEffect(() => {
    const meta = document.createElement("meta");
    meta.name = "robots";
    meta.content = "noindex, nofollow";
    document.head.appendChild(meta);
    return () => meta.remove();
  }, []);
  useEffect(() => {
    const c = new AbortController();
    setBusy(true);
    setError("");
    sharingRequest<PublicDashboard>(
      "/v1/public/dashboard",
      { token, password: submitted, year },
      c.signal,
      "POST",
      true,
    )
      .then((d) => {
        if (!c.signal.aborted) {
          setData(d);
          setLocked(false);
        }
      })
      .catch((e) => {
        if (!c.signal.aborted) {
          if ([401, 403, 404, 410].includes(e.status)) setData(null);
          setLocked(e.status === 401);
          setError(e.message);
        }
      })
      .finally(() => {
        if (!c.signal.aborted) setBusy(false);
      });
    return () => c.abort();
  }, [token, submitted, year, attempt]);
  useEffect(() => {
    const scope = `${token}:${submitted}:${year}`;
    if (poll.current.scope !== scope) poll.current = { scope, count: 0 };
    const recovery = data?.widgets.find(
      (w) => w.key === "daily_rings",
    )?.recovery;
    if (busy || error || !pendingRecovery(recovery?.state)) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const schedule = () => {
      clearTimeout(timer);
      if (document.visibilityState !== "visible") return;
      timer = setTimeout(
        () => {
          poll.current.count++;
          setAttempt((n) => n + 1);
        },
        recovery?.state === "awaiting_sync" || poll.current.count >= 6
          ? 30_000
          : 5_000,
      );
    };
    schedule();
    document.addEventListener("visibilitychange", schedule);
    return () => {
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", schedule);
    };
  }, [data, busy, error, token, submitted, year]);
  function unlock(e: FormEvent) {
    e.preventDefault();
    setSubmitted(password);
    setAttempt((n) => n + 1);
  }
  return (
    <div className="shell shared-shell">
      <header>
        <span className="brand">zoop</span>
      </header>
      <main>
        <div className="refresh-slot">
          {busy && <LoadingBar label="Loading dashboard" />}
        </div>
        {busy && !data && !locked && <LoadingCards />}
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        {locked ? (
          <form className="panel share-unlock" onSubmit={unlock}>
            <h1>Shared dashboard</h1>
            <label>
              Password
              <input
                autoFocus
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                maxLength={128}
                required
              />
            </label>
            <button className="primary" disabled={busy}>
              {busy && (
                <LoaderCircle
                  className="spinner"
                  size={16}
                  aria-hidden="true"
                />
              )}{" "}
              Open dashboard
            </button>
          </form>
        ) : error && !busy ? (
          <button onClick={() => setAttempt((n) => n + 1)}>Try again</button>
        ) : null}
        {data && (
          <DashboardPreview data={data} onYear={setYear} loading={busy} />
        )}
      </main>
    </div>
  );
}
export function DashboardPreview({
  data,
  onYear,
  onLayout,
  loading = false,
}: {
  data: PublicDashboard;
  loading?: boolean;
  onYear: (year: number) => void;
  onLayout?: (layout: Placement[]) => void;
}) {
  const layout = layoutFor(
    data.widgets.map((w) => w.key),
    data.layout,
  );
  return (
    <section
      className={`shared-content${onLayout ? " layout-editing" : ""}`}
      aria-busy={loading}
    >
      <div className="share-heading">
        <div className="share-identity">
          {data.photo && <img src={data.photo} alt="" />}
          <div>
            <h1>{data.title}</h1>
            {data.display_name && <p>{data.display_name}</p>}
          </div>
        </div>
        {data.paged ? (
          <label>
            Year
            <select
              aria-label="Dashboard year"
              disabled={loading}
              value={Number(data.to.slice(0, 4))}
              onChange={(e) => onYear(Number(e.target.value))}
            >
              {Array.from(
                { length: data.last_year - data.first_year + 1 },
                (_, i) => data.last_year - i,
              ).map((y) => (
                <option key={y}>{y}</option>
              ))}
            </select>
          </label>
        ) : (
          <span>
            {dateLabel(data.from)} –{" "}
            {dateLabel(data.to, {
              day: "numeric",
              month: "short",
              year: "numeric",
            })}
          </span>
        )}
      </div>
      <div className="shared-grid">
        {visualOrder(data.widgets, layout).map((widget) => (
          <SharedCell
            key={`${widget.key}:${data.from}:${data.to}`}
            placement={layout.find((p) => p.key === widget.key)!}
            layout={layout}
            onMove={onLayout}
          >
            <SharedCard widget={widget} data={data} loading={loading} />
          </SharedCell>
        ))}
      </div>
    </section>
  );
}

function pendingRecovery(state?: string) {
  return state === "updating" || state === "awaiting_sync";
}

function SharedCard({
  widget,
  data,
  loading,
}: {
  widget: SharedWidget;
  data: PublicDashboard;
  loading: boolean;
}) {
  const { key, points = [] } = widget,
    meta = widgets[key];
  const rows = (widget.activities ?? []).map((row, i) => ({ ...row, key: i }));
  if (key === "daily_rings") {
    const reading = recoveryScoreReading(widget.recovery);
    const recoveryLoading = loading || widget.recovery?.state === "updating";
    return (
      <section className="shared-rings" aria-label="Daily rings">
        <div className="shared-ring-date">
          {dateLabel(widget.day ?? data.to, {
            weekday: "long",
            month: "short",
            day: "numeric",
            year: "numeric",
          })}
        </div>
        <div className="rings">
          <Ring
            loading={loading}
            label="Sleep"
            value={duration(widget.sleep_seconds)}
            color="var(--sleep)"
          />
          <div
            className="ring-item recovery-ring"
            aria-busy={recoveryLoading}
            aria-label={`Recovery: ${reading.score ?? (recoveryLoading ? "loading" : reading.waiting ? "Waiting for sync" : "No reading")}`}
          >
            <RecoveryRingFace reading={reading} loading={recoveryLoading} />
          </div>
          <Ring
            loading={loading}
            label="Load"
            value={number(widget.load, 1)}
            color="var(--blue)"
            fraction={widget.load == null ? undefined : widget.load / 21}
          />
        </div>
      </section>
    );
  }
  if (key === "activity_heatmap") {
    return (
      <section className="panel shared-widget">
        <h2>{meta.label}</h2>
        <TrainingHeatmap
          days={points.map((p) => ({ day: p.day, load: p.value }))}
          rows={rows}
          from={widget.from ?? data.from}
          calendarFrom={new Date(
            Date.parse(data.to + "T12:00:00Z") - 364 * 86400000,
          )
            .toISOString()
            .slice(0, 10)}
          end={data.to}
        />
      </section>
    );
  }
  if (key === "recent_workouts")
    return (
      <section className="panel shared-widget">
        <h2>{meta.label}</h2>
        <div className="shared-card-scroll" tabIndex={0} aria-label="Workouts">
          <RecentActivities
            rows={rows}
            today={dayKey(new Date(), data.timezone)}
            pageSize={8}
          />
        </div>
      </section>
    );
  if (key === "by_sport")
    return (
      <section className="panel shared-widget">
        <h2>{meta.label}</h2>
        <div className="shared-card-scroll" tabIndex={0} aria-label="Sports">
          <BySport totals={widget.sports ?? []} />
        </div>
      </section>
    );
  const chart = chartPoints(points, key, data.from, data.to),
    latest = chart.filter((p) => p.value !== null).at(-1);
  return (
    <section className="panel shared-widget">
      <h2>{meta.label}</h2>
      <div className="share-reading">
        <strong>
          {latest
            ? key === "sleep"
              ? duration(latest.value! * 3600)
              : number(
                  latest.value!,
                  key === "weight" || key === "load" ? 1 : 0,
                )
            : "—"}
        </strong>
        <span>{key === "sleep" ? "" : meta.unit}</span>
        {latest && <small>{dateLabel(latest.day)}</small>}
      </div>
      <Chart
        data={chart}
        color={meta.color}
        unit={meta.unit}
        bar={meta.bar}
        latestMarker
      />
    </section>
  );
}
