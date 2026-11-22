import { duration } from "./calendar";
import { Ring } from "./Ring";

// Both private and shared dashboards use the target supplied by the server.
export function sleepProgress(
  seconds: number | null | undefined,
  minutes: number | null | undefined,
) {
  if (
    seconds == null ||
    minutes == null ||
    !Number.isFinite(seconds) ||
    !Number.isFinite(minutes) ||
    minutes <= 0
  )
    return undefined;
  return Math.max(0, Math.min(1, seconds / (minutes * 60)));
}

export function SleepRing({
  seconds,
  goalMinutes,
  loading = false,
}: {
  seconds?: number | null;
  goalMinutes?: number | null;
  loading?: boolean;
}) {
  return (
    <Ring
      label="Sleep"
      value={duration(seconds)}
      color="var(--sleep)"
      fraction={sleepProgress(seconds, goalMinutes)}
      loading={loading}
    />
  );
}
