import { RecoveryCard } from "./RecoveryHistory";
import { SleepTimeline } from "./SleepTimeline";
import { SleepStages, NightMetrics } from "./NightWidgets";
import { OutlookStatus } from "./OutlookStatus";
import { GoalProgressCard, GoalWeightCard } from "./Goals";
import { SleepRing } from "./SleepRing";
import { recoveryScoreReading } from "./recovery";
import { Ring } from "./Ring";
import { RecoveryRingFace } from "./RecoveryRing";
import { layoutFor } from "./shareLayout";
import { memo, useEffect, useState, useRef, type FormEvent } from "react";
import { BySport, TrainingHeatmap, RecentActivities } from "./Training";
import { SharedCell, visualOrder } from "./SharedGrid";
import { Chart } from "./Chart";
import { LoaderCircle } from "lucide-react";
import { LoadingBar, LoadingCards } from "./Loading";
import { dateLabel, number, duration, dayKey } from "./calendar";
import {
  chartPoints,
  dashboardPending,
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
    if (busy || error || !dashboardPending(data)) return;
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
  loading = false,
  hideHeading = false,
}: {
  data: PublicDashboard;
  loading?: boolean;
  onYear: (year: number) => void;
  hideHeading?: boolean;
}) {
  const layout = layoutFor(
    data.widgets.map((w) => w.key),
    data.layout,
  );
  return (
    <section className="shared-content" aria-busy={loading}>
      {!hideHeading && (
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
      )}
      <div className="shared-grid">
        {visualOrder(data.widgets, layout).map((widget) => (
          <SharedCell
            key={`${widget.key}:${data.from}:${data.to}`}
            placement={layout.find((p) => p.key === widget.key)!}
          >
            <SharedCard
              widget={widget}
              data={data}
              loading={loading}
              hideRingDate={hideHeading}
            />
          </SharedCell>
        ))}
      </div>
    </section>
  );
}

export const SharedCard = memo(function SharedCard({
  widget,
  data,
  loading,
  hideRingDate = false,
}: {
  widget: SharedWidget;
  data: PublicDashboard;
  loading: boolean;
  hideRingDate?: boolean;
}) {
  const { key, points = [] } = widget,
    meta = widgets[key];
  const rows = (widget.activities ?? []).map((row, i) => ({ ...row, key: i }));
  if (
    ["sleep_timeline", "sleep_stages", "nightly_metrics"].includes(key) &&
    widget.state === "updating"
  )
    return (
      <section className="panel shared-widget">
        <h2>{meta.label}</h2>
        <LoadingBar label={`Updating ${meta.label.toLowerCase()}`} />
      </section>
    );
  if (key === "sleep_timeline")
    return (
      <SleepTimeline sleep={widget.night ?? undefined} tz={data.timezone} />
    );
  if (key === "sleep_stages")
    return (
      <section className="panel shared-widget">
        <h2>Sleep stages</h2>
        <SleepStages sleep={widget.night ?? undefined} tz={data.timezone} />
      </section>
    );
  if (key === "nightly_metrics")
    return (
      <section className="panel shared-widget">
        <h2>Nightly metrics</h2>
        <NightMetrics metrics={widget.metrics} />
      </section>
    );
  if (key === "morning_outlook")
    return (
      <section className="panel shared-widget">
        <OutlookStatus
          insight={widget.insight ?? null}
          loading={loading || widget.insight?.state === "updating"}
          privateLink={false}
        />
      </section>
    );
  if (key === "goal_progress" || key === "goal_weight") {
    if (!widget.goal)
      return (
        <section className="panel shared-widget">
          <h2>{meta.label}</h2>
          <p className="empty">No goal for this period</p>
        </section>
      );
    if (key === "goal_progress")
      return (
        <GoalProgressCard
          goal={widget.goal}
          summary={widget.summary ?? null}
          now={new Date(widget.as_of ?? data.to + "T12:00:00Z")}
        />
      );
    const readings = widget.summary?.progress?.weigh_ins ?? [];
    const summary = widget.summary;
    return (
      <GoalWeightCard
        points={chartPoints(
          readings.map((r) => ({ day: r.day, value: r.kg })),
          key,
          data.from,
          data.to,
        )}
        value={readings.at(-1)?.kg}
        target={
          widget.goal.phase === "maintenance"
            ? null
            : summary?.progress?.target_weight_kg
        }
        band={
          summary?.maintenance_lower_kg != null &&
          summary.maintenance_upper_kg != null
            ? [summary.maintenance_lower_kg, summary.maintenance_upper_kg]
            : null
        }
      />
    );
  }
  if (key === "recovery") {
    const hrv = data.widgets.find((w) => w.key === "hrv"),
      rhr = data.widgets.find((w) => w.key === "resting_hr");
    const rows = points.flatMap((p) =>
      p.recovery
        ? [
            {
              day: p.day,
              recovery: p.recovery,
              ...(hrv
                ? {
                    hrv_ms:
                      hrv.points?.find((v) => v.day === p.day)?.value ?? null,
                  }
                : {}),
              ...(rhr
                ? {
                    resting_hr:
                      rhr.points?.find((v) => v.day === p.day)?.value ?? null,
                  }
                : {}),
            },
          ]
        : [],
    );
    return (
      <RecoveryCard
        rows={rows}
        from={data.from}
        days={
          Math.round((Date.parse(data.to) - Date.parse(data.from)) / 86400000) +
          1
        }
        loading={loading}
      />
    );
  }
  if (key === "daily_rings") {
    const reading = recoveryScoreReading(widget.recovery);
    const recoveryLoading = loading || widget.recovery?.state === "updating";
    return (
      <section className="shared-rings" aria-label="Daily rings">
        {!hideRingDate && (
          <div className="shared-ring-date">
            {dateLabel(widget.day ?? data.to, {
              weekday: "long",
              month: "short",
              day: "numeric",
              year: "numeric",
            })}
          </div>
        )}
        <div className="rings">
          <SleepRing
            loading={loading || widget.sleep_state === "updating"}
            seconds={widget.sleep_seconds}
            goalMinutes={widget.sleep_goal_minutes}
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
});
