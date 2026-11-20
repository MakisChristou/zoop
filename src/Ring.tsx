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
  return (
    <div className="ring-item">
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
            {loading ? (
              <LoaderCircle
                className="spinner"
                size={20}
                aria-label={`Loading ${label.toLowerCase()}`}
              />
            ) : (
              value
            )}
          </strong>
          {!loading && subtitle && <small>{subtitle}</small>}
        </div>
      </div>
      <span>{label}</span>
    </div>
  );
}
