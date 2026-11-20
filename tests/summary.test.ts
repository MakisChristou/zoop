import { describe, expect, it } from "vitest";
import type { Goal } from "../src/data";
import { stepsTarget } from "../src/summary";
const now = new Date("2026-11-20T22:30:00Z");
const goal: NonNullable<Goal["goal"]> = {
  id: 1,
  revision: 1,
  active: true,
  started_at: "2026-11-19T08:00:00Z",
  pace_started_at: "2026-11-19T08:00:00Z",
  updated_at: "2026-11-19T08:00:00Z",
  timezone: "Asia/Nicosia",
  finish_date: "2026-11-21",
  daily_steps_goal: 12000,
  weekly_loss_kg: 0.5,
  reminder_enabled: false,
  reminder_weekday: 1,
  reminder_minute: 1200,
};
describe("today steps target", () => {
  it("uses the selected and goal timezones at midnight", () => {
    expect(stepsTarget(goal, "2026-11-21", "Asia/Nicosia", now)).toBe(12000);
    expect(stepsTarget(goal, "2026-11-20", "Asia/Nicosia", now)).toBeNull();
    expect(stepsTarget(goal, "2026-11-20", "UTC", now)).toBe(12000);
  });
  it("does not borrow an inactive, future, expired or missing target", () => {
    for (const changes of [
      { active: false },
      { started_at: "2026-11-22T00:00:00Z" },
      { finish_date: "2026-11-20" },
      { daily_steps_goal: null },
      { daily_steps_goal: 0 },
      { daily_steps_goal: Infinity },
    ]) {
      expect(
        stepsTarget({ ...goal, ...changes }, "2026-11-21", "Asia/Nicosia", now),
      ).toBeNull();
    }
    expect(stepsTarget(null, "2026-11-21", "Asia/Nicosia", now)).toBeNull();
  });
});
