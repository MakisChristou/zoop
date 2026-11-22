import { layoutFor } from "./shareLayout";
import { DashboardEditor } from "./DashboardEditor";
import { useEffect, useState, useRef } from "react";
import { Copy, Plus, ExternalLink } from "lucide-react";
import { LoadingBar } from "./Loading";
import {
  newConfig,
  sharingRequest,
  shareURL,
  type Share,
  type ShareConfig,
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
          <p>Choose what appears on your link.</p>
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
  );
  const [password, setPassword] = useState(""),
    [changePassword, setChangePassword] = useState(false);
  const [expires, setExpires] = useState(
    share?.expires_at?.slice(0, 16) ??
      (share
        ? ""
        : new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 16)),
  );
  const [enabled, setEnabled] = useState(share?.enabled ?? true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [confirmDelete, setConfirmDelete] = useState(false);
  const [initialAccess] = useState(() => JSON.stringify({ expires, enabled }));
  const request = useRef<AbortController | null>(null);
  useEffect(() => () => request.current?.abort(), []);
  function change(update: Partial<ShareConfig>) {
    setConfig((c) => ({
      ...c,
      ...update,
      layout: update.widgets
        ? layoutFor(update.widgets, update.layout ?? c.layout)
        : (update.layout ?? c.layout),
    }));
  }
  async function save(remove = false) {
    request.current?.abort();
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
    <DashboardEditor
      device={share?.device_id ?? device}
      config={config}
      change={change}
      busy={busy}
      error={error}
      close={close}
      save={() => save()}
      shared
      accessDirty={
        changePassword || JSON.stringify({ expires, enabled }) !== initialAccess
      }
    >
      <fieldset disabled={busy} className="share-controls">
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
        {config.widgets.includes("activity_heatmap") && (
          <label>
            Heatmap history
            <select
              aria-label="Heatmap history"
              value={config.heatmap_year ? "year" : "dashboard"}
              onChange={(e) =>
                change({ heatmap_year: e.target.value === "year" })
              }
            >
              <option value="dashboard">Dashboard period</option>
              <option value="year">1 year</option>
            </select>
          </label>
        )}
        <div className="share-access">
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
        </div>
      </fieldset>
      <small>Anyone with the link can view and copy the selected data.</small>
      {share && (
        <div className="share-delete">
          {confirmDelete ? (
            <>
              <span>Delete this link?</span>
              <button disabled={busy} onClick={() => save(true)}>
                Delete
              </button>
              <button onClick={() => setConfirmDelete(false)}>
                Cancel deletion
              </button>
            </>
          ) : (
            <button disabled={busy} onClick={() => setConfirmDelete(true)}>
              Delete link
            </button>
          )}
        </div>
      )}
    </DashboardEditor>
  );
}
