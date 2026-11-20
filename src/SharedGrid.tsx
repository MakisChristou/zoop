import { useLayoutEffect, useRef, useState, type ReactNode } from "react";

// Keep the selected order in the DOM while mixed cards pack at their natural height.
// Measure the content, never the grid cell, so row spans cannot feed back into size.
export function SharedCell({
  wide,
  children,
}: {
  wide: boolean;
  children: ReactNode;
}) {
  const content = useRef<HTMLDivElement>(null);
  const [rows, setRows] = useState(1);
  useLayoutEffect(() => {
    const element = content.current;
    if (!element) return;
    const measure = (height: number) => setRows(Math.ceil(height + 16));
    measure(element.offsetHeight);
    const observer = new ResizeObserver(([entry]) => {
      measure(entry.borderBoxSize?.[0]?.blockSize ?? element.offsetHeight);
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return (
    <div
      className={`shared-cell${wide ? " shared-wide" : ""}`}
      style={{ gridRowEnd: `span ${rows}` }}
    >
      <div ref={content}>{children}</div>
    </div>
  );
}
