import { useRef, useState, type ReactNode, type PointerEvent } from "react";
import { GripVertical } from "lucide-react";
import { footprint, moveWidget, type Placement } from "./shareLayout";
import { widgets, type Widget } from "./sharing";
export function SharedCell({
  placement,
  layout,
  onMove,
  children,
}: {
  placement: Placement;
  layout: Placement[];
  onMove?: (layout: Placement[]) => void;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null),
    start = useRef<{
      x: number;
      y: number;
      column: number;
      row: number;
    } | null>(null);
  const [ghost, setGhost] = useState<Placement | null>(null);
  const size = footprint(placement.key);
  function rowPitch() {
    const grid = ref.current?.parentElement;
    return grid ? parseFloat(getComputedStyle(grid).gridAutoRows) + 16 : 96;
  }
  function position(e: PointerEvent<HTMLButtonElement>) {
    const origin = start.current,
      grid = ref.current?.parentElement;
    if (!origin || !grid) return placement;
    const width = grid.getBoundingClientRect().width,
      scale = width / grid.clientWidth,
      rtl = getComputedStyle(grid).direction === "rtl";
    return {
      ...placement,
      x: Math.max(
        0,
        Math.min(
          2 - size.w,
          origin.column +
            Math.round(
              ((e.clientX - origin.x) / ((width + 16 * scale) / 2)) *
                (rtl ? -1 : 1),
            ),
        ),
      ),
      y: Math.max(
        0,
        Math.min(
          96,
          origin.row +
            Math.round((e.clientY - origin.y) / (rowPitch() * scale)),
        ),
      ),
    };
  }
  function move(x: number, y: number) {
    onMove?.(moveWidget(layout, placement.key, x, y));
  }
  return (
    <div
      ref={ref}
      className={`shared-cell shared-${placement.key}${onMove ? " arranging" : ""}`}
      style={{
        gridColumn: `${placement.x + 1} / span ${size.w}`,
        gridRow: `${placement.y + 1} / span ${size.h}`,
        zIndex: ghost ? 10 : undefined,
        transform: ghost
          ? `translate(${(((ghost.x - placement.x) * ((ref.current?.parentElement?.clientWidth ?? 0) + 16)) / 2) * (getComputedStyle(ref.current!).direction === "rtl" ? -1 : 1)}px, ${(ghost.y - placement.y) * rowPitch()}px)`
          : undefined,
      }}
    >
      {onMove && (
        <button
          className="widget-grip"
          aria-label={`Move ${widgets[placement.key].label}`}
          aria-description="Drag to move. Arrow keys move one grid space."
          onPointerDown={(e) => {
            e.currentTarget.setPointerCapture(e.pointerId);
            start.current = {
              x: e.clientX,
              y: e.clientY,
              column: placement.x,
              row: placement.y,
            };
            setGhost(placement);
          }}
          onPointerMove={(e) => {
            if (start.current) setGhost(position(e));
          }}
          onPointerUp={(e) => {
            if (start.current) {
              const p = position(e);
              move(p.x, p.y);
            }
            start.current = null;
            setGhost(null);
          }}
          onPointerCancel={() => {
            start.current = null;
            setGhost(null);
          }}
          onKeyDown={(e) => {
            const offset: Record<string, [number, number]> = {
              ArrowLeft: [-1, 0],
              ArrowRight: [1, 0],
              ArrowUp: [0, -1],
              ArrowDown: [0, 1],
            };
            const d = offset[e.key];
            if (d) {
              e.preventDefault();
              const rtl = getComputedStyle(e.currentTarget).direction === "rtl";
              move(placement.x + d[0] * (rtl ? -1 : 1), placement.y + d[1]);
            }
          }}
        >
          <GripVertical size={18} />
        </button>
      )}
      {ghost && (
        <span className="sr-only" role="status">
          Row {ghost.y + 1} · Column {ghost.x + 1}
        </span>
      )}
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
