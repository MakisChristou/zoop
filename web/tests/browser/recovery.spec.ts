import { test, expect, type Page } from "@playwright/test";
const ready = {
  state: "ready",
  outlook: { state: "good" },
  metrics: [
    { key: "sleep", value: 27000 },
    { key: "hrv", value: 81 },
    { key: "resting_hr", value: 48 },
  ],
  recovery: {
    version: 1,
    method: "zoop-recovery-v1",
    state: "ready",
    score: 72,
    baseline_count: 28,
    recent_count: 3,
    reference_seconds: 28800,
    components: { hrv: 76, resting_hr: 72, last_sleep: 94, recent_sleep: 88 },
    limiting: ["resting_hr"],
    conflict: false,
    band: "high",
  },
};
async function fixture(page: Page) {
  let logged = false;
  await page.route("**/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    let body: unknown = [];
    let status = 200;
    if (path === "/v1/setup") {
      body = { available: false };
    } else if (path.endsWith("/login")) {
      logged = true;
      body = { id: 1 };
    } else if (!logged) {
      status = 401;
      body = { error: { message: "Sign in" } };
    } else if (path.endsWith("/me"))
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: false },
        devices: ["DEMO", "SECOND"],
      };
    else if (path.endsWith("/profile")) body = { tz: "UTC" };
    else if (path.endsWith("/insights")) body = ready;
    else if (path.endsWith("/weight-goal"))
      body = { goal: null, summary: null };
    else if (path.endsWith("/weight-goals"))
      body = { items: [], next_cursor: null };
    await route.fulfill({ status, json: body });
  });
}
async function login(page: Page) {
  await page.goto("/");
  await page.getByLabel("Email", { exact: true }).fill("demo@example.test");
  await page
    .getByLabel("Password", { exact: true })
    .fill("not-a-real-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.locator(".today-grid")).toBeVisible();
}

test("recovery uses server score and leaves steps in Today", async ({
  page,
}) => {
  await fixture(page);
  await login(page);
  const ring = page.getByRole("button", { name: "Recovery: 72", exact: true });
  await expect(ring).toBeVisible();
  await expect(ring.locator("strong")).toHaveText("72");
  await expect(ring.locator("svg circle").last()).toHaveAttribute(
    "stroke-dasharray",
    `${383 * 0.72} 383`,
  );
  await expect(
    page.getByRole("heading", { name: "Steps", exact: true }),
  ).toBeVisible();
  await ring.focus();
  await page.keyboard.press("Enter");
  const dialog = page.getByRole("dialog", { name: "Recovery", exact: true });
  await expect(dialog).toBeVisible();
  await expect(dialog.locator(".recovery-score")).toContainText("72High");
  await expect(dialog).toContainText("7h 30m");
  await expect(dialog).toContainText("81 ms");
  await expect(dialog).toContainText("48 bpm");
  await expect(dialog.locator(".recovery-influence")).toHaveText(
    "Main influenceResting heart rate",
  );
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
  await expect(ring).toBeFocused();
});

test("older APIs, partial inputs and ineligible scores stay neutral", async ({
  page,
}) => {
  await fixture(page);
  let payload: unknown = {
    state: "ready",
    outlook: { state: "good" },
    metrics: [],
  };
  await page.route("**/insights?*", (route) =>
    route.fulfill({ json: payload }),
  );
  await login(page);
  const ring = page.locator(".recovery-ring");
  await expect(ring.locator("strong")).toHaveText("—");
  await expect(ring.locator("svg circle")).toHaveCount(1);
  payload = {
    ...ready,
    recovery: {
      ...ready.recovery,
      state: "learning",
      score: 72,
      baseline_count: 8,
    },
  };
  await page
    .getByRole("button", { name: "Previous period", exact: true })
    .click();
  await ring.click();
  await expect(page.getByRole("dialog")).toContainText(
    "Learning · 8/14 nights",
  );
  await expect(page.locator(".recovery-metrics")).toHaveCount(0);
});

test("date and device changes clear old scores; refresh retains score with feedback", async ({
  page,
}) => {
  await fixture(page);
  await login(page);
  await expect(page.locator(".recovery-ring strong")).toHaveText("72");
  let release!: () => void;
  let held = new Promise<void>((r) => (release = r));
  await page.route("**/insights?*", async (route) => {
    await held;
    await route.fulfill({
      json: {
        ...ready,
        recovery: { ...ready.recovery, score: 21, band: "low" },
      },
    });
  });
  await page.getByRole("button", { name: "Refresh data", exact: true }).click();
  await expect(page.locator(".recovery-ring strong")).toHaveText("72");
  await expect(
    page.getByLabel("Updating recovery", { exact: true }),
  ).toBeVisible();
  release();
  await expect(page.locator(".recovery-ring strong")).toHaveText("21");
  held = new Promise<void>((r) => (release = r));
  await page
    .getByRole("button", { name: "Previous period", exact: true })
    .click();
  await expect(
    page.getByLabel("Loading recovery", { exact: true }),
  ).toBeVisible();
  await expect(page.locator(".recovery-ring")).not.toContainText("21");
  release();
  await expect(page.locator(".recovery-ring strong")).toHaveText("21");
  held = new Promise<void>((r) => (release = r));
  await page
    .getByRole("combobox", { name: "Device", exact: true })
    .selectOption("SECOND");
  await expect(
    page.getByLabel("Loading recovery", { exact: true }),
  ).toBeVisible();
  await expect(page.locator(".recovery-ring")).not.toContainText("21");
  release();
  await expect(page.locator(".recovery-ring strong")).toHaveText("21");
});

test("responsive recovery dialog, reduced motion and RTL", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await fixture(page);
  await login(page);
  for (const width of [320, 768, 1440, 2560]) {
    await page.setViewportSize({ width, height: 1000 });
    await page
      .locator(".rings")
      .screenshot({ path: `test-results/recovery-rings-${width}.png` });
    await page.locator(".recovery-ring").click();
    const dialog = page.getByRole("dialog");
    expect(
      await dialog.evaluate((el) => el.scrollWidth <= el.clientWidth),
    ).toBe(true);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `test-results/recovery-${width}.png`,
      fullPage: true,
    });
    await page.getByRole("button", { name: "Close", exact: true }).click();
  }
  await page.setViewportSize({ width: 768, height: 1000 });
  await page.evaluate(() => {
    document.documentElement.dir = "rtl";
    document.body.style.zoom = "2";
  });
  await page.locator(".recovery-ring").click();
  expect(
    await page
      .getByRole("dialog")
      .evaluate((el) => el.scrollWidth <= el.clientWidth),
  ).toBe(true);
  await page.getByRole("button", { name: "Close", exact: true }).click();
});

