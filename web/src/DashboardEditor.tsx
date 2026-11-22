import { useEffect, useState, type ReactNode } from "react";
import { LoaderCircle, LockKeyhole, Link } from "lucide-react";
import { DashboardCanvas } from "./DashboardCanvas";
import { useDashboardPreview } from "./useDashboardPreview";
import { LoadingBar } from "./Loading";
import type { ShareConfig } from "./sharing";
export function DashboardEditor({
  device,
  config,
  change,
  busy,
  error,
  close,
  save,
  shared = false,
  children,
  accessDirty = false,
}: {
  device: string;
  config: ShareConfig;
  change: (c: Partial<ShareConfig>) => void;
  busy: boolean;
  error: string;
  close: () => void;
  save: () => void;
  shared?: boolean;
  children?: ReactNode;
  accessDirty?: boolean;
}) {
  const preview = useDashboardPreview(device, config);
  const [settings, setSettings] = useState(false);
  const [initial] = useState(() => JSON.stringify(config));
  const dirty = accessDirty || JSON.stringify(config) !== initial;
  useEffect(() => {
    const warn = (e: BeforeUnloadEvent) => {
      if (dirty) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);
  function leave(action: () => void) {
    if (!dirty || window.confirm("Discard unsaved dashboard changes?"))
      action();
  }
  return (
    <section className="dashboard-editor">
      <div className="editor-toolbar">
        <h1>Edit dashboard</h1>
        <label className="editor-destination">
          {shared ? <Link size={15} /> : <LockKeyhole size={15} />}
          <select
            aria-label="Editing dashboard"
            value={shared ? "shared" : "private"}
            disabled={busy}
            onChange={(e) =>
              leave(() => {
                close();
                location.hash =
                  e.target.value === "shared" ? "Shares" : "Today";
              })
            }
          >
            <option value="private">My dashboard</option>
            <option value="shared">
              {shared ? `${config.title} · Shared` : "Shared dashboards"}
            </option>
          </select>
        </label>
        <div className="editor-actions">
          <button disabled={busy} onClick={() => leave(close)}>
            Cancel
          </button>
          <button
            className="primary"
            disabled={
              busy ||
              preview.loading ||
              !!preview.error ||
              !config.widgets.length ||
              !config.title.trim()
            }
            onClick={save}
          >
            {busy && <LoaderCircle className="spinner" size={15} />}Save
          </button>
        </div>
      </div>
      <div className="editor-load-slot">
        {(busy || preview.loading) && (
          <LoadingBar label={busy ? "Saving dashboard" : "Loading widgets"} />
        )}
      </div>
      {(error || preview.error) && (
        <p className="error" role="alert">
          {error || preview.error}
          {preview.error && <button onClick={preview.retry}>Retry</button>}
        </p>
      )}
      {shared && settings && (
        <div className="panel editor-settings">{children}</div>
      )}
      {shared && (
        <div className="editor-sharing-scope">
          <span>
            {config.range === "all"
              ? "All history"
              : config.range === "fixed"
                ? `${config.from} – ${config.to}`
                : "Last 30 days"}
            {config.heatmap_year ? " · Heatmap: 1 year" : ""}
          </span>
          <button
            aria-expanded={settings}
            onClick={() => setSettings(!settings)}
          >
            Sharing settings
          </button>
        </div>
      )}
      <DashboardCanvas
        config={config}
        data={preview.data}
        loading={preview.loading}
        change={change}
        disabled={busy}
      />
    </section>
  );
}
