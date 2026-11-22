import { afterEach, expect, it, vi } from "vitest";
import { withRequestDeadline } from "../src/request";
afterEach(() => vi.useRealTimers());
const stalled = (signal: AbortSignal) =>
  new Promise<never>((_, reject) => {
    signal.addEventListener("abort", () => reject(signal.reason), {
      once: true,
    });
  });
it("ends a stalled request with a retryable error", async () => {
  vi.useFakeTimers();
  const result = withRequestDeadline(undefined, stalled);
  const assertion = expect(result).rejects.toThrow("server took too long");
  await vi.advanceTimersByTimeAsync(30_000);
  await assertion;
  expect(vi.getTimerCount()).toBe(0);
});
it("preserves caller cancellation instead of reporting a timeout", async () => {
  const caller = new AbortController();
  const result = withRequestDeadline(caller.signal, stalled);
  caller.abort();
  await expect(result).rejects.toMatchObject({ name: "AbortError" });
});
it("does not start an already cancelled request and cleans up completed work", async () => {
  vi.useFakeTimers();
  const operation = vi.fn(async () => 42);
  await expect(
    withRequestDeadline(AbortSignal.abort(), operation),
  ).rejects.toMatchObject({ name: "AbortError" });
  expect(operation).not.toHaveBeenCalled();
  await expect(withRequestDeadline(undefined, operation)).resolves.toBe(42);
  expect(vi.getTimerCount()).toBe(0);
});
