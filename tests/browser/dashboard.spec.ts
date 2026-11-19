import { test, expect, type Page } from "@playwright/test";
const today = new Date().toISOString().slice(0, 10);
const day = (n: number) => {
  const d = new Date(today + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
async function fixture(
  page: Page,
  { admin = true, empty = false, fail = false, devices = ["DEMO"] } = {},
) {
  let logged = false;
  const writes: string[] = [];
  await page.route("**/v1/**", async (route) => {
    const r = route.request(),
      u = new URL(r.url()),
      path = u.pathname;
    let body: unknown = null;
    let status = 200;
    if (r.method() !== "GET") writes.push(path);
    if (path.endsWith("/login")) {
      logged = true;
      body = { id: 1 };
    } else if (path.endsWith("/logout")) {
      logged = false;
      status = 204;
    } else if (!logged) {
      status = 401;
      body = { error: { message: "Sign-in required" } };
    } else if (path.endsWith("/me"))
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: admin },
        devices,
      };
    else if (path.endsWith("/profile")) body = { tz: "UTC" };
    else if (path.endsWith("/insights"))
      body = { state: "ready", outlook: { state: "good" }, metrics: [] };
    else if (path.endsWith("/days"))
      body = empty
        ? []
        : Array.from({ length: 30 }, (_, i) => ({
            day: day(i - 29),
            steps: 6000 + i * 170,
            load: 8 + (i % 5),
            hr_avg: 62,
          }));
    else if (path.endsWith("/sleep-sessions"))
      body = empty
        ? []
        : Array.from({ length: 30 }, (_, i) => ({
            id: i + 1,
            kind: "main",
            start_ts: day(i - 29) + "T00:00:00Z",
            end_ts: day(i - 29) + "T08:30:00Z",
            duration_s: 30600,
            sleep: {
              window: {
                asleep_s: 27000 + (i % 4) * 600,
                waso_s: 1800,
                efficiency: 0.93,
                coverage_s: 30600,
                time_in_bed_s: 30600,
              },
              physiology: {
                resting_hr: 50 + (i % 3),
                hrv_rmssd_ms: 80 + (i % 6),
                respiratory_rate: 12.5,
                skin_temp_c: 34.1,
                spo2_pct: 98,
              },
              stages: {
                deep_s: 7200,
                rem_s: 7200,
                light_s: 14400,
                wake_s: 1800,
              },
            },
          }));
    else if (path.endsWith("/workouts"))
      body = empty
        ? []
        : [
            {
              id: 1,
              kind: "resistance",
              start_ts: today + "T12:00:00Z",
              end_ts: today + "T12:51:00Z",
              duration_s: 3060,
              load: 9.3,
              avg_hr: 121,
              max_hr: 157,
            },
            {
              id: 2,
              kind: "walk",
              start_ts: day(-1) + "T12:00:00Z",
              end_ts: day(-1) + "T13:00:00Z",
              duration_s: 3600,
              load: 6.3,
              avg_hr: 101,
              max_hr: 127,
            },
          ];
    else if (path.endsWith("/weights")) {
      body = empty
        ? []
        : Array.from({ length: 20 }, (_, i) => ({
            id: String(i),
            measured_at: day(i - 19) + "T08:00:00Z",
            kg: 65 - i * 0.055 + (i % 3) * 0.08,
            source: "health",
            removed: false,
          }));
      if (fail) {
        status = 503;
        body = { error: { message: "Weight history unavailable" } };
      }
    } else if (path.endsWith("/weight-goal"))
      body = empty
        ? { goal: null, summary: null }
        : {
            goal: {
              active: true,
              started_at: day(-4) + "T08:00:00Z",
              finish_date: day(23),
              timezone: "UTC",
              weekly_loss_kg: 0.5,
              daily_steps_goal: 10000,
            },
            summary: {
              state: "starting",
              week_number: 1,
              median_kg: 64.3,
              weeks: [
                { start: day(-4), end: day(2), median_kg: 64.3, count: 2 },
              ],
              progress: {
                starting_weight_kg: 64.6,
                current_weight_kg: 63.9,
                total_lost_kg: 0.7,
                target_weight_kg: 62.7,
                finish_date: day(23),
                weigh_ins: [
                  { day: day(-1), kg: 64.6 },
                  { day: today, kg: 63.9 },
                ],
              },
            },
          };
    else if (path.endsWith("/admin/stats")) {
      status = admin ? 200 : 403;
      body = {
        pipeline: {
          database: "reachable",
          accounts: 3,
          frames_24h: 284000,
          pending_decode: 0,
          failed_decode: 0,
          pending_analysis: 3,
          failed_analysis: 0,
          workers: [
            { name: "decoder", healthy: true },
            { name: "analysis", healthy: false },
          ],
          ingestion: [{ hour: today + "T12:00:00Z", frames: 15000 }],
          recent_jobs: [{ kind: "sleep", completed_at: today + "T12:00:00Z" }],
        },
        http: {
          uptime_seconds: 3600,
          requests_since_start: 1200,
          server_errors_since_start: 0,
          p95_ms_recent_2048: 42,
        },
      };
    }
    await route.fulfill({
      status,
      contentType: "application/json",
      body: status === 204 ? "" : JSON.stringify(body),
    });
  });
  return writes;
}
async function login(page: Page) {
  await page.goto("/");
  await page.getByLabel("Email", { exact: true }).fill("demo@example.test");
  await page
    .getByLabel("Password", { exact: true })
    .fill("not-a-real-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Today", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".today-grid")).toBeVisible();
}
test("desktop dashboard, five pages, details and admin", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  const writes = await fixture(page);
  await login(page);
  await page.screenshot({ path: "test-results/today.png", fullPage: true });
  for (const name of ["Activity", "Sleep", "Trends", "Goals"]) {
    await page.getByRole("link", { name, exact: true }).click();
    await expect(
      page.getByRole("heading", { name, exact: true }),
    ).toBeVisible();
    await page.screenshot({
      path: `test-results/${name.toLowerCase()}.png`,
      fullPage: true,
    });
  }
  await page.getByRole("link", { name: "Activity", exact: true }).click();
  await page.getByRole("button", { name: /Strength training/ }).click();
  await expect(
    page.getByRole("heading", { name: "Strength training" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Back", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Activity", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Account menu" }).click();
  await page.getByRole("link", { name: "Admin", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Backend" })).toBeVisible();
  await expect(page.getByText("Stale heartbeat")).toBeVisible();
  await page.screenshot({ path: "test-results/admin.png", fullPage: true });
  await page.getByRole("button", { name: "Account menu" }).click();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(
    page.getByRole("heading", { name: "Sign in to Zoop" }),
  ).toBeVisible();
  expect(errors).toEqual([]);
  expect(writes).toEqual(["/v1/auth/login", "/v1/auth/logout"]);
});
test("320px and enlarged text stay within viewport", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await fixture(page);
  await login(page);
  for (const name of ["Today", "Activity", "Sleep", "Trends", "Goals"]) {
    await page.getByRole("link", { name, exact: true }).click();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  }
  await page.addStyleTag({ content: "body{font-size:20px}" });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({ path: "test-results/mobile.png", fullPage: true });
});
test("missing data and member role do not fabricate measurements", async ({
  page,
}) => {
  await fixture(page, { admin: false, empty: true });
  await login(page);
  await expect(
    page.getByText("No readings for this period").first(),
  ).toBeVisible();
  await page.getByRole("button", { name: "Account menu" }).click();
  await expect(
    page.getByRole("link", { name: "Admin", exact: true }),
  ).toHaveCount(0);
  await page.goto("/#Admin");
  await expect(page.getByText("No access to this page.")).toBeVisible();
});
test("partial request failure is visible and other charts survive", async ({
  page,
}) => {
  await fixture(page, { fail: true });
  await login(page);
  await expect(page.getByRole("alert")).toContainText(
    "Weight history unavailable",
  );
  await expect(
    page.getByRole("heading", { name: "Time asleep" }),
  ).toBeVisible();
});
test("period paging and chart readings are keyboard accessible", async ({
  page,
}) => {
  await fixture(page);
  await login(page);
  await page.getByRole("link", { name: "Trends", exact: true }).click();
  await page.getByRole("button", { name: "Week", exact: true }).click();
  await page.getByRole("button", { name: "Previous period" }).click();
  await page.getByRole("button", { name: "Next period" }).click();
  await expect(page.getByText("Readings", { exact: true })).toHaveCount(0);
  const chart = page.locator(".chart-frame").first();
  await chart.focus();
  await chart.press("End");
  await expect(chart.locator(".chart-tooltip")).toBeVisible();
  const current = await chart.locator(".chart-tooltip strong").innerText();
  await chart.press("ArrowLeft");
  await expect(chart.locator(".chart-tooltip strong")).not.toHaveText(current);
  await chart.press("Escape");
  await expect(chart.locator(".chart-tooltip")).toHaveCount(0);
  await expect(chart.getByRole("table")).toHaveCount(1);
  await page.getByRole("button", { name: "Year", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Year", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
});

test("wide layouts stay compact, date stays centered and long workout histories page", async ({
  page,
}) => {
  await page.setViewportSize({ width: 2560, height: 1440 });
  await fixture(page);
  await page.route("**/v1/devices/*/workouts?*", async (route) => {
    await route.fulfill({
      json: Array.from({ length: 14 }, (_, i) => ({
        id: i + 1,
        kind: "resistance",
        start_ts: day(-i) + "T12:00:00Z",
        end_ts: day(-i) + "T12:51:00Z",
        duration_s: 3060,
        load: 9.3,
        avg_hr: 121,
        max_hr: 157,
      })),
    });
  });
  await login(page);
  const centered = async () => {
    const date = await page
      .locator(".today-period .date-control")
      .boundingBox();
    const rings = await page.locator(".rings").boundingBox();
    expect(
      Math.abs(date!.x + date!.width / 2 - rings!.x - rings!.width / 2),
    ).toBeLessThan(2);
  };
  await centered();
  await page
    .getByRole("button", { name: "Previous period", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Today", exact: true }),
  ).toBeVisible();
  await centered();
  expect(
    await page
      .locator(".shell")
      .evaluate((el) => el.getBoundingClientRect().width),
  ).toBeLessThanOrEqual(1100);
  await expect(
    page.getByText("Read-only · Your data, your server"),
  ).toHaveCount(0);
  await expect(
    page.locator('link[rel="icon"][type="image/svg+xml"]'),
  ).toHaveAttribute("href", "/zoop.svg");
  const logo = await page.request.get("/zoop.svg");
  expect(logo.status()).toBe(200);
  expect(await logo.text()).toContain('<title id="title">Zoop</title>');
  await page.getByRole("link", { name: "Activity", exact: true }).click();
  await page.getByRole("button", { name: "Month", exact: true }).click();
  const card = page.locator(".training-grid > .panel").filter({
    has: page.getByRole("heading", {
      name: "Recent activities",
      exact: true,
    }),
  });
  await expect(card.locator(".workout")).toHaveCount(6);
  expect((await card.boundingBox())!.width).toBeLessThan(530);
  expect((await card.boundingBox())!.height).toBeLessThan(800);
  await page
    .getByRole("button", { name: "Next workouts", exact: true })
    .click();
  await expect(page.getByText("7–12 of 14", { exact: true })).toBeVisible();
  await page
    .getByRole("button", { name: "Next workouts", exact: true })
    .click();
  await expect(card.locator(".workout")).toHaveCount(2);
  await expect(
    page.getByRole("button", { name: "Next workouts", exact: true }),
  ).toBeDisabled();
  await page
    .getByRole("button", { name: "Previous workouts", exact: true })
    .click();
  await expect(card.locator(".workout")).toHaveCount(6);
  for (const width of [1920, 1024, 768, 700, 390, 320]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  }
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.screenshot({
    path: "test-results/activity-wide.png",
    fullPage: true,
  });
});

test("paired charts align and remain aligned at desktop sizes", async ({
  page,
}) => {
  await fixture(page);
  await login(page);
  for (const width of [2560, 1440, 1024]) {
    await page.setViewportSize({ width, height: 1000 });
    const cards = page.locator(".today-grid > .panel");
    const a = await cards.nth(0).boundingBox(),
      b = await cards.nth(1).boundingBox();
    expect(Math.abs(a!.y - b!.y)).toBeLessThan(1);
    expect(Math.abs(a!.height - b!.height)).toBeLessThan(1);
    const plots = page.locator(".today-grid .chart-frame");
    const c = await plots.nth(0).boundingBox(),
      d = await plots.nth(1).boundingBox();
    expect(Math.abs(c!.y - d!.y)).toBeLessThan(1);
  }
});

test("slow refresh retains charts, reports completed datasets, and ends on failure", async ({
  page,
}) => {
  await fixture(page);
  await login(page);
  const weight = await page
    .locator(".today-grid .panel-value")
    .first()
    .innerText();
  let release!: () => void;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route("**/v1/devices/*/weights?*", async (route) => {
    await held;
    await route.fulfill({
      status: 503,
      json: { error: { message: "Weight history unavailable" } },
    });
  });
  await page.getByRole("button", { name: "Refresh data", exact: true }).click();
  const progress = page.getByRole("progressbar", { name: "Loading data" });
  await expect(progress).toBeVisible();
  await expect(progress).toHaveAttribute("aria-valuenow", "5");
  await expect(progress).toHaveAttribute("aria-valuemax", "6");
  await expect(page.locator(".today-grid .panel-value").first()).toHaveText(
    weight,
  );
  release();
  await expect(progress).toHaveCount(0);
  await expect(page.getByRole("alert")).toContainText(
    "Weight history unavailable",
  );
  await expect(page.locator(".today-grid .panel-value").first()).toHaveText(
    weight,
  );
});

test("heatmap supports keyboard navigation, missing days and mobile scrolling", async ({
  page,
}) => {
  await fixture(page);
  await login(page);
  await page.getByRole("link", { name: "Activity", exact: true }).click();
  const map = page.getByRole("group", { name: "Daily activity, past year" });
  const cell = map.locator('button[tabindex="0"]');
  await cell.focus();
  await expect(page.getByRole("tooltip")).toContainText("Load");
  await cell.press("ArrowLeft");
  await expect(map.locator("button:focus")).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await map.locator("button:focus").press("Home");
  await map.locator("button:focus").press("Escape");
  await expect(page.getByRole("tooltip")).toHaveCount(0);
  expect(await map.locator('[data-level="missing"]').count()).toBeGreaterThan(
    300,
  );
  await page.setViewportSize({ width: 390, height: 844 });
  // Re-enter: recent data must be visible rather than the oldest empty months.
  await page.getByRole("link", { name: "Today", exact: true }).click();
  await page.getByRole("link", { name: "Activity", exact: true }).click();
  expect(
    await page.locator(".heatmap-scroll").evaluate((el) => el.scrollLeft),
  ).toBeGreaterThan(0);
});

test("pointer chart selection and reduced-motion initial loading work", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await fixture(page);
  let release!: () => void;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route("**/v1/devices/*/profile", async (route) => {
    await held;
    await route.fulfill({ json: { tz: "UTC" } });
  });
  await page.goto("/");
  await page.getByLabel("Email", { exact: true }).fill("demo@example.test");
  await page
    .getByLabel("Password", { exact: true })
    .fill("not-a-real-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(
    page.getByRole("progressbar", { name: "Loading data" }),
  ).toBeVisible();
  await expect(page.locator(".skeleton-grid")).toBeVisible();
  await expect(page.getByText("No readings for this period")).toHaveCount(0);
  await page.screenshot({ path: "test-results/loading.png" });
  release();
  await expect(page.locator(".today-grid")).toBeVisible();
  await expect(
    page.getByRole("progressbar", { name: "Loading data" }),
  ).toHaveCount(0);
  const chart = page.locator(".chart-frame").first(),
    plot = chart.locator(".recharts-wrapper");
  const rect = (await plot.boundingBox())!;
  await page.mouse.move(
    rect.x + rect.width * 0.75,
    rect.y + rect.height * 0.45,
  );
  await expect(chart.locator(".chart-tooltip")).toBeVisible();
  await expect(chart.locator(".chart-tooltip")).not.toContainText(":");
  await page.screenshot({ path: "test-results/tooltip.png" });
});

test("switching devices clears cached readings until the new source loads", async ({
  page,
}) => {
  await fixture(page, { devices: ["DEMO", "OTHER"] });
  await login(page);
  let release!: () => void;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route("**/v1/devices/OTHER/profile", async (route) => {
    await held;
    await route.fulfill({ json: { tz: "UTC" } });
  });
  await page.getByRole("combobox", { name: "Device" }).selectOption("OTHER");
  await expect(page.locator(".today-grid")).toHaveCount(0);
  await expect(page.locator(".skeleton-grid")).toBeVisible();
  release();
  await expect(page.locator(".today-grid")).toBeVisible();
});

test("touch heatmap targets, RTL and 200 percent layout stay usable", async ({
  page,
  browser,
}) => {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    hasTouch: true,
    isMobile: true,
  });
  const touch = await context.newPage();
  await fixture(touch);
  await login(touch);
  await touch.getByRole("link", { name: "Activity", exact: true }).click();
  const cell = touch.locator(".training-heatmap button").last();
  const box = (await cell.boundingBox())!;
  expect(box.width).toBeGreaterThanOrEqual(24);
  expect(box.height).toBeGreaterThanOrEqual(24);
  await touch.screenshot({
    path: "test-results/activity-touch.png",
    fullPage: true,
  });
  await context.close();
  await fixture(page);
  await login(page);
  await page.evaluate(() => {
    document.documentElement.dir = "rtl";
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.evaluate(() => {
    document.documentElement.dir = "ltr";
    document.body.style.zoom = "2";
  });
  await expect
    .poll(() =>
      page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    )
    .toBe(true);
  await page.screenshot({ path: "test-results/zoom-200.png", fullPage: true });
});

test("outlook waiting indicator stays small inside its neutral ring", async ({
  page,
}) => {
  await fixture(page);
  let release!: () => void;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route("**/v1/devices/*/days/*/insights?*", async (route) => {
    await held;
    await route.fulfill({
      json: { state: "ready", outlook: { state: "good" }, metrics: [] },
    });
  });
  await login(page);
  const spinner = page.getByLabel("Loading outlook");
  await expect(spinner).toBeVisible();
  const rect = (await spinner.boundingBox())!;
  expect(rect.width).toBeLessThan(30);
  expect(rect.height).toBeLessThan(30);
  release();
  await expect(spinner).toHaveCount(0);
});
