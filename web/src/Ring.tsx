import { LoaderCircle } from "lucide-react";
export function Ring({
  label,
  value,
  color,
  fraction,
  subtitle,
  loading = false,
}: {
  label: string;
  value: string;
  color: string;
  fraction?: number;
  subtitle?: string;
  loading?: boolean;
}) {
  const empty = value === "—";
  return (
    <div className="ring-item" aria-busy={loading}>
      <div className="ring">
        <svg viewBox="0 0 140 140" aria-hidden="true">
          <circle
            cx="70"
            cy="70"
            r="61"
            fill="none"
            stroke="var(--track)"
            strokeWidth="7"
          />
          {fraction != null ? (
            <circle
              cx="70"
              cy="70"
              r="61"
              fill="none"
              stroke={color}
              strokeWidth="7"
              strokeLinecap="round"
              strokeDasharray={`${383 * Math.max(0, Math.min(1, fraction))} 383`}
            />
          ) : (
            <circle cx="131" cy="70" r="4" fill={color} />
          )}
        </svg>
        <div className="ring-reading">
          <strong>
            {loading && empty ? (
              <LoaderCircle
                className="spinner"
                size={20}
                role="status"
                aria-label={`Loading ${label.toLowerCase()}`}
              />
            ) : (
              value
            )}
          </strong>
          {subtitle && <small>{subtitle}</small>}
        </div>
      </div>
      <span>
        {label}
        {loading && !empty && (
          <LoaderCircle
            className="spinner recovery-refresh"
            size={12}
            role="status"
            aria-label={`Updating ${label.toLowerCase()}`}
          />
        )}
      </span>
    </div>
  );
}
