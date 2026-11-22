import { useEffect, useRef, useState } from "react";
import { DashboardEditor } from "./DashboardEditor";
import { DashboardPreview } from "./SharedDashboard";
import { LoadingBar } from "./Loading";
import { layoutFor } from "./shareLayout";
import { newConfig, sharingRequest, type ShareConfig } from "./sharing";
import { useDashboardPreview } from "./useDashboardPreview";
import { addDays } from "./calendar";
export interface DashboardPreference {
  config: ShareConfig | null;
  revision: number;
}
export function useDashboardPreference(device: string) {
  const [value, setValue] = useState<DashboardPreference | null>(null),
    [error, setError] = useState(""),
    [retry, setRetry] = useState(0);
  useEffect(() => {
    const c = new AbortController();
    setValue(null);
    setError("");
    sharingRequest<DashboardPreference>(
      `/v1/dashboard-layouts/${encodeURIComponent(device)}`,
      undefined,
      c.signal,
      "GET",
    )
      .then((v) => {
        if (!c.signal.aborted) setValue(v);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      });
    return () => c.abort();
  }, [device, retry]);
  return { value, setValue, error, retry: () => setRetry((n) => n + 1) };
}
export function PrivateDashboardEditor({
  device,
  preference,
  close,
  saved,
}: {
  device: string;
  preference: DashboardPreference;
  close: () => void;
  saved: (v: DashboardPreference) => void;
}) {
  const [config, setConfig] = useState(
      preference.config ?? { ...newConfig(), heatmap_year: true },
    ),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const request = useRef<AbortController | null>(null);
  useEffect(() => () => request.current?.abort(), []);
  async function save() {
    const c = new AbortController();
    request.current = c;
    setBusy(true);
    setError("");
    try {
      const v = await sharingRequest<DashboardPreference>(
        `/v1/dashboard-layouts/${encodeURIComponent(device)}`,
        { config, revision: preference.revision },
        c.signal,
        "PUT",
      );
      if (!c.signal.aborted) saved(v);
    } catch (e) {
      if (!c.signal.aborted) setError((e as Error).message);
    } finally {
      if (!c.signal.aborted) setBusy(false);
    }
  }
  return (
    <DashboardEditor
      device={device}
      config={config}
      change={(u) =>
        setConfig((c) => ({
          ...c,
          ...u,
          layout: u.widgets
            ? layoutFor(u.widgets, u.layout ?? c.layout)
            : (u.layout ?? c.layout),
        }))
      }
      busy={busy}
      error={error}
      close={close}
      save={save}
    />
  );
}
export function CustomDashboard({
  device,
  config,
  date,
  refresh,
}: {
  device: string;
  config: ShareConfig;
  date: string;
  refresh: number;
}) {
  const period = {
    ...config,
    range: "fixed" as const,
    from: addDays(date, -29),
    to: date,
  };
  const preview = useDashboardPreview(device, period, undefined, refresh);
  return (
    <>
      {preview.loading && <LoadingBar label="Loading dashboard" />}
      {preview.error && (
        <p className="error" role="alert">
          {preview.error}
          <button onClick={preview.retry}>Retry</button>
        </p>
      )}
      {preview.data && (
        <DashboardPreview
          data={{
            ...preview.data,
            layout: layoutFor(config.widgets, config.layout),
          }}
          onYear={() => {}}
          loading={preview.loading}
          hideHeading
        />
      )}
    </>
  );
}
