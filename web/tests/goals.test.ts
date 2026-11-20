import { describe, it, expect } from "vitest";
import {
  goalOutcome,
  goalProgress,
  goalWeekNumber,
  type GoalPeriod,
} from "../src/Goals";
import type { Goal } from "../src/data";
const goal: NonNullable<Goal["goal"]> = {
  id: 1,
  revision: 1,
  active: true,
  started_at: "2026-03-27T12:00:00Z",
  pace_started_at: "2026-03-27T12:00:00Z",
  updated_at: "2026-03-27T12:00:00Z",
  timezone: "Europe/Berlin",
  finish_date: "2026-04-03",
  weekly_loss_kg: 0.3,
  daily_steps_goal: null,
  reminder_enabled: false,
  reminder_weekday: 1,
  reminder_minute: 1200,
};
const summary: NonNullable<Goal["summary"]> = {
  state: "starting",
  week_number: 1,
  median_kg: 64.2,
  change_kg: null,
  weeks: [],
  progress: {
    weigh_ins: [],
    finish_date: goal.finish_date,
    completed: false,
    starting_weight_kg: 64.6,
    current_weight_kg: 63.9,
    total_lost_kg: 0.7,
    target_weight_kg: 63.2,
  },
};
describe("goal presentation", () => {
  it("keeps calendar week numbers after a midweek start or pace change", () => {
    expect(goalWeekNumber(goal, "2026-03-23")).toBe(1);
    expect(goalWeekNumber(goal, "2026-03-30")).toBe(2);
    expect(
      goalWeekNumber(
        { ...goal, pace_started_at: "2026-04-01T12:00:00Z" },
        "2026-04-06",
      ),
    ).toBe(3);
  });
  it("uses calendar days through DST and bounds progress", () => {
    const p = goalProgress(goal, summary, new Date("2026-03-30T10:00:00Z"));
    expect(p.elapsed).toBe(3);
    expect(p.remaining).toBe(4);
    expect(p.weight).toBeCloseTo(0.5);
    expect(goalProgress(goal, summary, new Date("2026-05-01")).time).toBe(1);
  });
  it("does not turn missing measurements or a gain into success", () => {
    expect(goalProgress(goal, null, new Date()).weight).toBeNull();
    expect(
      goalProgress(
        goal,
        { ...summary, progress: { ...summary.progress!, total_lost_kg: -0.2 } },
        new Date(),
      ).weight,
    ).toBe(0);
  });
  it("separates choosing to end from reaching a target", () => {
    const p: GoalPeriod = {
      id: 1,
      goal,
      summary,
      ended_at: "2026-03-30T10:00:00Z",
      end_reason: "manual",
    };
    expect(goalOutcome(p)).toBe("Ended early");
    expect(goalOutcome({ ...p, goal: { ...goal, finish_date: null } })).toBe(
      "Ended",
    );
    expect(
      goalOutcome({
        ...p,
        summary: {
          ...summary,
          progress: { ...summary.progress!, current_weight_kg: 63.1 },
        },
      }),
    ).toBe("Target reached");
    expect(goalOutcome({ ...p, summary: { ...summary, progress: null } })).toBe(
      "No weigh-ins",
    );
  });
});

it("bulk progress and outcomes follow increasing weight", () => {
  const g = { ...goal, phase: "bulk" as const };
  const s = {
    ...summary,
    progress: {
      ...summary.progress!,
      starting_weight_kg: 64,
      current_weight_kg: 64.4,
      target_weight_kg: 64.8,
      total_lost_kg: -0.4,
    },
  };
  expect(goalProgress(g, s, new Date()).weight).toBeCloseTo(0.5);
  expect(
    goalOutcome({
      id: 1,
      goal: g,
      summary: s,
      ended_at: "2026-04-04",
      end_reason: "scheduled",
    }),
  ).toBe("Finished");
  expect(
    goalOutcome({
      id: 1,
      goal: g,
      summary: { ...s, progress: { ...s.progress, current_weight_kg: 64.9 } },
      ended_at: "2026-04-04",
      end_reason: "scheduled",
    }),
  ).toBe("Target reached");
});
it("indefinite maintenance never invents a countdown", () => {
  const p = goalProgress(
    { ...goal, phase: "maintenance", finish_date: null },
    { ...summary, progress: { ...summary.progress!, target_weight_kg: null } },
    new Date("2026-04-03T12:00:00Z"),
  );
  expect(p.time).toBeNull();
  expect(p.remaining).toBeNull();
  expect(p.weight).toBeNull();
  expect(p.elapsed).toBe(7);
});
