import type { ReactNode } from "react";
import { footprint, type Placement } from "./shareLayout";
import type { Widget } from "./sharing";
export function SharedCell({
  placement,
  children,
}: {
  placement: Placement;
  children: ReactNode;
}) {
  const size = footprint(placement.key, placement.size);
  return (
    <div
      className={`shared-cell shared-${placement.key}`}
      data-widget={placement.key}
      style={{
        gridColumn: `${placement.x + 1} / span ${size.w}`,
        gridRow: `${placement.y + 1} / span ${size.h}`,
      }}
    >
      {children}
    </div>
  );
}
export function visualOrder<T extends { key: Widget }>(
  items: T[],
  layout: Placement[],
) {
  return [...items].sort((a, b) => {
    const x = layout.find((p) => p.key === a.key)!,
      y = layout.find((p) => p.key === b.key)!;
    return x.y - y.y || x.x - y.x;
  });
}
