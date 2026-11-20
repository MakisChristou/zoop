import { describe, it, expect } from "vitest";
import {
  bounds,
  movePeriod,
  dayKey,
  addDays,
  dailyWeights,
  series,
  duration,
} from "../src/calendar";
describe("calendar periods", () => {
  it("pages calendar months without clamping errors", () => {
    expect(bounds("2026-03-31", "Month")).toEqual(["2026-03-01", "2026-04-01"]);
    expect(movePeriod("2026-03-31", "Month", -1)).toBe("2026-02-01");
    expect(bounds("2024-02-29", "Month")[1]).toBe("2024-03-01");
  });
  it("handles weeks crossing years and calendar quarters", () => {
    expect(bounds("2026-01-01", "Week")).toEqual(["2025-12-29", "2026-01-05"]);
    expect(bounds("2026-11-19", "3 months")).toEqual([
      "2026-10-01",
      "2027-01-01",
    ]);
    expect(movePeriod("2026-12-31", "Year", 1)).toBe("2027-01-01");
  });
  it("uses profile timezone across midnight and DST", () => {
    expect(dayKey(new Date("2026-03-29T21:30:00Z"), "Europe/Athens")).toBe(
      "2026-03-30",
    );
    expect(dayKey(new Date("2026-03-29T01:30:00Z"), "America/New_York")).toBe(
      "2026-03-28",
    );
    expect(addDays("2026-03-29", 1)).toBe("2026-03-30");
  });
  it("preserves gaps instead of joining or zero-filling them", () => {
    expect(
      series(
        [
          { day: "2026-01-01", value: 64 },
          { day: "2026-01-03", value: 63 },
        ],
        "2026-01-01",
        "2026-01-04",
      ).map((r) => r.value),
    ).toEqual([64, null, 63]);
    expect(duration(undefined)).toBe("—");
  });
  it("uses one weight per local day and respects Health priority", () => {
    const rows = [
      { measured_at: "2026-01-01T08:00:00Z", kg: 64, source: "health" },
      { measured_at: "2026-01-01T12:00:00Z", kg: 65, source: "snoop" },
      { measured_at: "2026-01-01T14:00:00Z", kg: 63.9, source: "health" },
    ];
    expect(dailyWeights(rows, "UTC")).toEqual([
      { day: "2026-01-01", value: 63.9 },
    ]);
  });
});

it("uses the same deterministic daily weight tie-break as the API", () => {
  const at = "2026-01-01T12:00:00Z";
  expect(
    dailyWeights(
      [
        { id: "a", measured_at: at, kg: 60, source: "health" },
        { id: "z", measured_at: at, kg: 61, source: "health" },
      ],
      "UTC",
    )[0].value,
  ).toBe(61);
});
