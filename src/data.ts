export interface Account {
  id: number;
  email: string;
  is_admin: boolean;
}
export interface Identity {
  account: Account;
  devices: string[];
}
export interface Day {
  day: string;
  steps: number | null;
  load: number | null;
  hr_avg: number | null;
}
// The API's raw counter includes non-walking arm movement. Match iOS everywhere
// the dashboard shows steps; missing filtered data must never fall back to raw.
export interface DayResponse extends Day {
  steps_walking?: number | null;
}
export function displayDay(row: DayResponse): Day {
  return { ...row, steps: row.steps_walking ?? null };
}
export interface SleepData {
  window: {
    asleep_s: number;
    efficiency: number | null;
    waso_s: number;
    coverage_s: number;
    time_in_bed_s: number;
  };
  physiology: {
    resting_hr: number | null;
    hrv_rmssd_ms: number | null;
    respiratory_rate: number | null;
    skin_temp_c: number | null;
    spo2_pct: number | null;
  };
  stages: { deep_s: number; rem_s: number; light_s: number; wake_s: number };
  partial?: boolean;
}
export interface Session {
  id: number;
  kind: string;
  start_ts: string;
  end_ts: string;
  duration_s: number;
  load: number | null;
  avg_hr: number | null;
  max_hr: number | null;
  kcal: number | null;
  steps: number | null;
  zones_min: number[] | null;
  sleep?: SleepData;
}
export interface Weight {
  id: string;
  measured_at: string;
  kg: number;
  source: string;
  removed: boolean;
}
export interface Goal {
  goal: null | {
    phase?: "cut" | "bulk" | "maintenance";
    maintenance_reference_kg?: number | null;
    maintenance_range_pct?: number;
    id: number;
    revision: number;
    pace_started_at: string;
    updated_at: string;
    reminder_enabled: boolean;
    reminder_weekday: number;
    reminder_minute: number;
    active: boolean;
    started_at: string;
    finish_date: string | null;
    timezone: string;
    weekly_loss_kg: number;
    daily_steps_goal: number | null;
  };
  summary: null | {
    trend_kg_per_week?: number | null;
    maintenance_lower_kg?: number | null;
    maintenance_upper_kg?: number | null;
    start?: string;
    state: string;
    week_number: number;
    median_kg: number | null;
    change_kg: number | null;
    weeks: {
      start: string;
      end: string;
      median_kg: number | null;
      count: number;
    }[];
    progress: null | {
      weigh_ins: { day: string; kg: number }[];
      finish_date: string | null;
      completed: boolean;
      starting_weight_kg: number | null;
      current_weight_kg: number | null;
      total_lost_kg: number | null;
      target_weight_kg: number | null;
    };
  };
}
export interface Insights {
  state: string;
  outlook: { state: string };
  metrics: {
    key: string;
    value?: number | null;
    comparison?: {
      delta: number | null;
      unit: string;
      signal: string | null;
    } | null;
  }[];
}
export interface AdminStats {
  pipeline: {
    database: string;
    accounts: number;
    frames_24h: number;
    pending_decode: number;
    failed_decode: number;
    pending_analysis: number;
    failed_analysis: number;
    workers: {
      name: string;
      heartbeat_at: string;
      last_success: string | null;
      paused: boolean;
      has_error: boolean;
      healthy: boolean;
    }[];
    ingestion: { hour: string; frames: number }[];
    recent_jobs: { kind: string; completed_at: string }[];
  };
  http: {
    uptime_seconds: number;
    requests_since_start: number;
    server_errors_since_start: number;
    p95_ms_recent_2048: number | null;
  };
}
export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
export async function api<T>(
  path: string,
  signal?: AbortSignal,
  body?: unknown,
  method?: "PUT" | "POST",
): Promise<T> {
  const r = await fetch(path, {
    signal,
    credentials: "same-origin",
    cache: "no-store",
    method: method ?? (body === undefined ? "GET" : "POST"),
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!r.ok) {
    if (r.status === 401 && !path.endsWith("/login"))
      window.dispatchEvent(new Event("zoop:unauthorized"));
    const e = await r.json().catch(() => null);
    throw new ApiError(
      r.status,
      e?.error?.message ?? "Could not load this data.",
    );
  }
  return r.status === 204 ? (undefined as T) : r.json();
}
export const endpoint = (device: string, suffix: string) =>
  `/v1/devices/${encodeURIComponent(device)}/${suffix}`;
export async function weights(
  device: string,
  from: string,
  to: string,
  signal: AbortSignal,
): Promise<Weight[]> {
  const all: Weight[] = [];
  let cursor = "";
  for (let page = 0; page < 100; page++) {
    const rows = await api<Weight[]>(
      endpoint(
        device,
        `weights?${new URLSearchParams({ from, to, after: cursor })}`,
      ),
      signal,
    );
    all.push(...rows);
    if (rows.length < 250)
      return all
        .filter((w) => !w.removed)
        .sort((a, b) => a.measured_at.localeCompare(b.measured_at));
    const next = rows.at(-1)!.id;
    if (next <= cursor) throw new Error("History pagination did not advance.");
    cursor = next;
  }
  throw new Error("History is too large to load. Choose a smaller range.");
}
