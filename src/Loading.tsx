export function LoadingBar({
  value,
  total,
  label = "Loading data",
}: {
  value?: number;
  total?: number;
  label?: string;
}) {
  const measurable = value != null && total != null && total > 0;
  return (
    <div className="loading-status" role="status">
      <span className="sr-only">{label}</span>
      <div
        className={`loading-bar${measurable ? "" : " indeterminate"}`}
        role="progressbar"
        aria-label={label}
        aria-valuemin={measurable ? 0 : undefined}
        aria-valuemax={measurable ? total : undefined}
        aria-valuenow={measurable ? value : undefined}
        aria-valuetext={
          measurable ? `${value} of ${total} datasets checked` : undefined
        }
      >
        <span
          style={
            measurable
              ? { width: `${Math.max(0, Math.min(1, value / total)) * 100}%` }
              : undefined
          }
        />
      </div>
    </div>
  );
}
export function LoadingCards() {
  return (
    <div className="grid skeleton-grid" aria-hidden="true">
      {[0, 1, 2, 3].map((n) => (
        <div className="panel skeleton-card" key={n}>
          <span className="skeleton-title" />
          <div className="skeleton-plot" />
        </div>
      ))}
    </div>
  );
}
