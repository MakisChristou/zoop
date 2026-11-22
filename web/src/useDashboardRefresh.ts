import { useEffect, useRef } from "react";
import { dayKey } from "./calendar";
import { dashboardPending, type PublicDashboard } from "./sharing";

// Private previews and public visitors follow one refresh policy. Keep completed
// readings visible; never retry a save or a password submission automatically.
export function useDashboardRefresh(
  scope: string,
  data: PublicDashboard | null,
  busy: boolean,
  error: string,
  refresh: () => void,
) {
  const callback = useRef(refresh);
  callback.current = refresh;
  const poll = useRef({ scope, count: 0 });
  useEffect(() => {
    if (poll.current.scope !== scope) poll.current = { scope, count: 0 };
    if (busy || !data) return;
    const today = dayKey(new Date(), data.timezone);
    // Old waiting observations should not cause a fast polling loop forever.
    const current = data.to >= today;
    const calculating =
      !error &&
      data.widgets.some(
        (w) =>
          w.state === "updating" ||
          w.sleep_state === "updating" ||
          w.insight?.state === "updating" ||
          w.recovery?.state === "updating" ||
          w.points?.some(
            (p) => p.day === data.to && p.recovery?.state === "updating",
          ),
      );
    const pending =
      calculating || (!error && current && dashboardPending(data));
    if (!pending) poll.current.count = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const schedule = () => {
      clearTimeout(timer);
      if (document.visibilityState !== "visible") return;
      timer = setTimeout(
        () => {
          if (
            current ||
            pending ||
            today !== dayKey(new Date(), data.timezone)
          ) {
            poll.current.count++;
            callback.current();
          } else schedule();
        },
        calculating && poll.current.count < 6
          ? 5_000
          : pending
            ? 30_000
            : 60_000,
      );
    };
    const visible = () => {
      clearTimeout(timer);
      if (document.visibilityState === "visible") callback.current();
    };
    schedule();
    document.addEventListener("visibilitychange", visible);
    return () => {
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [scope, data, busy, error]);
}
