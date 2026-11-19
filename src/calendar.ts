export type Period = "Week" | "Month" | "3 months" | "Year";
export function dayKey(date: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  return ["year", "month", "day"]
    .map((type) => parts.find((p) => p.type === type)!.value)
    .join("-");
}
export const atDay = (key: string) => new Date(`${key}T12:00:00Z`);
export const addDays = (key: string, n: number) => {
  const d = atDay(key);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
export function bounds(key: string, period: Period): [string, string] {
  const d = atDay(key);
  if (period === "Week") {
    const start = addDays(key, -((d.getUTCDay() + 6) % 7));
    return [start, addDays(start, 7)];
  }
  const month =
    period === "Year"
      ? 0
      : period === "3 months"
        ? Math.floor(d.getUTCMonth() / 3) * 3
        : d.getUTCMonth();
  const start = new Date(Date.UTC(d.getUTCFullYear(), month, 1, 12));
  const end = new Date(start);
  end.setUTCMonth(
    month + (period === "Year" ? 12 : period === "3 months" ? 3 : 1),
  );
  return [start.toISOString().slice(0, 10), end.toISOString().slice(0, 10)];
}
export function movePeriod(key: string, period: Period, n: number) {
  const [start] = bounds(key, period);
  if (period === "Week") return addDays(start, 7 * n);
  const d = atDay(start);
  d.setUTCMonth(
    d.getUTCMonth() +
      n * (period === "Year" ? 12 : period === "3 months" ? 3 : 1),
  );
  return d.toISOString().slice(0, 10);
}
export function dateLabel(
  key: string,
  opts: Intl.DateTimeFormatOptions = { day: "numeric", month: "short" },
) {
  return atDay(key).toLocaleDateString(undefined, { ...opts, timeZone: "UTC" });
}
export function duration(seconds: number | null | undefined) {
  if (seconds == null) return "—";
  const m = Math.round(seconds / 60);
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;
}
export function number(value: number | null | undefined, digits = 0) {
  return value == null || !Number.isFinite(value)
    ? "—"
    : value.toLocaleString(undefined, { maximumFractionDigits: digits });
}
export function dailyWeights<
  T extends { measured_at: string; kg: number; source: string; id?: string },
>(rows: T[], tz: string) {
  const out = new Map<string, T>();
  for (const row of rows) {
    const key = dayKey(new Date(row.measured_at), tz),
      old = out.get(key);
    if (
      !old ||
      (row.source === "health" && old.source !== "health") ||
      ((row.source === "health") === (old.source === "health") &&
        (row.measured_at > old.measured_at ||
          (row.measured_at === old.measured_at &&
            (row.id ?? "") > (old.id ?? ""))))
    )
      out.set(key, row);
  }
  return [...out]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([day, row]) => ({ day, value: row.kg }));
}
export function series(
  rows: { day: string; value: number | null }[],
  start: string,
  end: string,
) {
  const map = new Map(rows.map((r) => [r.day, r.value]));
  const result: { day: string; x: number; value: number | null }[] = [];
  for (let day = start; day < end; day = addDays(day, 1))
    result.push({ day, x: atDay(day).getTime(), value: map.get(day) ?? null });
  return result;
}
