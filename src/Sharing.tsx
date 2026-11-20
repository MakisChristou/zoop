import { useEffect, useState, useRef } from "react";
import {
  ArrowUp,
  ArrowDown,
  Copy,
  Plus,
  LoaderCircle,
  ArrowLeft,
  ExternalLink,
} from "lucide-react";
import { LoadingBar } from "./Loading";
import { DashboardPreview } from "./SharedDashboard";
import {
  widgets,
  newConfig,
  sharingRequest,
  shareURL,
  type Share,
  type ShareConfig,
  type Widget,
  type PublicDashboard,
} from "./sharing";
export function Sharing({ device }: { device: string }) {
  const [list, setList] = useState<Share[]>([]),
    [editing, setEditing] = useState<Share | null | undefined>(),
    [busy, setBusy] = useState(true),
    [error, setError] = useState(""),
    [copied, setCopied] = useState<number | null>(null),
    [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const c = new AbortController();
    setBusy(true);
    setList([]);
    setError("");
    sharingRequest<Share[]>("/v1/shares", undefined, c.signal, "GET")
      .then((rows) => {
        if (!c.signal.aborted) setList(rows);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      })
      .finally(() => {
        if (!c.signal.aborted) setBusy(false);
      });
    return () => c.abort();
  }, [device, attempt]);
  async function copy(s: Share) {
    try {
      await navigator.clipboard.writeText(shareURL(s.token));
      setCopied(s.id);
    } catch {
      setError("Could not copy the link. Open it and copy the address.");
    }
  }
  if (editing !== undefined)
    return (
      <ShareEditor
        key={editing?.id ?? "new"}
        share={editing}
        device={device}
        close={() => setEditing(undefined)}
        saved={() => {
          setEditing(undefined);
          setAttempt((n) => n + 1);
        }}
      />
    );
  return (
    <section className="sharing">
      <div className="share-heading">
        <h1>Shared dashboards</h1>
        <button className="primary" onClick={() => setEditing(null)}>
          <Plus size={16} /> New dashboard
        </button>
      </div>
      {busy && <LoadingBar />}
      {error && (
        <p className="error" role="alert">
          {error}{" "}
          <button onClick={() => setAttempt((n) => n + 1)}>Try again</button>
        </p>
      )}
      {!busy && !error && !list.length && (
        <div className="panel share-empty">
          <h2>Share the metrics you choose.</h2>
          <p>Create a dashboard. Preview it before sharing.</p>
        </div>
      )}
      <div className="share-list">
        {list.map((s) => (
          <article className="panel" key={s.id}>
            <div className="share-heading">
              <div>
                <h2>{s.config.title}</h2>
                <p>
                  {!s.enabled
                    ? "Disabled"
                    : s.expires_at && Date.parse(s.expires_at) <= Date.now()
                      ? "Expired"
                      : s.password_protected
                        ? "Password protected"
                        : "Anyone with the link"}{" "}
                  ·{" "}
                  {s.config.range === "last30"
                    ? "Last 30 days"
                    : s.config.range === "all"
                      ? "All history"
                      : "Selected dates"}
                </p>
              </div>
              <button onClick={() => setEditing(s)}>Edit</button>
            </div>
            <div className="share-actions">
              <button onClick={() => copy(s)}>
                <Copy size={16} />
                {copied === s.id ? "Copied" : "Copy link"}
              </button>
              <a href={shareURL(s.token)} target="_blank" rel="noreferrer">
                <ExternalLink size={16} /> Open
              </a>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
function ShareEditor({
  share,
  device,
  close,
  saved,
}: {
  share: Share | null;
  device: string;
  close: () => void;
  saved: () => void;
}) {
  const [config, setConfig] = useState<ShareConfig>(
      share?.config ?? newConfig(),
    ),
    [password, setPassword] = useState(""),
    [changePassword, setChangePassword] = useState(false),
    [expires, setExpires] = useState(
      share?.expires_at?.slice(0, 16) ??
        (share
          ? ""
          : new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 16)),
    ),
    [enabled, setEnabled] = useState(share?.enabled ?? true),
    [preview, setPreview] = useState<PublicDashboard | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [confirmDelete, setConfirmDelete] = useState(false);
  const request = useRef<AbortController | null>(null),
    generation = useRef(0);
  useEffect(
    () => () => {
      request.current?.abort();
      generation.current++;
    },
    [],
  );
  function change(update: Partial<ShareConfig>) {
    request.current?.abort();
    generation.current++;
    setBusy(false);
    setConfig((c) => ({ ...c, ...update }));
    setPreview(null);
    setError("");
  }
  function toggle(key: Widget) {
    change({
      widgets: config.widgets.includes(key)
        ? config.widgets.filter((w) => w !== key)
        : [...config.widgets, key],
    });
  }
  function move(index: number, offset: number) {
    const next = [...config.widgets];
    [next[index], next[index + offset]] = [next[index + offset], next[index]];
    change({ widgets: next });
  }
  async function view(year?: number) {
    request.current?.abort();
    const c = new AbortController();
    request.current = c;
    const id = ++generation.current;
    setBusy(true);
    setError("");
    try {
      const d = await sharingRequest<PublicDashboard>(
        "/v1/shares/preview",
        { device_id: share?.device_id ?? device, config, year },
        c.signal,
      );
      if (id === generation.current) setPreview(d);
    } catch (e) {
      if (!c.signal.aborted) setError((e as Error).message);
    } finally {
      if (id === generation.current) setBusy(false);
    }
  }
  async function save(remove = false) {
    const c = new AbortController();
    request.current = c;
    setBusy(true);
    setError("");
    try {
      await sharingRequest(
        share ? `/v1/shares/${share.id}` : "/v1/shares",
        remove
          ? undefined
          : {
              device_id: share?.device_id ?? device,
              config,
              enabled,
              expires_at: expires
                ? new Date(expires + "Z").toISOString()
                : null,
              revision: share?.revision ?? 0,
              ...(!share || changePassword ? { password } : {}),
            },
        c.signal,
        remove ? "DELETE" : share ? "PUT" : "POST",
      );
      if (!c.signal.aborted) saved();
    } catch (e) {
      if (!c.signal.aborted) setError((e as Error).message);
    } finally {
      if (!c.signal.aborted) setBusy(false);
    }
  }
  return (
    <section className="sharing">
      <div className="share-heading">
        <button onClick={close} disabled={busy}>
          <ArrowLeft size={16} /> Back
        </button>
        <h1>{share ? "Edit dashboard" : "New dashboard"}</h1>
      </div>
      <div className="share-editor">
        <div className="panel share-controls">
          <fieldset disabled={busy}>
            <label>
              Title
              <input
                maxLength={80}
                value={config.title}
                onChange={(e) => change({ title: e.target.value })}
              />
            </label>
            <label>
              History
              <select
                aria-label="History"
                value={config.range}
                onChange={(e) =>
                  change({ range: e.target.value as ShareConfig["range"] })
                }
              >
                <option value="last30">Last 30 days</option>
                <option value="all">All history</option>
                <option value="fixed">Selected dates</option>
              </select>
            </label>
            {config.range === "fixed" && (
              <div className="share-dates">
                <label>
                  From
                  <input
                    type="date"
                    value={config.from ?? ""}
                    onChange={(e) => change({ from: e.target.value })}
                  />
                </label>
                <label>
                  To
                  <input
                    type="date"
                    value={config.to ?? ""}
                    onChange={(e) => change({ to: e.target.value })}
                  />
                </label>
              </div>
            )}
            <h2>Metrics</h2>
            <div className="share-metrics">
              {[
                ...config.widgets,
                ...(Object.keys(widgets) as Widget[]).filter(
                  (k) => !config.widgets.includes(k),
                ),
              ].map((key) => {
                const i = config.widgets.indexOf(key);
                return (
                  <div key={key}>
                    <label>
                      <input
                        type="checkbox"
                        checked={i >= 0}
                        onChange={() => toggle(key)}
                      />
                      {widgets[key].label}
                    </label>
                    {i >= 0 && (
                      <>
                        <button
                          aria-label={`Move ${widgets[key].label} up`}
                          disabled={i === 0}
                          onClick={() => move(i, -1)}
                        >
                          <ArrowUp size={14} />
                        </button>
                        <button
                          aria-label={`Move ${widgets[key].label} down`}
                          disabled={i === config.widgets.length - 1}
                          onClick={() => move(i, 1)}
                        >
                          <ArrowDown size={14} />
                        </button>
                      </>
                    )}
                  </div>
                );
              })}
            </div>
            <details>
              <summary>Identity & access</summary>
              <label>
                Display name
                <input
                  maxLength={80}
                  value={config.display_name}
                  onChange={(e) => change({ display_name: e.target.value })}
                  placeholder="Optional"
                />
              </label>
              <label className="share-check">
                <input
                  type="checkbox"
                  checked={config.show_photo}
                  onChange={(e) => change({ show_photo: e.target.checked })}
                />
                Show profile photo
              </label>
              <label>
                Expires (UTC)
                <input
                  type="datetime-local"
                  value={expires}
                  onChange={(e) => setExpires(e.target.value)}
                />
              </label>
              <button onClick={() => setExpires("")}>Never expires</button>
              {!expires && <small>No expiry</small>}
              {share?.password_protected && (
                <label className="share-check">
                  <input
                    type="checkbox"
                    checked={changePassword}
                    onChange={(e) => setChangePassword(e.target.checked)}
                  />
                  Change or remove password
                </label>
              )}
              {(!share?.password_protected || changePassword) && (
                <label>
                  Password
                  <input
                    type="password"
                    autoComplete="new-password"
                    maxLength={128}
                    value={password}
                    onChange={(e) => {
                      setPassword(e.target.value);
                      setChangePassword(true);
                    }}
                    placeholder={
                      share?.password_protected
                        ? "Leave empty to remove"
                        : "Optional · at least 8 characters"
                    }
                  />
                </label>
              )}
              {share && (
                <label className="share-check">
                  <input
                    type="checkbox"
                    checked={enabled}
                    onChange={(e) => setEnabled(e.target.checked)}
                  />
                  Link enabled
                </label>
              )}
            </details>
          </fieldset>
          <div className="share-actions">
            <button
              disabled={busy || !config.title.trim() || !config.widgets.length}
              onClick={() => view()}
            >
              Preview
            </button>
            <button
              className="primary"
              disabled={
                busy ||
                (!preview &&
                  (!share ||
                    JSON.stringify(config) !== JSON.stringify(share.config)))
              }
              onClick={() => save()}
            >
              {busy && <LoaderCircle className="spinner" size={16} />}{" "}
              {share ? "Save changes" : "Create link"}
            </button>
          </div>
          <small>
            Anyone with the link can view and copy the selected data.
          </small>
          {share && (
            <div className="share-delete">
              {confirmDelete ? (
                <>
                  <span>Delete this link?</span>
                  <button disabled={busy} onClick={() => save(true)}>
                    Delete
                  </button>
                  <button onClick={() => setConfirmDelete(false)}>
                    Cancel
                  </button>
                </>
              ) : (
                <button disabled={busy} onClick={() => setConfirmDelete(true)}>
                  Delete link
                </button>
              )}
            </div>
          )}
        </div>
        <div className="share-preview">
          <h2>Visitor preview</h2>
          {busy && <LoadingBar label="Preparing dashboard" />}
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          {preview ? (
            <DashboardPreview data={preview} onYear={view} />
          ) : (
            <div className="panel share-empty">
              Choose your metrics, then preview.
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
