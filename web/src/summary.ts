import type { Goal } from "./data";
import { dayKey } from "./calendar";

// Current-day target only: edits to a goal must not rewrite past comparisons.
export function stepsTarget(
  goal: Goal["goal"],
  date: string,
  timezone: string,
  now = new Date(),
): number | null {
  const target = goal?.daily_steps_goal;
  if (
    !goal?.active ||
    target == null ||
    !Number.isInteger(target) ||
    target < 1 ||
    target > 100_000 ||
    date !== dayKey(now, timezone)
  )
    return null;
  const goalDay = dayKey(now, goal.timezone);
  if (
    goalDay < dayKey(new Date(goal.started_at), goal.timezone) ||
    (goal.finish_date && goalDay > goal.finish_date)
  )
    return null;
  return target;
}
