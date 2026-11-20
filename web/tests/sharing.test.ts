import { describe, it, expect } from "vitest";
import { newConfig, publicToken, chartPoints } from "../src/sharing";
describe("sharing", () => {
  it("defaults to 30 days with identity omitted", () => {
    expect(newConfig()).toMatchObject({
      range: "last30",
      show_photo: false,
      display_name: "",
    });
  });
  it("keeps public routing separate from account pages", () => {
    expect(publicToken("#Shares")).toBeNull();
    expect(publicToken("#share/abc")).toBe("abc");
  });
  it("converts display units without filling missing readings with zero", () => {
    expect(
      chartPoints(
        [
          { day: "2026-01-01", value: 28800 },
          { day: "2026-01-03", value: 25200 },
        ],
        "sleep",
        "2026-01-01",
        "2026-01-03",
      ).map((p) => p.value),
    ).toEqual([8, null, 7]);
  });
  it("never fills dates outside the authorized window", () => {
    expect(
      chartPoints(
        [{ day: "2020-01-01", value: 70 }],
        "weight",
        "2026-01-01",
        "2026-01-02",
      ).map((p) => p.value),
    ).toEqual([null, null]);
  });
});
