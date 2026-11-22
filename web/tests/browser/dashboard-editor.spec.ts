import { widgets } from "../../src/sharing";
import { test, expect, type Page, type Locator } from "@playwright/test";
const token = "d".repeat(64);
const initial = {
  title: "My dashboard",
  display_name: "",
  show_photo: false,
  range: "last30",
  from: null,
  to: null,
  widgets: ["daily_rings", "weight", "sleep", "recent_workouts", "steps"],
  layout: [],
};
const date = new Date().toISOString().slice(0, 10);
function projection(c: any) {
  return {
    title: c.title,
    display_name: "",
    photo: null,
    timezone: "UTC",
    from: "2026-10-25",
    to: "2026-11-22",
    paged: false,
    first_year: 2026,
    last_year: 2026,
    layout: c.layout,
    widgets: c.widgets.map((key: string) => ({
      key,
      ...extra(key),
      day: date,
      sleep_seconds: 30240,
      sleep_goal_minutes: 480,
      load: 11.6,
      recovery: {
        state: "ready",
        score: 76,
        band: "high",
        version: 1,
        method: "zoop-recovery-v1",
      },
      points: Array.from({ length: 29 }, (_, i) => ({
        day: new Date(Date.UTC(2026, 9, 25 + i)).toISOString().slice(0, 10),
        recovery:
          key === "recovery"
            ? {
                version: 1,
                method: "zoop-recovery-v1",
                state: "ready",
                score: [25, 55, 80][i % 3],
                band: ["low", "moderate", "high"][i % 3],
              }
            : undefined,
        value:
          key === "weight"
            ? 64.5 - i * 0.025
            : key === "sleep"
              ? 28000 + (i % 4) * 500
              : key === "steps"
                ? 7500 + (i % 5) * 1000
                : 8 + (i % 5),
      })),
      activities: [
        { day: date, kind: "resistance", duration_s: 3000, load: 9.3 },
      ],
      sports: [],
    })),
  };
}
function extra(key: string) {
  const night = {
    start_ts: "2026-11-22T00:00:00Z",
    end_ts: "2026-11-22T08:24:00Z",
    timezone: "UTC",
    sleep: {
      window: {
        asleep_s: 30240,
        onset: "2026-11-22T00:00:00Z",
        offset: "2026-11-22T08:24:00Z",
      },
      stages: { deep_s: 7200, rem_s: 7200, light_s: 15840, wake_s: 300 },
      segments: [
        {
          stage: "deep",
          start: "2026-11-22T01:00:00Z",
          end: "2026-11-22T03:00:00Z",
        },
        {
          stage: "rem",
          start: "2026-11-22T03:00:00Z",
          end: "2026-11-22T05:00:00Z",
        },
      ],
      partial: false,
    },
  };
  if (key.startsWith("sleep_")) return { night, state: "ready" };
  if (key === "nightly_metrics")
    return {
      state: "ready",
      metrics: {
        resting_hr: 48,
        hrv_rmssd_ms: 81,
        respiratory_rate: 13,
        efficiency: 0.97,
        partial: false,
      },
    };
  if (key === "morning_outlook")
    return {
      insight: {
        state: "ready",
        outlook: { state: "good" },
        metrics: [
          { key: "sleep", value: 30240 },
          { key: "hrv", value: 81 },
          { key: "resting_hr", value: 48 },
        ],
      },
    };
  if (key.startsWith("goal_"))
    return {
      as_of: "2026-11-22T12:00:00Z",
      goal: {
        phase: "cut",
        active: true,
        started_at: "2026-11-01T00:00:00Z",
        finish_date: "2026-12-01",
        timezone: "UTC",
        daily_steps_goal: 8000,
      },
      summary: {
        state: "on_pace",
        week_number: 3,
        median_kg: 64,
        change_kg: -0.4,
        weeks: [],
        progress: {
          starting_weight_kg: 66,
          current_weight_kg: 64,
          total_lost_kg: 2,
          target_weight_kg: 63,
          finish_date: "2026-12-01",
          completed: false,
          weigh_ins: [
            { day: "2026-11-15", kg: 64.5 },
            { day: "2026-11-22", kg: 64 },
          ],
        },
      },
    };
  return {};
}
async function fixture(page: Page) {
  const state = {
    preference: { config: null as any, revision: 0 },
    shares: [] as any[],
    writes: [] as string[],
    fail: false,
    previewFail: false,
    previews: 0,
  };
  await page.route("**/v1/**", async (r) => {
    const p = new URL(r.request().url()).pathname,
      m = r.request().method();
    let body: any = [];
    if (p.endsWith("/me"))
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: false },
        devices: ["DEMO"],
      };
    else if (p.endsWith("/photo")) return r.fulfill({ status: 404, json: {} });
    else if (p.startsWith("/v1/dashboard-layouts/")) {
      if (m === "PUT") {
        state.writes.push(p);
        if (state.fail)
          return r.fulfill({
            status: 409,
            json: {
              error: {
                message: "This dashboard changed. Reload before editing again.",
              },
            },
          });
        state.preference = {
          config: r.request().postDataJSON().config,
          revision: state.preference.revision + 1,
        };
      }
      body = state.preference;
    } else if (p === "/v1/shares/preview") {
      state.previews++;
      if (state.previewFail) return r.fulfill({ status: 503, json: {} });
      body = projection(r.request().postDataJSON().config);
    } else if (p === "/v1/public/dashboard")
      body = projection(state.shares[0].config);
    else if (p === "/v1/shares" && m === "GET") body = state.shares;
    else if (p === "/v1/shares" || p === "/v1/shares/1") {
      state.writes.push(p);
      body = { ...r.request().postDataJSON(), id: 1, token, revision: 1 };
      state.shares = [body];
    } else if (p.endsWith("/profile")) body = { tz: "UTC" };
    else if (p.endsWith("/insights"))
      body = {
        state: "ready",
        recovery: { state: "ready", score: 76, band: "high" },
        metrics: [],
      };
    else if (p.endsWith("/weight-goal")) body = { goal: null, summary: null };
    else if (p.endsWith("/sleep-goal"))
      body = { minutes: 480, configured: true };
    await r.fulfill({ json: body });
  });
  return state;
}
async function open(page: Page, shared = false) {
  await page.goto(shared ? "/#Shares" : "/#Today");
  await page
    .getByRole("button", {
      name: shared ? "New dashboard" : "Edit dashboard",
      exact: true,
    })
    .click();
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
}
async function drag(page: Page, source: string, x: number, y: number) {
  const b = (await page
    .getByRole("button", { name: source, exact: true })
    .boundingBox())!;
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
  await page.mouse.down();
  await page.mouse.move(x, y, { steps: 12 });
  await page.mouse.up();
}
async function noOverlap(page: Page) {
  const b = await page
    .locator(".dashboard-canvas > .shared-cell")
    .evaluateAll((ns) =>
      ns.map((n) => {
        const r = n.getBoundingClientRect();
        return { x: r.x, y: r.y, w: r.width, h: r.height };
      }),
    );
  for (let i = 0; i < b.length; i++)
    for (let j = i + 1; j < b.length; j++)
      expect(
        b[i].x < b[j].x + b[j].w - 1 &&
          b[i].x + b[i].w > b[j].x + 1 &&
          b[i].y < b[j].y + b[j].h - 1 &&
          b[i].y + b[i].h > b[j].y + 1,
      ).toBe(false);
}
for (const shared of [false, true])
  test(`${shared ? "shared" : "private"} drag, resize, save, reload and isolation`, async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 1100 });
    const s = await fixture(page);
    await open(page, shared);
    const grid = (await page.locator(".dashboard-canvas").boundingBox())!;
    await drag(page, "Add Every day", grid.x + 50, grid.y + 20);
    await expect(
      page.getByRole("button", { name: "Remove Every day" }),
    ).toBeVisible();
    await noOverlap(page);
    await expect(
      page.getByRole("button", { name: "Save", exact: true }),
    ).toBeEnabled();
    const requests = s.previews;
    await page
      .getByRole("group", { name: "Weight size" })
      .getByRole("button", { name: "Wide", exact: true })
      .click();
    await noOverlap(page);
    await expect(page.locator(".shared-weight")).toHaveCSS(
      "grid-column-end",
      "span 2",
    );
    await page.waitForTimeout(300);
    expect(s.previews).toBe(requests);
    // Moving into occupied cells displaces existing widgets without dropping them.
    await page
      .getByRole("button", { name: "Move Weight", exact: true })
      .focus();
    await page.keyboard.press("ArrowUp");
    await noOverlap(page);
    expect(s.writes).toEqual([]);
    await page.getByRole("button", { name: "Save", exact: true }).click();
    if (shared) {
      expect(s.preference.config).toBeNull();
      expect(s.shares[0].config.widgets).toContain("activity_heatmap");
      await page.goto("/#share/" + token);
    } else {
      expect(s.shares).toHaveLength(0);
      expect(
        s.preference.config.layout.find((p: any) => p.key === "weight").size,
      ).toBe("wide");
      await page.reload();
    }
    await expect(page.locator(".shared-activity_heatmap")).toBeVisible();
    await expect(page.locator(".shared-weight")).toHaveCSS(
      "grid-column-end",
      "span 2",
    );
  });
