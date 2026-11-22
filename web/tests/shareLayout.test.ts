import { describe, it, expect } from "vitest";
import { layoutFor, moveWidget, footprint, overlaps } from "../src/shareLayout";
import { widgets, type Widget } from "../src/sharing";
function valid(rows: ReturnType<typeof layoutFor>) {
  for (const [i, a] of rows.entries()) {
    expect(a.x).toBeGreaterThanOrEqual(0);
    expect(a.x + footprint(a.key).w).toBeLessThanOrEqual(2);
    expect(a.y).toBeGreaterThanOrEqual(0);
    expect(a.y + footprint(a.key).h).toBeLessThanOrEqual(104);
    for (const b of rows.slice(i + 1)) expect(overlaps(a, b)).toBe(false);
  }
}
describe("fixed dashboard placement", () => {
  it("packs any selected order and safely displaces collisions", () => {
    const keys = Object.keys(widgets) as Widget[];
    for (let n = 0; n < keys.length; n++) {
      const order = [...keys.slice(n), ...keys.slice(0, n)];
      let rows = layoutFor(order);
      valid(rows);
      for (const key of order)
        for (const [x, y] of [
          [0, 0],
          [1, 0],
          [1, 5],
          [99, 1000],
          [-2, -9],
        ]) {
          rows = moveWidget(rows, key, x, y);
          valid(rows);
        }
      expect(rows.map((p) => p.key)).toEqual(order);
    }
  });
  it("retains placements on reload and adding a widget", () => {
    const rows = moveWidget(layoutFor(["sleep", "load"]), "sleep", 1, 6);
    expect(layoutFor(["sleep", "load"], rows)).toEqual(rows);
    const added = layoutFor(["sleep", "load", "daily_rings"], rows);
    valid(added);
    expect(added.slice(0, 2)).toEqual(rows);
  });
  it("repairs malformed legacy layout and fixes widths", () => {
    const rows = layoutFor(
      ["daily_rings", "activity_heatmap"],
      [
        { key: "daily_rings", x: 1, y: 0 },
        { key: "activity_heatmap", x: 0, y: 0 },
      ],
    );
    valid(rows);
    expect(rows.every((r) => r.x === 0)).toBe(true);
  });
});

it("resizes only to safe widths and preserves every displaced widget", () => {
  let rows = layoutFor(["weight", "sleep", "daily_rings", "steps"]);
  rows = moveWidget(rows, "weight", 1, 0, "wide");
  expect(rows.find((p) => p.key === "weight")).toMatchObject({
    x: 0,
    y: 0,
    size: "wide",
  });
  for (const [i, a] of rows.entries())
    for (const b of rows.slice(i + 1)) expect(overlaps(a, b)).toBe(false);
  expect(
    layoutFor(
      rows.map((p) => p.key),
      rows,
    ),
  ).toEqual(rows);
  rows = moveWidget(rows, "sleep", 0, 0, "wide");
  expect(rows.find((p) => p.key === "weight")?.size).toBe("wide");
  for (const [i, a] of rows.entries())
    for (const b of rows.slice(i + 1)) expect(overlaps(a, b)).toBe(false);
  expect(footprint("activity_heatmap", "wide")).toEqual({ w: 2, h: 3 });
});
