import { useDashboardRefresh } from "./useDashboardRefresh";
import { useEffect, useState } from "react";
import {
  sharingRequest,
  type ShareConfig,
  type PublicDashboard,
} from "./sharing";
// Layout-only changes never refetch health data. Scope changes clear stale projections.
export function useDashboardPreview(
  device: string,
  config: ShareConfig,
  year?: number,
  refresh = 0,
) {
  const scope = JSON.stringify({
    device_id: device,
    config: { ...config, widgets: [...config.widgets].sort(), layout: [] },
    year,
  });
  const [result, setResult] = useState<{
    scope: string;
    data: PublicDashboard | null;
    error: string;
    loading: boolean;
  }>({ scope: "", data: null, error: "", loading: true });
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    const c = new AbortController();
    if (!JSON.parse(scope).config.widgets.length) {
      setResult({ scope, data: null, error: "", loading: false });
      return;
    }
    setResult((p) => ({
      scope,
      data: p.scope === scope ? p.data : null,
      error: "",
      loading: true,
    }));
    const timer = setTimeout(() => {
      sharingRequest<PublicDashboard>(
        "/v1/shares/preview",
        JSON.parse(scope),
        c.signal,
      )
        .then((data) => {
          if (!c.signal.aborted)
            setResult({ scope, data, error: "", loading: false });
        })
        .catch((e) => {
          if (!c.signal.aborted)
            setResult((p) => ({ ...p, error: e.message, loading: false }));
        });
    }, 180);
    return () => {
      clearTimeout(timer);
      c.abort();
    };
  }, [scope, refresh, retry]);
  useDashboardRefresh(
    scope,
    result.scope === scope ? result.data : null,
    result.loading,
    result.error,
    () => setRetry((n) => n + 1),
  );
  const current = result.scope === scope;
  return {
    data: current ? result.data : null,
    loading: !current || result.loading,
    error: current ? result.error : "",
    retry: () => setRetry((n) => n + 1),
  };
}
