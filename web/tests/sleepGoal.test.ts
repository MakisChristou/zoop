import { describe, expect, it } from "vitest";
import { sleepProgress } from "../src/SleepRing";

describe("backend sleep target progress", () => {
  it("fills at the goal and clamps above it", () => {
    expect(sleepProgress(6 * 3600, 480)).toBe(0.75);
    expect(sleepProgress(8 * 3600, 480)).toBe(1);
    expect(sleepProgress(8.4 * 3600, 480)).toBe(1);
    expect(sleepProgress(8 * 3600, 600)).toBe(0.8);
  });
  it("does not invent progress for missing data or a missing target", () => {
    expect(sleepProgress(null, 480)).toBeUndefined();
    expect(sleepProgress(30000, undefined)).toBeUndefined();
    expect(sleepProgress(30000, 0)).toBeUndefined();
    expect(sleepProgress(NaN, 480)).toBeUndefined();
    expect(sleepProgress(0, 480)).toBe(0);
  });
});
