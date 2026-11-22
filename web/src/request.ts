// Bound the entire response, including a body that stalls after its headers.
export async function withRequestDeadline<T>(
  caller: AbortSignal | null | undefined,
  operation: (signal: AbortSignal) => Promise<T>,
  timeout = 30_000,
): Promise<T> {
  const controller = new AbortController();
  const cancel = () => controller.abort(caller?.reason);
  if (caller?.aborted) cancel();
  else caller?.addEventListener("abort", cancel, { once: true });
  let expired = false;
  const timer = setTimeout(() => {
    expired = true;
    controller.abort();
  }, timeout);
  try {
    controller.signal.throwIfAborted();
    return await operation(controller.signal);
  } catch (error) {
    if (expired && !caller?.aborted)
      throw new Error("The server took too long. Try again.");
    throw error;
  } finally {
    clearTimeout(timer);
    caller?.removeEventListener("abort", cancel);
  }
}
