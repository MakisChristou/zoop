import { describe, expect, it } from "vitest";
import { displayDay, type Goal } from "../src/data";
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

describe("daily displayed steps", () => {
  const raw = {
    day: "2026-11-20",
    steps: 5879,
    steps_walking: 4714,
    load: null,
    hr_avg: null,
  };
  it("matches iPhone's walking/running filtered count instead of raw arm motion", () => {
    expect(displayDay(raw).steps).toBe(4714);
    expect(displayDay({ ...raw, steps_walking: 0 }).steps).toBe(0);
  });
  it("does not substitute raw steps when filtered data is missing", () => {
    expect(displayDay({ ...raw, steps_walking: null }).steps).toBeNull();
    expect(displayDay({ ...raw, steps_walking: undefined }).steps).toBeNull();
  });
});
