import { useEffect, useState, useRef } from "react";
import {
  sharingRequest,
  dashboardPending,
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
  const poll = useRef({ scope: "", count: 0 });
  useEffect(() => {
    if (poll.current.scope !== scope) poll.current = { scope, count: 0 };
    if (
      result.scope !== scope ||
      result.loading ||
      result.error ||
      !dashboardPending(result.data)
    )
      return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const schedule = () => {
      clearTimeout(timer);
      if (document.visibilityState !== "visible") return;
      timer = setTimeout(
        () => {
          poll.current.count++;
          setRetry((n) => n + 1);
        },
        poll.current.count < 6 ? 5000 : 30000,
      );
    };
    schedule();
    document.addEventListener("visibilitychange", schedule);
    return () => {
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", schedule);
    };
  }, [scope, result]);
  const current = result.scope === scope;
  return {
    data: current ? result.data : null,
    loading: !current || result.loading,
    error: current ? result.error : "",
    retry: () => setRetry((n) => n + 1),
  };
}
