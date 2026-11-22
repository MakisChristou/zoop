import { withRequestDeadline } from "./request";
import type { RecoveryDay } from "./RecoveryHistory";
import type { SleepSummary } from "./SleepTimeline";
import type { NightMetricsData } from "./NightWidgets";
import type { GoalPresentation } from "./Goals";
import type { Goal, Insights } from "./data";
import type { Placement } from "./shareLayout";
import type { SportTotal } from "./Training";
import { type Point } from "./Chart";
export const widgets = {
  daily_rings: {
    label: "Daily rings",
    detail: "Sleep, Recovery and Load",
    unit: "",
    color: "var(--sleep)",
    bar: false,
  },
  activity_heatmap: {
    label: "Every day",
    detail: "Daily Load and workouts",
    unit: "",
    color: "var(--blue)",
    bar: false,
  },
  recent_workouts: {
    label: "Recent activities",
    detail: "Type, date, duration and Load",
    unit: "",
    color: "var(--blue)",
    bar: false,
  },
  by_sport: {
    label: "By sport",
    detail: "Workout counts and durations",
    unit: "",
    color: "var(--blue)",
    bar: false,
  },
  sleep: { label: "Sleep", unit: "h", color: "var(--sleep)", bar: false },
  recovery: {
    label: "Daily recovery",
    detail: "Daily score and recovery bands",
    unit: "%",
    color: "var(--recovery-high)",
    bar: true,
  },
  load: { label: "Load", unit: "", color: "var(--blue)", bar: true },
  steps: { label: "Steps", unit: "steps", color: "var(--blue)", bar: true },
  workouts: {
    label: "Workout count",
    unit: "sessions",
    color: "var(--blue)",
    bar: true,
  },
  weight: { label: "Weight", unit: "kg", color: "var(--text)", bar: false },
  hrv: { label: "HRV", unit: "ms", color: "var(--sleep)", bar: false },
  resting_hr: {
    label: "Resting heart rate",
    unit: "bpm",
    color: "var(--text)",
    bar: false,
  },
  sleep_timeline: {
    label: "Sleep timeline",
    detail: "Last night’s stages and times",
    unit: "",
    color: "var(--sleep)",
    bar: false,
  },
  sleep_stages: {
    label: "Sleep stages",
    detail: "Deep, REM, light and awake",
    unit: "",
    color: "var(--sleep)",
    bar: false,
  },
  nightly_metrics: {
    label: "Nightly metrics",
    detail: "HRV, resting HR, efficiency and breathing",
    unit: "",
    color: "var(--text)",
    bar: false,
  },
  morning_outlook: {
    label: "Morning outlook",
    detail: "Sleep, HRV and resting HR comparisons",
    unit: "",
    color: "var(--text)",
    bar: false,
  },
  goal_progress: {
    label: "Goal progress",
    detail: "Current phase, start and target weight",
    unit: "",
    color: "var(--text)",
    bar: false,
  },
  goal_weight: {
    label: "Goal weight",
    detail: "Weights in the shared period and current goal target",
    unit: "kg",
    color: "var(--text)",
    bar: false,
  },
} as const;
export type Widget = keyof typeof widgets;
export interface ShareConfig {
  heatmap_year?: boolean;
  title: string;
  display_name: string;
  show_photo: boolean;
  range: "last30" | "all" | "fixed";
  from: string | null;
  to: string | null;
  widgets: Widget[];
  layout?: Placement[];
}
export interface Share {
  id: number;
  device_id: string;
  token: string;
  config: ShareConfig;
  enabled: boolean;
  expires_at: string | null;
  revision: number;
  password_protected: boolean;
}
export interface PublicDashboard {
  title: string;
  display_name: string;
  photo: string | null;
  timezone: string;
  from: string;
  to: string;
  paged: boolean;
  first_year: number;
  last_year: number;
  widgets: SharedWidget[];
  layout?: Placement[];
}
export interface SharedActivity {
  day: string;
  kind: string;
  duration_s: number;
  load?: number | null;
  count?: number;
}
export interface SharedWidget {
  state?: string;
  sleep_state?: string;
  night?: SleepSummary | null;
  metrics?: NightMetricsData | null;
  insight?: Insights | null;
  goal?: GoalPresentation | null;
  summary?: Goal["summary"];
  as_of?: string;

