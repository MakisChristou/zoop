import type { Widget } from "./sharing";
export type Placement = {
  key: Widget;
  x: number;
  y: number;
  size?: "standard" | "wide";
};
// Fixed footprints, shared with the API's validation contract. No free resizing.
export const resizable = (key: Widget) =>
  !["daily_rings", "activity_heatmap", "by_sport", "recent_workouts"].includes(
    key,
  );
export function footprint(key: Widget, preset?: Placement["size"]) {
  return key === "daily_rings" || key === "activity_heatmap"
    ? { w: 2, h: 3 }
    : key === "by_sport"
      ? { w: 1, h: 3 }
      : key === "recent_workouts"
        ? { w: 1, h: 8 }
        : { w: preset === "wide" ? 2 : 1, h: 4 };
}
export function overlaps(a: Placement, b: Placement) {
  const x = footprint(a.key, a.size),
    y = footprint(b.key, b.size);
  return (
    a.x < b.x + y.w && a.x + x.w > b.x && a.y < b.y + y.h && a.y + x.h > b.y
  );
}
function fit(
  key: Widget,
  placed: Placement[],
  size?: Placement["size"],
): Placement {
  for (let y = 0; y <= 96; y++)
    for (let x = 0; x <= 2 - footprint(key, size).w; x++) {
      const item = { key, x, y, ...(size ? { size } : {}) };
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
      size = footprint(key, p?.size);
    placed.push(
      p &&
        (!p.size ||
          p.size === "standard" ||
          (p.size === "wide" && resizable(key))) &&
        Number.isInteger(p.x) &&
        Number.isInteger(p.y) &&
        p.x >= 0 &&
        p.x + size.w <= 2 &&
        p.y >= 0 &&
        p.y <= 96 &&
        p.y + size.h <= 104 &&
        !placed.some((other) => overlaps(p, other))
        ? p
        : fit(
            key,
            placed,
            resizable(key) && p?.size === "wide" ? "wide" : undefined,
          ),
    );
  }
  return placed;
}
export function moveWidget(
  layout: Placement[],
  key: Widget,
  x: number,
  y: number,
  size = layout.find((p) => p.key === key)?.size,
): Placement[] {
  const moved = {
    key,
    ...(size ? { size } : {}),
    x: Math.max(0, Math.min(2 - footprint(key, size).w, x)),
    y: Math.max(0, Math.min(96, y)),
  };
  // Push collisions down in reading order, preserving columns and chosen sizes.
  // Inserting a wide heatmap shifts the rows below it instead of scattering cards.
  const result: Placement[] = [moved];
  const remaining = layout
    .filter((p) => p.key !== key)
    .sort((a, b) => a.y - b.y || a.x - b.x);
  for (const original of remaining) {
    let p = { ...original };
    let collisions = result.filter((other) => overlaps(p, other));
    while (collisions.length) {
      p.y = Math.max(
        ...collisions.map(
          (other) => other.y + footprint(other.key, other.size).h,
        ),
      );
      if (p.y > 96) {
        p = fit(p.key, result, p.size);
        break;
      }
      collisions = result.filter((other) => overlaps(p, other));
    }
    result.push(p);
  }
  return layout.map((p) => result.find((r) => r.key === p.key)!);
}
