import { test, expect, type Page } from "@playwright/test";
const token = "b".repeat(64);
function fixture(from = "2026-01-01") {
  const to = "2026-11-20";
  const points = Array.from({ length: 324 }, (_, i) => ({
    day: new Date(Date.UTC(2026, 0, 1 + i)).toISOString().slice(0, 10),
    value: i % 8 === 0 ? null : 5 + (i % 12),
  })).filter((p) => p.day >= from);
  const activities = Array.from({ length: 12 }, (_, i) => ({
    day: `2026-11-${20 - Math.floor(i / 2)}`,
    kind: i % 2 ? "walk" : "resistance",
    duration_s: i % 2 ? 2400 : 3300,
    load: i % 2 ? 5.4 : 10.2,
  }));
  return {
    title: "Training",
    display_name: "",
    photo: null,
    timezone: "UTC",
    from,
    to,
    paged: from === "2026-01-01",
    first_year: 2025,
    last_year: 2026,
    widgets: [
      {
        key: "activity_heatmap",
        points,
        activities: activities.map(({ load, ...s }) => ({ ...s, count: 1 })),
      },
      {
        key: "by_sport",
        sports: [
          { kind: "resistance", count: 6, seconds: 19800 },
          { kind: "walk", count: 6, seconds: 14400 },
        ],
      },
      { key: "recent_workouts", activities },
    ],
  };
}
async function publicPage(page: Page, from = "2026-01-01") {
  const paths: string[] = [];
  await page.route("**/v1/**", async (r) => {
    const path = new URL(r.request().url()).pathname;
    paths.push(path);
    expect(path).toBe("/v1/public/dashboard");
    await r.fulfill({ json: fixture(from) });
  });
  await page.goto("/#share/" + token);
  await expect(
    page.getByRole("heading", { name: "Recent activities" }),
  ).toBeVisible();
  return paths;
}
for (const width of [320, 768, 1440, 2560])
  test(`real dashboard widgets at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1100 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    const paths = await publicPage(page);
    await expect(page.locator(".training-heatmap")).toHaveCount(1);
    await expect(page.locator(".sport")).toHaveCount(2);
    await expect(page.locator(".timeline-entry")).toHaveCount(8);
    await expect(page.locator("button.workout")).toHaveCount(0);
    const day = page.getByRole("button", {
      name: /November 20, 2026.*2 workouts/,
    });
    await day.focus();
    await page.keyboard.press("Enter");
    await expect(page.getByRole("tooltip")).toContainText("Strength training");
    await expect(page.getByRole("tooltip")).toContainText("Walk");
    await page.getByRole("button", { name: "Next workouts" }).click();
    await expect(page.locator(".timeline-entry")).toHaveCount(4);
    await page.getByRole("button", { name: "Previous workouts" }).click();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await day.blur();
    await page.screenshot({
      path: `/tmp/zoop-rich-widgets-${width}.png`,
      fullPage: true,
    });
    expect(paths.every((p) => p === "/v1/public/dashboard")).toBe(true);
  });
test.describe("touch heatmap", () => {
  test.use({ hasTouch: true });
  test("30-day heatmap stays inside its period and remains usable on touch", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await publicPage(page, "2026-10-22");
    const cells = page.locator(".training-heatmap button:not(:disabled)");
    await expect(cells).toHaveCount(30);
    await expect(
      page.locator('.training-heatmap button[aria-label^="October 21, 2026"]'),
    ).toBeDisabled();
    await page
      .getByRole("button", { name: /November 20, 2026.*2 workouts/ })
      .click();
    await expect(page.getByRole("tooltip")).toBeVisible();
    await page.evaluate(() => {
      document.documentElement.dir = "rtl";
      document.documentElement.style.fontSize = "200%";
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const size = await cells.last().boundingBox();
    expect(size!.width).toBeGreaterThanOrEqual(24);
    expect(size!.height).toBeGreaterThanOrEqual(24);
    await page.screenshot({
      path: "/tmp/zoop-rich-widgets-30d.png",
      fullPage: true,
    });
  });
});
test("new cards are optional and editing does not expand an existing link", async ({
  page,
}) => {
  const config = {
    title: "Old dashboard",
    range: "last30",
    widgets: ["workouts"],
    display_name: "",
    show_photo: false,
    from: null,
    to: null,
  };
  let preview: any = null;
  await page.route("**/v1/**", async (r) => {
    const p = new URL(r.request().url()).pathname;
    let body: unknown = [];
    if (p.endsWith("/me"))
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: false },
        devices: ["DEMO"],
      };
    else if (p.endsWith("/photo")) return r.fulfill({ status: 404, json: {} });
    else if (p === "/v1/shares")
      body = [
        {
          id: 1,
          device_id: "DEMO",
          token,
          config,
          enabled: true,
          expires_at: null,
          revision: 1,
          password_protected: false,
        },
      ];
    else if (p.endsWith("/preview")) {
      preview = r.request().postDataJSON();
      body = {
        ...fixture(),
        widgets: fixture().widgets.filter((w) =>
          preview.config.widgets.includes(w.key),
        ),
      };
    }
    await r.fulfill({ json: body });
  });
  await page.goto("/#Shares");
  await page.getByRole("button", { name: "Edit", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Remove Workout count", exact: true }),
  ).toBeVisible();
  for (const name of ["Every day", "Recent activities", "By sport"])
    await expect(
      page.getByRole("button", { name: `Add ${name}`, exact: true }),
    ).toBeEnabled();
  await page
    .getByRole("button", { name: "Add Every day", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Add Recent activities", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
  await expect(
    page.getByRole("heading", { name: "Recent activities", exact: true }),
  ).toBeVisible();
  expect([...preview.config.widgets].sort()).toEqual([
    "activity_heatmap",
    "recent_workouts",
    "workouts",
  ]);
  const cell = page
    .locator(
      '.dashboard-canvas .training-heatmap button[data-level="3"]:not(:disabled)',
    )
    .first();
  expect(
    await cell.evaluate((el) => getComputedStyle(el).backgroundColor),
  ).toBe("rgb(57, 124, 175)");
  const labels = await page
    .locator(".dashboard-canvas .heatmap-months span")
    .evaluateAll((nodes) => nodes.map((n) => n.getBoundingClientRect().top));
  expect(new Set(labels).size).toBe(1);
  await page.screenshot({
    path: "/tmp/zoop-rich-widgets-editor.png",
    fullPage: true,
  });
});
test("empty richer widgets remain honest", async ({ page }) => {
  await page.route("**/v1/**", (r) =>
    r.fulfill({
      json: {
        ...fixture("2026-10-22"),
        widgets: [
          { key: "activity_heatmap", points: [], activities: [] },
          { key: "by_sport", sports: [] },
          { key: "recent_workouts", activities: [] },
        ],
      },
    }),
  );
  await page.goto("/#share/" + token);
  await expect(page.getByText("No workouts in this period")).toHaveCount(2);
  await expect(
    page.getByRole("button", {
      name: /November 20, 2026, No load recorded, 0 workouts/,
    }),
  ).toBeVisible();
});

test("heatmap keeps recent history on resize without stealing an older selection", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await publicPage(page);
  const scroll = page.locator(".heatmap-scroll");
  await page.setViewportSize({ width: 390, height: 900 });
  await expect
    .poll(() =>
      scroll.evaluate((e) => e.scrollWidth - e.clientWidth - e.scrollLeft),
    )
    .toBeLessThan(3);
  await scroll.evaluate((e) => {
    e.scrollLeft = 150;
  });
  await expect.poll(() => scroll.evaluate((e) => e.scrollLeft)).toBe(150);
  await page.waitForTimeout(100);
  await page.setViewportSize({ width: 450, height: 900 });
  await expect.poll(() => scroll.evaluate((e) => e.scrollLeft)).toBe(150);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await expect
    .poll(() => scroll.evaluate((e) => e.scrollWidth - e.clientWidth))
    .toBe(0);
  await page.evaluate(
    () =>
      new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
  );
  await page.setViewportSize({ width: 390, height: 900 });
  await expect
    .poll(() =>
      scroll.evaluate((e) => e.scrollWidth - e.clientWidth - e.scrollLeft),
    )
    .toBeLessThan(3);
});
