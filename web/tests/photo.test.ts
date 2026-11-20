import { describe, expect, it } from "vitest";
import { cropRect } from "../src/photo";
describe("profile crop", () => {
  it("centres square crops without stretching portrait or landscape images", () => {
    expect(cropRect(800, 400, { x: 0.5, y: 0.5, zoom: 1 })).toEqual({
      x: 200,
      y: 0,
      size: 400,
    });
    expect(cropRect(400, 800, { x: 0.5, y: 0.5, zoom: 1 })).toEqual({
      x: 0,
      y: 200,
      size: 400,
    });
  });
  it("keeps zoomed and dragged crops entirely within the source", () => {
    for (const [w, h] of [
      [400, 800],
      [800, 400],
      [500, 500],
    ]) {
      for (const x of [-1, 0, 0.5, 1, 2])
        for (const y of [-1, 0, 0.5, 1, 2])
          for (const zoom of [0.5, 1, 2, 3, 4]) {
            const r = cropRect(w, h, { x, y, zoom });
            expect(r.x).toBeGreaterThanOrEqual(0);
            expect(r.y).toBeGreaterThanOrEqual(0);
            expect(r.x + r.size).toBeLessThanOrEqual(w);
            expect(r.y + r.size).toBeLessThanOrEqual(h);
          }
    }
  });
});
