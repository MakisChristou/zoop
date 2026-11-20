import { useEffect, useState, type FormEvent } from "react";
import { BySport, TrainingHeatmap, RecentActivities } from "./Training";
import { SharedCell } from "./SharedGrid";
import { Chart } from "./Chart";
import { LoadingBar } from "./Loading";
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
    setData(null);
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
          setLocked(e.status === 401);
          setError(e.message);
        }
      })
      .finally(() => {
        if (!c.signal.aborted) setBusy(false);
      });
    return () => c.abort();
  }, [token, submitted, year, attempt]);
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
        {busy && <LoadingBar label="Loading dashboard" />}
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
              Open dashboard
            </button>
          </form>
        ) : error && !busy ? (
          <button onClick={() => setAttempt((n) => n + 1)}>Try again</button>
        ) : null}
        {data && <DashboardPreview data={data} onYear={setYear} />}
      </main>
    </div>
  );
}
export function DashboardPreview({
  data,
  onYear,
}: {
  data: PublicDashboard;
  onYear: (year: number) => void;
}) {
  return (
    <section className="shared-content">
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
        {data.widgets.map((widget) => (
          <SharedCell
            key={`${widget.key}:${data.from}:${data.to}`}
            wide={
              widget.key === "activity_heatmap" &&
              (Date.parse(data.to) - Date.parse(data.from)) / 86400000 > 90
            }
          >
            <SharedCard widget={widget} data={data} />
          </SharedCell>
        ))}
      </div>
    </section>
  );
}

function SharedCard({
  widget,
  data,
}: {
  widget: SharedWidget;
  data: PublicDashboard;
}) {
  const { key, points = [] } = widget,
    meta = widgets[key];
  const rows = (widget.activities ?? []).map((row, i) => ({ ...row, key: i }));
  if (key === "activity_heatmap") {
    return (
      <section className="panel shared-widget">
        <h2>{meta.label}</h2>
        <TrainingHeatmap
          days={points.map((p) => ({ day: p.day, load: p.value }))}
          rows={rows}
          from={data.from}
          end={data.to}
        />
      </section>
    );
  }
  if (key === "recent_workouts")
    return (
      <section className="panel shared-widget">
        <h2>{meta.label}</h2>
        <RecentActivities
          rows={rows}
          today={dayKey(new Date(), data.timezone)}
          pageSize={8}
        />
      </section>
    );
  if (key === "by_sport")
    return (
      <section className="panel shared-widget">
        <h2>{meta.label}</h2>
        <BySport totals={widget.sports ?? []} />
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
