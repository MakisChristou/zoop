import type { Insights, Recovery } from "./data";

const bands = { low: "Low", moderate: "Moderate", high: "High" } as const;
const colors = {
  low: "var(--red)",
  moderate: "var(--yellow)",
  high: "var(--green)",
} as const;
const influences: Record<string, string> = {
  hrv: "HRV",
  resting_hr: "Resting heart rate",
  last_sleep: "Last night's sleep",
  recent_sleep: "Recent sleep",
};

// Presentation only: the API owns eligibility, score, band and contributors.
export function recoveryReading(insight: Insights | null) {
  const recovery = insight?.recovery;
  const supported =
    recovery?.version === 1 && recovery.method === "zoop-recovery-v1";
  const ready =
    supported &&
    recovery.state === "ready" &&
    typeof recovery.score === "number" &&
    Number.isInteger(recovery.score) &&
    recovery.score >= 0 &&
    recovery.score <= 100 &&
    recovery.band != null &&
    Object.hasOwn(bands, recovery.band);
  return {
    score: ready ? recovery.score : null,
    fraction: ready ? recovery.score! / 100 : null,
    color: ready ? colors[recovery.band!] : "var(--muted)",
    status: ready
      ? bands[recovery.band!]
      : recoveryStatus(supported ? recovery : null),
    influences: ready
      ? [...new Set(recovery.limiting ?? [])].flatMap((key) =>
          Object.hasOwn(influences, key) ? [influences[key]] : [],
        )
      : [],
    conflict: ready && recovery.conflict,
  };
}

function recoveryStatus(recovery: Recovery | null | undefined): string {
  switch (recovery?.state) {
    case "learning":
      return `Learning · ${recovery.baseline_count}/14 nights`;
    case "updating":
      return "Updating";
    case "awaiting_sync":
      return "Syncing";
    case "no_sleep":
      return "No reading";
    case "insufficient_data":
      return "Not enough data";
    case "insufficient_recent_data":
      return "Not enough data";
    case "unusual_signals":
      return "Unusual readings";
    case "ambiguous_history":
      return "Not enough data";
    default:
      return "No reading";
  }
}

export function recoveryPending(insight: Insights | null): boolean {
  return [insight?.state, insight?.recovery?.state].some(
    (state) => state === "updating" || state === "awaiting_sync",
  );
}
