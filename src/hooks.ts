import { useEffect, useState } from "react";
import {
  api,
  endpoint,
  weights,
  type Day,
  type Session,
  type Weight,
  type Goal,
} from "./data";
import { addDays, dayKey } from "./calendar";
export interface Dataset {
  tz: string;
  days: Day[];
  sleeps: Session[];
  workouts: Session[];
  weights: Weight[];
  goal: Goal | null;
  errors: Record<string, string>;
  loadedAt: Date;
}
export function useDataset(device: string, refresh: number) {
  const [data, setData] = useState<Dataset | null>(null),
    [loading, setLoading] = useState(false),
    [error, setError] = useState("");
  useEffect(() => {
    const ctrl = new AbortController();
    setData(null);
    setLoading(true);
    setError("");
    (async () => {
      try {
        const profile = await api<{ tz: string } | null>(
          endpoint(device, "profile"),
          ctrl.signal,
        );
        const tz =
          profile?.tz ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
        const now = dayKey(new Date(), tz),
          from = addDays(now, -366) + "T00:00:00Z",
          to = addDays(now, 2) + "T00:00:00Z";
        const names = [
          "days",
          "sleeps",
          "workouts",
          "weights",
          "goal",
        ] as const;
        const results = await Promise.allSettled([
          api<Day[]>(
            endpoint(device, `days?limit=366&tz=${encodeURIComponent(tz)}`),
            ctrl.signal,
          ),
          api<Session[]>(
            endpoint(device, `sleep-sessions?limit=1000&from=${from}&to=${to}`),
            ctrl.signal,
          ),
          api<Session[]>(
            endpoint(device, `workouts?limit=500&from=${from}&to=${to}`),
            ctrl.signal,
          ),
          weights(device, from, to, ctrl.signal),
          api<Goal>(endpoint(device, "weight-goal"), ctrl.signal),
        ]);
        if (ctrl.signal.aborted) return;
        const errors: Record<string, string> = {};
        results.forEach((r, i) => {
          if (r.status === "rejected") errors[names[i]] = r.reason.message;
        });
        const val = <T>(i: number, fallback: T): T =>
          results[i].status === "fulfilled"
            ? (results[i].value as T)
            : fallback;
        const workouts = val<Session[]>(2, []),
          sleeps = val<Session[]>(1, []);
        if (workouts.length === 500)
          errors.workouts =
            "Only the latest 500 workouts are available in this view.";
        if (sleeps.length === 1000)
          errors.sleeps =
            "Only the latest 1,000 sleep sessions are available in this view.";
        setData({
          tz,
          days: val<Day[]>(0, []),
          sleeps,
          workouts,
          weights: val<Weight[]>(3, []),
          goal: val<Goal | null>(4, null),
          errors,
          loadedAt: new Date(),
        });
      } catch (e) {
        if (!ctrl.signal.aborted)
          setError(
            e instanceof Error ? e.message : "Could not load your data.",
          );
      } finally {
        if (!ctrl.signal.aborted) setLoading(false);
      }
    })();
    return () => ctrl.abort();
  }, [device, refresh]);
  return { data, loading, error };
}
export function useRead<T>(path: string | null, refresh = 0) {
  const [state, setState] = useState<{
    data: T | null;
    loading: boolean;
    error: string;
  }>({ data: null, loading: !!path, error: "" });
  useEffect(() => {
    const ctrl = new AbortController();
    setState({ data: null, loading: !!path, error: "" });
    if (path)
      api<T>(path, ctrl.signal)
        .then((data) => setState({ data, loading: false, error: "" }))
        .catch((e) => {
          if (!ctrl.signal.aborted)
            setState({ data: null, loading: false, error: e.message });
        });
    return () => ctrl.abort();
  }, [path, refresh]);
  return state;
}
