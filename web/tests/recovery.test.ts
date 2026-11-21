import { describe, expect, it } from "vitest";
import type { Insights, Recovery } from "../src/data";
import { recoveryReading } from "../src/recovery";
const recovery: Recovery = {
  version: 1,
  method: "zoop-recovery-v1",
  state: "ready",
  score: 72,
  baseline_count: 28,
  recent_count: 3,
  reference_seconds: 28800,
  components: { hrv: 76, resting_hr: 72, last_sleep: 94, recent_sleep: 88 },
  limiting: ["resting_hr"],
  conflict: false,
  band: "high",
};
const insight = (changes: Partial<Recovery> = {}): Insights => ({
  state: "ready",
  outlook: { state: "good" },
  metrics: [],
  recovery: { ...recovery, ...changes },
});
describe("server-owned recovery presentation", () => {
  it("renders the API score and band even when components disagree", () => {
    const value = recoveryReading(insight({ score: 41, band: "high" }));
    expect(value.score).toBe(41);
    expect(value.fraction).toBe(0.41);
    expect(value.color).toBe("var(--recovery-high)");
    expect(value.status).toBe("High");
  });
  it("renders both endpoints without treating zero as unavailable", () => {
    expect(recoveryReading(insight({ score: 0, band: "low" })).score).toBe(0);
    expect(
      recoveryReading(insight({ score: 100, band: "high" })).fraction,
    ).toBe(1);
    expect(
      recoveryReading(insight({ score: 50, band: "moderate" })).color,
    ).toBe("var(--recovery-moderate)");
  });
  it("keeps old APIs, future versions and malformed values neutral", () => {
    const old: Insights = {
      state: "ready",
      outlook: { state: "good" },
      metrics: [],
    };
    for (const value of [
      null,
      old,
      { ...old, recovery: null },
      insight({ version: 2 }),
      insight({ method: "future-method" }),
      ...[null, NaN, Infinity, -1, 101, 1.5].map((score) => insight({ score })),
      insight({ band: null }),
      insight({ band: "toString" as Recovery["band"] }),
    ]) {
      expect(recoveryReading(value).score).toBeNull();
      expect(recoveryReading(value).fraction).toBeNull();
    }
  });
  it("never leaks a stale numeric score into a non-ready state", () => {
    for (const state of [
      "learning",
      "updating",
      "awaiting_sync",
      "no_sleep",
      "insufficient_data",
      "insufficient_recent_data",
      "unusual_signals",
      "ambiguous_history",
      "unknown",
    ]) {
      expect(recoveryReading(insight({ state })).score).toBeNull();
      expect(recoveryReading(insight({ state })).influences).toEqual([]);
    }
  });
  it("shows only known server-provided influences without duplicates", () => {
    expect(
      recoveryReading(
        insight({
          limiting: ["recent_sleep", "recent_sleep", "unknown"],
          conflict: true,
        }),
      ),
    ).toMatchObject({ influences: ["Recent sleep"], conflict: true });
  });
});

// The history uses the server's band, including boundary values and missing days.
import { recoveryPoints } from "../src/RecoveryHistory";
it("keeps history boundaries, missing dates and zero scores distinct", () => {
  const scores = [0, 33, 34, 66, 67, 100];
  const points = recoveryPoints(
    scores.map((score, i) => ({
      day: `2026-11-0${i + 1}`,
      recovery: {
        ...recovery,
        score,
        band: score < 34 ? "low" : score < 67 ? "moderate" : "high",
      },
      hrv_ms: 77,
      resting_hr: 47,
    })),
    "2026-11-01",
    7,
  );
  expect(points.map((p) => p.score)).toEqual([...scores, null]);
  expect(points.map((p) => p.color)).toEqual([
    "var(--recovery-low)",
    "var(--recovery-low)",
    "var(--recovery-moderate)",
    "var(--recovery-moderate)",
    "var(--recovery-high)",
    "var(--recovery-high)",
    "var(--muted)",
  ]);
});