test("pending analysis polls insights only, then stops on ready", async ({
  page,
}) => {
  await page.clock.install();
  await fixture(page);
  let calls = 0;
  let dayCalls = 0;
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.endsWith("/days")) dayCalls += 1;
  });
  await page.route("**/insights?*", (route) => {
    calls += 1;
    return route.fulfill({
      json:
        calls === 1
          ? {
              ...ready,
              recovery: {
                ...ready.recovery,
                state: "updating",
                score: null,
                band: null,
              },
            }
          : ready,
    });
  });
  await login(page);
  await expect(
    page.getByLabel("Loading recovery", { exact: true }),
  ).toBeVisible();
  await page.clock.fastForward(5001);
  await expect(page.locator(".recovery-ring strong")).toHaveText("72");
  await page.clock.fastForward(60000);
  expect(calls).toBe(2);
  expect(dayCalls).toBe(1);
});

test("an initial insights failure keeps recovery neutral and shows the error", async ({
  page,
}) => {
  await fixture(page);
  await page.route("**/insights?*", (route) =>
    route.fulfill({
      status: 503,
      json: { error: { message: "Analysis unavailable" } },
    }),
  );
  await login(page);
  await expect(page.getByRole("alert")).toContainText("Analysis unavailable");
  await expect(page.locator(".recovery-ring strong")).toHaveText("—");
  await expect(page.locator(".recovery-ring > .ring > svg circle")).toHaveCount(
    1,
  );
});

test("pending polling backs off and pauses in a hidden tab", async ({
  page,
}) => {
  await page.clock.install();
  await fixture(page);
  let calls = 0;
  await page.route("**/insights?*", (route) => {
    calls += 1;
    return route.fulfill({
      json: {
        ...ready,
        recovery: {
          ...ready.recovery,
          state: "updating",
          score: null,
          band: null,
        },
      },
    });
  });
  await login(page);
  await expect(
    page.getByLabel("Loading recovery", { exact: true }),
  ).toBeVisible();
  for (let count = 2; count <= 7; count++) {
    await page.clock.fastForward(5001);
    await expect.poll(() => calls).toBe(count);
    await expect(
      page.getByLabel("Loading recovery", { exact: true }),
    ).toBeVisible();
  }
  await page.clock.fastForward(5001);
  expect(calls).toBe(7);
  await page.clock.fastForward(25001);
  await expect.poll(() => calls).toBe(8);
  await page.evaluate(() => {
    Object.defineProperty(document, "visibilityState", {
      value: "hidden",
      configurable: true,
    });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await page.clock.fastForward(60000);
  expect(calls).toBe(8);
  await page.evaluate(() => {
    Object.defineProperty(document, "visibilityState", {
      value: "visible",
      configurable: true,
    });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await page.clock.fastForward(30001);
  await expect.poll(() => calls).toBe(9);
});