for (const width of [320, 768, 1440, 2560])
  test(`editor visual and keyboard at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    await fixture(page);
    await open(page, true);
    if (
      await page
        .getByRole("button", { name: "Add widgets", exact: true })
        .isVisible()
    )
      await page
        .getByRole("button", { name: "Add widgets", exact: true })
        .click();
    await page.getByRole("button", { name: "Add Every day" }).focus();
    await page.keyboard.press("Enter");
    await expect(
      page.getByRole("button", { name: "Save", exact: true }),
    ).toBeEnabled();
    await page
      .getByRole("button", { name: "Move Every day", exact: true })
      .focus();
    await page.keyboard.press("ArrowUp");
    await noOverlap(page);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await expect(
      page.getByRole("button", { name: "Save", exact: true }),
    ).toBeEnabled();
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      path: `/tmp/zoop-editor-${width}.png`,
      fullPage: true,
    });
    await page.screenshot({ path: `/tmp/zoop-editor-viewport-${width}.png` });
    await page.evaluate(() => {
      document.documentElement.dir = "rtl";
      document.body.style.zoom = "2";
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  });
test("cancel, failed save, stale preview and reset never publish a draft", async ({
  page,
}) => {
  const s = await fixture(page);
  await open(page);
  await page.getByRole("button", { name: "Remove Weight" }).click();
  page.once("dialog", (d) => d.accept());
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  expect(s.writes).toHaveLength(0);
  await page
    .getByRole("button", { name: "Edit dashboard", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Remove Weight" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Remove Weight" }).click();
  await page.getByRole("button", { name: "Reset layout" }).click();
  await expect(
    page.getByRole("button", { name: "Remove Weight" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
  s.fail = true;
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("Reload");
  expect(s.preference.config).toBeNull();
  s.previewFail = true;
  await page.getByRole("button", { name: "Add HRV", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeDisabled();
  await expect(
    page.getByRole("button", { name: "Retry", exact: true }),
  ).toBeVisible();
  s.previewFail = false;
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
});
test.describe("touch editing", () => {
  test.use({ isMobile: true, hasTouch: true });
  test("tap add and reorder on a narrow phone", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    const s = await fixture(page);
    await open(page, true);
    await page.getByRole("button", { name: "Add widgets", exact: true }).tap();
    await page
      .getByRole("button", { name: "Add Every day", exact: true })
      .tap();
    await expect(
      page.getByRole("button", { name: "Remove Every day" }),
    ).toBeVisible();
    await page
      .getByRole("button", { name: "Move Every day up", exact: true })
      .tap();
    await noOverlap(page);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.getByRole("button", { name: "Save", exact: true }).tap();
    expect(s.shares).toHaveLength(1);
  });
});

test.describe("touch dragging", () => {
  test.use({ isMobile: true, hasTouch: true });
  test("release uses the last position before a paint", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 1200 });
    await fixture(page);
    await open(page, true);
    for (const name of ["Daily rings", "Recent activities", "Steps"])
      await page
        .getByRole("button", { name: `Remove ${name}`, exact: true })
        .tap();
    const handle = page.getByRole("button", {
      name: "Move Weight",
      exact: true,
    });
    await handle.scrollIntoViewIfNeeded();
    const box = (await handle.boundingBox())!;
    const cdp = await page.context().newCDPSession(page);
    await handle.evaluate((element) => {
      element.addEventListener(
        "pointerdown",
        (event) => {
          element.setAttribute(
            "data-test-pointer",
            String((event as PointerEvent).pointerId),
          );
        },
        { once: true },
      );
    });
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: box.x + 15, y: box.y + 15 }],
    });
    // Deliver a move and release in one task, before React can render the move.
    await handle.evaluate((element) => {
      const target = document
        .querySelector(".shared-sleep")!
        .getBoundingClientRect();
      const init = {
        bubbles: true,
        pointerId: Number(element.getAttribute("data-test-pointer")),
        pointerType: "touch",
        isPrimary: true,
        button: 0,
        clientX: target.left + 30,
        clientY: target.top + target.height / 2 + 25,
      };
      element.dispatchEvent(
        new PointerEvent("pointermove", { ...init, buttons: 1 }),
      );
      element.dispatchEvent(
        new PointerEvent("pointerup", { ...init, buttons: 0 }),
      );
    });
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchEnd",
      touchPoints: [],
    });
    await expect(
      page.locator(".dashboard-canvas > .shared-cell").first(),
    ).toHaveAttribute("data-widget", "sleep");
    await noOverlap(page);
  });
  test("a real touch drag reorders cards", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 900 });
    await fixture(page);
    await open(page, true);
    for (const name of ["Daily rings", "Recent activities", "Steps"])
      await page
        .getByRole("button", { name: `Remove ${name}`, exact: true })
        .tap();
    await page.evaluate(() => document.fonts.ready);
    const handle = page.getByRole("button", {
      name: "Move Weight",
      exact: true,
    });
    await handle.scrollIntoViewIfNeeded();
    const box = (await handle.boundingBox())!;
    const sleep = (await page.locator(".shared-sleep").boundingBox())!;
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: box.x + 15, y: box.y + 15 }],
    });
    const end = Math.min(850, sleep.y + sleep.height / 2 + 25);
    for (let i = 1; i <= 12; i++)
      await cdp.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [
          { x: box.x + 15, y: box.y + 15 + ((end - box.y - 15) * i) / 12 },
        ],
      });
    await expect(page.locator(".drag-widget-preview")).toBeVisible();
    // Near the viewport edge the canvas scrolls during the gesture. Wait until
    // the finger really crosses Sleep's midpoint before releasing it.
    await expect
      .poll(async () => {
        const target = (await page.locator(".shared-sleep").boundingBox())!;
        return target.y + target.height / 2;
      })
      .toBeLessThan(end);
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchEnd",
      touchPoints: [],
    });
    await expect(
      page.locator(".dashboard-canvas > .shared-cell").first(),
    ).toHaveAttribute("data-widget", "sleep");
    await noOverlap(page);
  });
});

test("existing public dashboard keeps its saved scope until Save", async ({
  page,
}) => {
  const s = await fixture(page);
  s.shares = [
    {
      id: 1,
      device_id: "DEMO",
      config: initial,
      token,
      enabled: true,
      revision: 1,
      password_protected: true,
      expires_at: null,
    },
  ];
  await page.goto("/#Shares");
  await page.getByRole("button", { name: "Edit", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
  await page
    .getByRole("button", { name: "Remove Weight", exact: true })
    .click();
  expect(s.shares[0].config.widgets).toContain("weight");
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  expect(s.shares[0].config.widgets).not.toContain("weight");
  expect(s.shares[0]).not.toHaveProperty("password");
  expect(s.shares[0].expires_at).toBeNull();
});

test("Escape and dropping outside the canvas leave the layout unchanged", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await fixture(page);
  await open(page);
  const before = await page.locator(".shared-weight").getAttribute("style");
  const b = (await page
    .getByRole("button", { name: "Move Weight", exact: true })
    .boundingBox())!;
  await page.mouse.move(b.x + 10, b.y + 10);
  await page.mouse.down();
  await page.mouse.move(b.x + 100, b.y + 100, { steps: 8 });
  await page.keyboard.press("Escape");
  await page.mouse.up();
  expect(await page.locator(".shared-weight").getAttribute("style")).toBe(
    before,
  );
  await drag(page, "Add Every day", 20, 150);
  await expect(page.locator(".shared-activity_heatmap")).toHaveCount(0);
});

// Capture the same card at the same physical origin, independent of page scroll.
async function cardImage(card: Locator, path?: string) {
  await card.page().mouse.move(0, 949);
  const original = await card.getAttribute("style");
  await card.evaluate((el) => {
    const r = el.getBoundingClientRect();
    const backdrop = document.createElement("div");
    backdrop.id = "comparison-backdrop";
    Object.assign(backdrop.style, {
      position: "fixed",
      inset: "0",
      background: "#0a0a0a",
      zIndex: "9998",
    });
    document.body.append(backdrop);
    Object.assign((el as HTMLElement).style, {
      position: "fixed",
      top: "0px",
      left: "0px",
      zIndex: "9999",
      width: `${r.width}px`,
      height: `${r.height}px`,
      margin: "0",
    });
  });
  const image = await card.screenshot({ animations: "disabled", path });
  await card.evaluate(
    (el, style) =>
      style === null
        ? el.removeAttribute("style")
        : el.setAttribute("style", style),
    original,
  );
  await card
    .page()
    .evaluate(() => document.getElementById("comparison-backdrop")?.remove());
  return image;
}
for (const width of [320, 768, 1440, 2560]) {
  test(`private and public share the complete widget catalog at ${width}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 950 });
    const state = await fixture(page);
    const config = { ...initial, widgets: Object.keys(widgets) };
    state.preference = { config, revision: 1 };
    state.shares = [
      { id: 1, token, config, enabled: true, expires_at: null, revision: 1 },
    ];
    await page.goto("/#Today");
    await expect(page.locator(".shared-cell")).toHaveCount(
      Object.keys(widgets).length,
    );
    await page.evaluate(() => document.fonts.ready);
    const snapshots = new Map<string, Buffer>();
    for (const key of [
      "recovery",
      "sleep_timeline",
      "sleep_stages",
      "nightly_metrics",
      "morning_outlook",
      "goal_progress",
      "goal_weight",
    ]) {
      const card = page.locator(`[data-widget="${key}"]`);
      await card.scrollIntoViewIfNeeded();
      snapshots.set(
        key,
        await cardImage(card, `/tmp/zoop-parity-private-${key}-${width}.png`),
      );
      const overflow = await card.evaluate(
        (el) => el.scrollWidth > el.clientWidth + 1,
      );
      expect(overflow, `${key} overflows at ${width}`).toBe(false);
    }
    await page.goto(`/#share/${token}`);
    await expect(page.locator(".shared-cell")).toHaveCount(
      Object.keys(widgets).length,
    );
    await page.evaluate(() => document.fonts.ready);
    for (const [key, expected] of snapshots) {
      const card = page.locator(`[data-widget="${key}"]`);
      await card.scrollIntoViewIfNeeded();
      const actual = await cardImage(
        card,
        `/tmp/zoop-parity-${key}-${width}.png`,
      );
      expect(
        actual.equals(expected),
        `${key} must look identical at ${width}`,
      ).toBe(true);
    }
    const recovery = page.locator('[data-widget="recovery"]');
    await recovery.scrollIntoViewIfNeeded();
    await recovery
      .getByRole("group", { name: "Daily recovery history", exact: true })
      .focus();
    await page.keyboard.press("Home");
    await expect(recovery.locator(".recovery-tooltip")).toContainText("25%");
    for (const band of ["low", "moderate", "high"])
      await expect(
        recovery.locator(`path[fill="var(--recovery-${band})"]`).first(),
      ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Edit goal", exact: true }),
    ).toHaveCount(0);
    await expect(page.locator('a[href="#Sleep"]')).toHaveCount(0);
  });
}
test("the same full catalog is offered by both editors", async ({ page }) => {
  await fixture(page);
  for (const shared of [false, true]) {
    await open(page, shared);
    for (const meta of Object.values(widgets))
      await expect(
        page.getByRole("button", { name: `Add ${meta.label}`, exact: true }),
      ).toHaveCount(1);
  }
});
test("a pending Sleep ring shows loading and automatically recovers", async ({
  page,
}) => {
  await page.clock.install({ time: new Date("2026-11-22T12:00:00Z") });
  const state = await fixture(page);
  state.preference = { config: initial, revision: 1 };
  let pending = true;
  await page.route("**/v1/shares/preview", async (r) => {
    const data = projection(r.request().postDataJSON().config);
    data.widgets[0].sleep_seconds = pending ? null : 30240;
    data.widgets[0].sleep_state = pending ? "updating" : "ready";
    await r.fulfill({ json: data });
  });
  await page.goto("/#Today");
  await expect(
    page.getByRole("status", { name: "Loading sleep", exact: true }),
  ).toBeVisible();
  pending = false;
  await page.clock.fastForward(5001);
  await expect(page.locator('[data-widget="daily_rings"]')).toContainText(
    "8h 24m",
    { timeout: 10000 },
  );
  await expect(
    page.getByRole("status", { name: "Loading sleep", exact: true }),
  ).toHaveCount(0);
});
