import type { Widget } from "./sharing";
export type Placement = { key: Widget; x: number; y: number };
// Fixed footprints, shared with the API's validation contract. No free resizing.
export function footprint(key: Widget) {
  return key === "daily_rings" || key === "activity_heatmap"
    ? { w: 2, h: 3 }
    : key === "by_sport"
      ? { w: 1, h: 3 }
      : key === "recent_workouts"
        ? { w: 1, h: 8 }
        : { w: 1, h: 4 };
}
export function overlaps(a: Placement, b: Placement) {
  const x = footprint(a.key),
    y = footprint(b.key);
  return (
    a.x < b.x + y.w && a.x + x.w > b.x && a.y < b.y + y.h && a.y + x.h > b.y
  );
}
function fit(key: Widget, placed: Placement[]): Placement {
  for (let y = 0; y <= 96; y++)
    for (let x = 0; x <= 2 - footprint(key).w; x++) {
      const item = { key, x, y };
      if (!placed.some((p) => overlaps(item, p))) return item;
    }
  throw new Error("Dashboard layout is full.");
}
export function layoutFor(
  keys: Widget[],
  saved: Placement[] = [],
): Placement[] {
  const placed: Placement[] = [];
  for (const key of keys) {
    const p = saved.find((p) => p.key === key),
      size = footprint(key);
    placed.push(
      p &&
        Number.isInteger(p.x) &&
        Number.isInteger(p.y) &&
        p.x >= 0 &&
        p.x + size.w <= 2 &&
        p.y >= 0 &&
        p.y <= 96 &&
        p.y + size.h <= 104 &&
        !placed.some((other) => overlaps(p, other))
        ? p
        : fit(key, placed),
    );
  }
  return placed;
}
export function moveWidget(
  layout: Placement[],
  key: Widget,
  x: number,
  y: number,
): Placement[] {
  const moved = {
    key,
    x: Math.max(0, Math.min(2 - footprint(key).w, x)),
    y: Math.max(0, Math.min(96, y)),
  };
  const stable = layout.filter((p) => p.key !== key && !overlaps(moved, p));
  const displaced = layout.filter((p) => p.key !== key && overlaps(moved, p));
  const result = [moved, ...stable];
  for (const p of displaced) result.push(fit(p.key, result));
  return layout.map((p) => result.find((r) => r.key === p.key)!);
}
