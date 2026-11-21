import { test, expect } from "@playwright/test";
const token = "d".repeat(64);
function dashboard(state = "ready", year = 2026) {
  return {
    title: "Training",
    display_name: "",
    photo: null,
    timezone: "UTC",
    from: `${year}-01-01`,
    to: `${year}-11-20`,
    paged: true,
    first_year: 2025,
    last_year: 2026,
    widgets: [
      {
        key: "daily_rings",
        day: `${year}-11-20`,
        sleep_seconds: 27000,
        load: 12.3,
        recovery: {
          version: 1,
          method: "zoop-recovery-v1",
          state,
          score: state === "ready" ? 73 : null,
          band: state === "ready" ? "high" : null,
        },
      },
      { key: "steps", points: [{ day: `${year}-11-20`, value: 8200 }] },
    ],
  };
}
function hold() {
  let release!: () => void;
  const promise = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { promise, release };
}
test("public initial loading shows placeholders without inventing readings", async ({
  page,
}) => {
  const held = hold();
  await page.route("**/v1/**", async (route) => {
    expect(new URL(route.request().url()).pathname).toBe(
      "/v1/public/dashboard",
    );
    expect(route.request().headers()["cookie"]).toBeUndefined();
    await held.promise;
    await route.fulfill({ json: dashboard() });
  });
  await page.goto("/#share/" + token);
  await expect(
    page.getByRole("progressbar", { name: "Loading dashboard" }),
  ).toBeVisible();
  await expect(page.locator(".skeleton-grid")).toBeVisible();
  await expect(page.locator(".ring-reading")).toHaveCount(0);
  held.release();
  await expect(page.locator(".shared-rings .ring-reading strong")).toHaveText([
    "7h 30m",
    "73",
    "12.3",
  ]);
  await expect(page.getByRole("progressbar")).toHaveCount(0);
});
test("pending public recovery has a reduced-motion-safe indicator and refreshes to a score", async ({
  page,
}) => {
  await page.clock.install();
  await page.emulateMedia({ reducedMotion: "reduce" });
  let ready = false,
    requests = 0;
  await page.route("**/v1/**", async (route) => {
    requests++;
    expect(new URL(route.request().url()).pathname).toBe(
      "/v1/public/dashboard",
    );
    expect(route.request().headers()["cookie"]).toBeUndefined();
    await route.fulfill({ json: dashboard(ready ? "ready" : "updating") });
  });
  await page.goto("/#share/" + token);
  const indicator = page.getByRole("status", {
    name: "Loading recovery",
    exact: true,
  });
  await expect(indicator).toBeVisible();
  await expect(indicator).toHaveCSS("animation-name", "none");
  for (const width of [320, 768, 1440, 2560]) {
    await page.setViewportSize({ width, height: 1000 });
    await expect(indicator).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `/tmp/zoop-public-loading-${width}.png`,
      fullPage: true,
    });
  }
  await page.evaluate(() => {
    document.documentElement.dir = "rtl";
    document.body.style.zoom = "2";
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  ready = true;
  await page.clock.fastForward(5001);
  await expect(
    page.locator(".shared-rings .ring-reading strong").nth(1),
  ).toHaveText("73");
  await expect(indicator).toHaveCount(0);
  const count = requests;
  await page.clock.fastForward(30_000);
  expect(requests).toBe(count);
});
test("year refresh keeps readings, indicates all rings, retries failures and clears revoked data", async ({
  page,
}) => {
  await page.setViewportSize({ width: 320, height: 1000 });
  const held = hold();
  let status = 200;
  await page.route("**/v1/public/dashboard", async (route) => {
    if (route.request().postDataJSON().year === 2025) await held.promise;
    await route.fulfill({ status, json: status === 200 ? dashboard() : {} });
  });
  await page.goto("/#share/" + token);
  await expect(page.locator(".shared-rings")).toBeVisible();
  await page.getByLabel("Dashboard year").selectOption("2025");
  for (const name of ["sleep", "recovery", "load"])
    await expect(
      page.getByRole("status", { name: `Updating ${name}`, exact: true }),
    ).toBeVisible();
  await expect(page.locator(".shared-rings .ring-reading strong")).toHaveText([
    "7h 30m",
    "73",
    "12.3",
  ]);
  await expect(page.locator(".chart-frame")).toBeVisible();
  await page.screenshot({
    path: "/tmp/zoop-public-refresh.png",
    fullPage: true,
  });
  status = 503;
  held.release();
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page.getByRole("progressbar")).toHaveCount(0);
  await expect(page.locator(".shared-rings .spinner")).toHaveCount(0);
  await expect(page.locator(".shared-rings")).toBeVisible();
  status = 404;
  await page.getByRole("button", { name: "Try again" }).click();
  await expect(page.getByRole("alert")).toContainText("no longer available");
  await expect(page.locator(".shared-content")).toHaveCount(0);
});
test("switching public links cancels pending reads and removes previous readings", async ({
  page,
}) => {
  const held = hold();
  await page.route("**/v1/public/dashboard", async (route) => {
    if (route.request().postDataJSON().token !== token) await held.promise;
    await route.fulfill({ json: dashboard() });
  });
  await page.goto("/#share/" + token);
  await expect(page.locator(".shared-rings")).toBeVisible();
  await page.evaluate(() => {
    location.hash = "share/" + "e".repeat(64);
  });
  await expect(page.locator(".shared-rings")).toHaveCount(0);
  await expect(page.getByRole("progressbar")).toBeVisible();
  held.release();
  await expect(page.locator(".shared-rings")).toBeVisible();
});
