import { createPortal } from "react-dom";
import {
  useEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from "react";
import {
  Activity,
  CalendarDays,
  ChartColumn,
  Check,
  CircleGauge,
  Dumbbell,
  Footprints,
  GripVertical,
  Heart,
  Moon,
  Plus,
  RotateCcw,
  Scale,
  X,
  ArrowUp,
  ArrowDown,
} from "lucide-react";
import { SharedCard } from "./SharedDashboard";
import { SharedCell, visualOrder } from "./SharedGrid";
import {
  footprint,
  layoutFor,
  moveWidget,
  resizable,
  type Placement,
} from "./shareLayout";
import {
  widgets,
  newConfig,
  type Widget,
  type ShareConfig,
  type PublicDashboard,
} from "./sharing";
const icons = {
  sleep_timeline: Moon,
  sleep_stages: Moon,
  nightly_metrics: Heart,
  morning_outlook: CircleGauge,
  goal_progress: Scale,
  goal_weight: Scale,
  daily_rings: CircleGauge,
  activity_heatmap: CalendarDays,
  recent_workouts: Dumbbell,
  by_sport: ChartColumn,
  sleep: Moon,
  recovery: Heart,
  weight: Scale,
  steps: Footprints,
  load: Activity,
  workouts: Dumbbell,
  hrv: Heart,
  resting_hr: Heart,
};
const library = Object.keys(widgets) as Widget[];
export function DashboardCanvas({
  config,
  data,
  loading,
  change,
  disabled = false,
}: {
  config: ShareConfig;
  data: PublicDashboard | null;
  loading: boolean;
  change: (update: Partial<ShareConfig>) => void;
  disabled?: boolean;
}) {
  const grid = useRef<HTMLDivElement>(null);
  const layout = layoutFor(config.widgets, config.layout);
  const [drag, setDrag] = useState<{
    key: Widget;
    x: number;
    y: number;
    inside: boolean;
    clientX: number;
    clientY: number;
  } | null>(null);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [announcement, announce] = useState("");
  const active = useRef<{
    key: Widget;
    startX: number;
    startY: number;
    moved: boolean;
    fromLibrary: boolean;
  } | null>(null);
  const dragRef = useRef(drag);
  dragRef.current = drag;
  const cancel = () => {
    active.current = null;
    dragRef.current = null;
    setDrag(null);
  };
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") cancel();
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  function update(next: Placement[]) {
    change({ widgets: next.map((p) => p.key), layout: next });
  }
  function add(key: Widget) {
    if (config.widgets.includes(key)) return;
    update(layoutFor([...config.widgets, key], layout));
    setLibraryOpen(false);
    announce(`${widgets[key].label} added`);
  }
  function reorder(key: Widget, offset: number) {
    const order = visualOrder(layout, layout).map((p) => p.key),
      i = order.indexOf(key),
      j = i + offset;
    if (j < 0 || j >= order.length) return;
    [order[i], order[j]] = [order[j], order[i]];
    update(
      layoutFor(
        order,
        order.map((k) => ({
          key: k,
          x: -1,
          y: 0,
          size: layout.find((p) => p.key === k)?.size,
        })),
      ),
    );
    announce(`${widgets[key].label} moved ${offset < 0 ? "up" : "down"}`);
  }
  function start(
    e: ReactPointerEvent<HTMLButtonElement>,
    key: Widget,
    fromLibrary: boolean,
  ) {
    if (disabled || e.button !== 0) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    active.current = {
      key,
      startX: e.clientX,
      startY: e.clientY,
      moved: false,
      fromLibrary,
    };
  }
  function pointerLocation(clientX: number, clientY: number) {
    const a = active.current,
      el = grid.current;
    if (!a || !el) return;
    if (Math.hypot(clientX - a.startX, clientY - a.startY) > 5) a.moved = true;
    if (!a.moved) return;
    const rect = el.getBoundingClientRect(),
      css = getComputedStyle(el);
    const mobile = css.display === "flex",
      rtl = css.direction === "rtl";
    const x = mobile
      ? 0
      : Math.min(
          1,
          Math.max(
            0,
            Math.floor(
              (rtl ? rect.right - clientX : clientX - rect.left) /
                ((rect.width + 16) / 2),
            ),
          ),
        );
    const pitch =
      ((parseFloat(css.gridAutoRows) + 16) * rect.width) / el.clientWidth;
    const inside =
      clientX >= rect.left &&
      clientX <= rect.right &&
      clientY >= rect.top &&
      clientY <= rect.bottom + 80;
    const y = mobile
      ? Array.from(el.querySelectorAll<HTMLElement>(":scope > .shared-cell"))
          .filter((n) => n.dataset.widget !== a.key)
          .filter(
            (n) =>
              clientY >
              n.getBoundingClientRect().top +
                n.getBoundingClientRect().height / 2,
          ).length
      : Math.min(96, Math.max(0, Math.floor((clientY - rect.top) / pitch)));
    // Pointer release can arrive before React paints the last move.
    const next = { key: a.key, x, y, inside, clientX, clientY };
    dragRef.current = next;
    setDrag(next);
  }
  const pointerLocationRef = useRef(pointerLocation);
  pointerLocationRef.current = pointerLocation;
  const dragging = drag !== null;
  useEffect(() => {
    if (!dragging) return;
    let frame: number;
    const scroll = () => {
      const d = dragRef.current;
      if (!d || !active.current) return;
      const delta =
        d.clientY > innerHeight - 60 ? 12 : d.clientY < 80 ? -12 : 0;
      if (delta) {
        window.scrollBy(0, delta);
        pointerLocationRef.current(d.clientX, d.clientY);
      }
      frame = requestAnimationFrame(scroll);
    };
    frame = requestAnimationFrame(scroll);
    return () => cancelAnimationFrame(frame);
  }, [dragging]);
  function pointer(e: ReactPointerEvent<HTMLButtonElement>) {
    pointerLocation(e.clientX, e.clientY);
  }
  function finish(e: ReactPointerEvent<HTMLButtonElement>) {
    pointerLocation(e.clientX, e.clientY);
    const a = active.current,
      d = dragRef.current;
    if (a?.moved && d?.inside && grid.current) {
      const initial = layoutFor(
        [...config.widgets.filter((k) => k !== a.key), a.key],
        layout,
      );
      if (getComputedStyle(grid.current).display === "flex") {
        const order = visualOrder(initial, initial)
          .map((p) => p.key)
          .filter((k) => k !== a.key);
        order.splice(Math.min(d.y, order.length), 0, a.key);
        update(
          layoutFor(
            order,
            order.map((key) => ({
              key,
              x: -1,
              y: 0,
              size: initial.find((p) => p.key === key)?.size,
            })),
          ),
        );
      } else update(moveWidget(initial, a.key, d.x, d.y));
      setLibraryOpen(false);
      announce(`${widgets[a.key].label} placed`);
    } else if (a && !a.moved && a.fromLibrary) add(a.key);
    cancel();
  }
  const handlers = (key: Widget, fromLibrary = false) => ({
    onPointerDown: (e: ReactPointerEvent<HTMLButtonElement>) =>
      start(e, key, fromLibrary),
    onPointerMove: pointer,
    onPointerUp: finish,
    onPointerCancel: cancel,
  });
  return (
    <div className="dashboard-workspace">
      <aside
        className={`widget-library${libraryOpen ? " library-open" : ""}`}
        aria-label="Widget library"
      >
        <h2>Widgets</h2>
        <button
          className="mobile-library-toggle"
          aria-expanded={libraryOpen}
          onClick={() => setLibraryOpen(!libraryOpen)}
        >
          <Plus size={16} />
          Add widgets
        </button>
        <div className="widget-library-items">
          {library.map((key) => {
            const Icon = icons[key],
              added = config.widgets.includes(key);
            return (
              <button
                key={key}
                className="library-widget"
                disabled={disabled || added}
                aria-label={`Add ${widgets[key].label}`}
                {...handlers(key, true)}
                onClick={(e) => {
                  if (e.detail === 0) add(key);
                }}
              >
                <Icon size={18} />
                <span>{widgets[key].label}</span>
                {added ? <Check size={15} /> : <GripVertical size={16} />}
              </button>
            );
          })}
        </div>
        <button
          className="reset-layout"
          disabled={disabled}
          onClick={() => {
            change({ widgets: newConfig().widgets, layout: [] });
            announce("Default layout restored");
          }}
        >
          <RotateCcw size={15} />
          Reset layout
        </button>
      </aside>
      <div className="canvas-wrap shared-content">
        <div
          className="shared-grid dashboard-canvas"
          ref={grid}
          aria-label="Dashboard canvas"
        >
          {visualOrder(layout, layout).map((p, index) => (
            <SharedCell key={p.key} placement={p}>
              <div
                className={`canvas-card${drag?.key === p.key ? " is-dragging" : ""}`}
              >
                <div className="canvas-tools">
                  <button
                    className="canvas-grip"
                    disabled={disabled}
                    aria-label={`Move ${widgets[p.key].label}`}
                    aria-description="Drag to move. Use arrow keys to reposition. Escape cancels dragging."
                    {...handlers(p.key)}
                    onKeyDown={(e) => {
                      const offsets: Record<string, [number, number]> = {
                        ArrowUp: [0, -1],
                        ArrowDown: [0, 1],
                        ArrowLeft: [-1, 0],
                        ArrowRight: [1, 0],
                      };
                      const d = offsets[e.key];
                      if (!d) return;
                      e.preventDefault();
                      if (
                        grid.current &&
                        getComputedStyle(grid.current).display === "flex"
                      )
                        reorder(p.key, d[1] || d[0]);
                      else {
                        const rtl =
                          grid.current &&
                          getComputedStyle(grid.current).direction === "rtl";
                        update(
                          moveWidget(
                            layout,
                            p.key,
                            p.x + d[0] * (rtl ? -1 : 1),
                            p.y + d[1],
                          ),
                        );
                        announce(`${widgets[p.key].label} moved`);
                      }
                    }}
                  >
                    <GripVertical size={16} />
                  </button>
                  <span className="canvas-tool-spacer" />
                  {resizable(p.key) && (
                    <div
                      className="widget-sizes"
                      role="group"
                      aria-label={`${widgets[p.key].label} size`}
                    >
                      {(["standard", "wide"] as const).map((size) => (
                        <button
                          key={size}
                          disabled={disabled}
                          aria-pressed={(p.size ?? "standard") === size}
                          onClick={() =>
                            update(moveWidget(layout, p.key, p.x, p.y, size))
                          }
                        >
                          {size === "standard" ? "Standard" : "Wide"}
                        </button>
                      ))}
                    </div>
                  )}
                  <div className="mobile-reorder">
                    <button
                      disabled={disabled || index === 0}
                      aria-label={`Move ${widgets[p.key].label} up`}
                      onClick={() => reorder(p.key, -1)}
                    >
                      <ArrowUp size={15} />
                    </button>
                    <button
                      disabled={disabled || index === layout.length - 1}
                      aria-label={`Move ${widgets[p.key].label} down`}
                      onClick={() => reorder(p.key, 1)}
                    >
                      <ArrowDown size={15} />
                    </button>
                  </div>
                  <button
                    disabled={disabled}
                    aria-label={`Remove ${widgets[p.key].label}`}
                    onClick={() => {
                      update(layout.filter((l) => l.key !== p.key));
                      announce(`${widgets[p.key].label} removed`);
                    }}
                  >
                    <X size={17} />
                  </button>
                </div>
                {data?.widgets.find((w) => w.key === p.key) ? (
                  <SharedCard
                    widget={data.widgets.find((w) => w.key === p.key)!}
                    data={data}
                    loading={loading}
                    hideRingDate
                  />
                ) : (
                  <div className="panel widget-placeholder" aria-busy={loading}>
                    <h2>{widgets[p.key].label}</h2>
                    {loading ? (
                      <div className="widget-skeleton" />
                    ) : (
                      <span className="muted">No readings</span>
                    )}
                  </div>
                )}
              </div>
            </SharedCell>
          ))}
          <div
            className="canvas-drop"
            style={{
              gridColumn: "1 / -1",
              gridRow: `${Math.max(0, ...layout.map((p) => p.y + footprint(p.key, p.size).h)) + 1} / span 2`,
            }}
          >
            <Plus size={22} />
            <span>Drop widget</span>
          </div>
          {drag?.inside && (
            <div
              className="canvas-drop-marker"
              style={{
                gridColumn: `${Math.min(drag.x, 2 - footprint(drag.key, layout.find((p) => p.key === drag.key)?.size).w) + 1} / span ${footprint(drag.key, layout.find((p) => p.key === drag.key)?.size).w}`,
                gridRow: `${drag.y + 1} / span ${footprint(drag.key).h}`,
                ...(grid.current &&
                getComputedStyle(grid.current).display === "flex"
                  ? {
                      top: (() => {
                        const cells = Array.from(
                          grid.current!.querySelectorAll<HTMLElement>(
                            ":scope > .shared-cell",
                          ),
                        ).filter((n) => n.dataset.widget !== drag.key);
                        const target = cells[drag.y];
                        return target
                          ? target.offsetTop - 8
                          : Math.max(
                              0,
                              ...cells.map((n) => n.offsetTop + n.offsetHeight),
                            ) + 8;
                      })(),
                      bottom: "auto",
                      height: 4,
                    }
                  : {}),
              }}
            >
              {widgets[drag.key].label}
            </div>
          )}
        </div>
        {!data && !loading && !config.widgets.length && (
          <span className="sr-only">Empty dashboard</span>
        )}
        {drag &&
          createPortal(
            <div
              className="drag-widget-preview"
              style={{
                left: Math.max(
                  8,
                  Math.min(innerWidth - 180, drag.clientX + 12),
                ),
                top: Math.max(8, Math.min(innerHeight - 48, drag.clientY + 12)),
              }}
            >
              <GripVertical size={16} />
              {widgets[drag.key].label}
            </div>,
            document.body,
          )}
        <span className="sr-only" role="status">
          {announcement}
        </span>
      </div>
    </div>
  );
}