  from?: string;
  to?: string;
  day?: string;
  sleep_seconds?: number | null;
  sleep_goal_minutes?: number | null;
  load?: number | null;
  recovery?: {
    version: number;
    method: string;
    score: number | null;
    band: "low" | "moderate" | "high" | null;
    state: string;
  } | null;
  key: Widget;
  points?: {
    day: string;
    value: number | null;
    recovery?: RecoveryDay["recovery"];
  }[];
  activities?: SharedActivity[];
  sports?: SportTotal[];
}
export const newConfig = (): ShareConfig => ({
  title: "My dashboard",
  display_name: "",
  show_photo: false,
  range: "last30",
  from: null,
  to: null,
  widgets: ["daily_rings", "weight", "sleep", "recent_workouts", "steps"],
});
export function publicToken(hash: string): string | null {
  return hash.startsWith("#share/") ? hash.slice(7) : null;
}
export function shareURL(token: string): string {
  return `${location.origin}${location.pathname}#share/${token}`;
}
export function chartPoints(
  points: { day: string; value: number | null }[],
  key: Widget,
  from: string,
  to: string,
): Point[] {
  const values = new Map(points.map((p) => [p.day, p.value]));
  const result: Point[] = [];
  // Fill absent dates with null so lines never imply measurements through missing days.
  for (
    let x = Date.parse(from + "T12:00:00Z"),
      end = Date.parse(to + "T12:00:00Z");
    x <= end;
    x += 86400000
  ) {
    const day = new Date(x).toISOString().slice(0, 10),
      v = values.get(day) ?? null;
    result.push({
      day,
      x,
      value: v === null ? null : key === "sleep" ? v / 3600 : v,
    });
  }
  return result;
}
// Public requests never use account credentials or emit the private logout event.
export async function sharingRequest<T>(
  path: string,
  body?: unknown,
  signal?: AbortSignal,
  method = "POST",
  visitor = false,
): Promise<T> {
  return withRequestDeadline(signal, async (signal) => {
    const response = await fetch(path, {
      redirect: "error",
      method,
      credentials: visitor ? "omit" : "same-origin",
      cache: "no-store",
      referrerPolicy: "no-referrer",
      headers: { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
    if (!response.ok) {
      const e = new Error(
        visitor
          ? response.status === 401
            ? "Enter the dashboard password."
            : response.status === 404
              ? "This link is no longer available."
              : response.status === 429
                ? "Too many attempts. Try again in a minute."
                : "Could not load this dashboard. Try again."
          : method === "GET" || path.endsWith("/preview")
            ? "Could not load this dashboard. Try again."
            : "Could not save this change. Please try again.",
      ) as Error & { status: number };
      e.status = response.status;
      if (!visitor) {
        const detail = await response.json().catch(() => null);
        e.message = detail?.error?.message ?? e.message;
      }
      throw e;
    }
    return response.status === 204
      ? (undefined as T)
      : (response.json() as Promise<T>);
  });
}

// A pending calculation is loading, not a missing measurement. Both viewers retry it.
export function dashboardPending(data: PublicDashboard | null) {
  return !!data?.widgets.some(
    (w) =>
      w.state === "updating" ||
      w.sleep_state === "updating" ||
      ["updating", "awaiting_sync"].includes(w.insight?.state ?? "") ||
      ["updating", "awaiting_sync"].includes(w.recovery?.state ?? "") ||
      w.points?.some((p) =>
        ["updating", "awaiting_sync"].includes(p.recovery?.state ?? ""),
      ),
  );
}
