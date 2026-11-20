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
    page.getByRole("checkbox", { name: "Workout count", exact: true }),
  ).toBeChecked();
  for (const name of ["Every day", "Recent activities", "By sport"])
    await expect(
      page.getByRole("checkbox", { name, exact: true }),
    ).not.toBeChecked();
  await page.getByRole("checkbox", { name: "Every day", exact: true }).check();
  await page
    .getByRole("checkbox", { name: "Recent activities", exact: true })
    .check();
  await page.getByRole("button", { name: "Preview", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Recent activities", exact: true }),
  ).toBeVisible();
  expect(preview.config.widgets).toEqual([
    "workouts",
    "activity_heatmap",
    "recent_workouts",
  ]);
  const cell = page
    .locator(
      '.share-preview .training-heatmap button[data-level="3"]:not(:disabled)',
    )
    .first();
  expect(
    await cell.evaluate((el) => getComputedStyle(el).backgroundColor),
  ).toBe("rgb(57, 124, 175)");
  const labels = await page
    .locator(".share-preview .heatmap-months span")
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

for (const width of [320, 768, 1440, 2560]) {
  test(`mixed widget orders keep compact heights at ${width}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 1100 });
    const data = fixture("2026-10-22");
    data.widgets = [data.widgets[2], data.widgets[0], data.widgets[1]];
    await page.route("**/v1/**", (route) => route.fulfill({ json: data }));
    await page.goto("/#share/" + token);
    const cards = page.locator(".shared-widget");
    await expect(cards).toHaveCount(3);
    await expect
      .poll(async () => Math.round((await cards.nth(1).boundingBox())!.height))
      .toBeLessThan(430);
    const boxes = await cards.evaluateAll((els) =>
      els.map((el) => {
        const r = el.getBoundingClientRect();
        return { x: r.x, y: r.y, w: r.width, h: r.height };
      }),
    );
    expect(boxes[2].h).toBeLessThan(350);
    if (width > 768) {
      expect(boxes[1].y).toBeCloseTo(boxes[0].y, 0);
      expect(boxes[2].x).toBeCloseTo(boxes[1].x, 0);
      expect(boxes[2].y - boxes[1].y - boxes[1].h).toBeGreaterThanOrEqual(15);
      expect(boxes[2].y - boxes[1].y - boxes[1].h).toBeLessThan(18);
    }
    for (let i = 0; i < boxes.length; i++)
      for (let j = i + 1; j < boxes.length; j++) {
        const a = boxes[i],
          b = boxes[j];
        expect(
          a.x + a.w <= b.x + 1 ||
            b.x + b.w <= a.x + 1 ||
            a.y + a.h <= b.y + 1 ||
            b.y + b.h <= a.y + 1,
        ).toBe(true);
      }
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `/tmp/zoop-layout-${width}.png`,
      fullPage: true,
    });
    await page.getByRole("button", { name: "Next workouts" }).click();
    await expect(page.locator(".timeline-entry")).toHaveCount(4);
    await expect
      .poll(async () => Math.round((await cards.nth(0).boundingBox())!.height))
      .toBeLessThan(650);
    await page.evaluate(() => {
      document.documentElement.dir = "rtl";
      document.documentElement.style.zoom = "2";
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  });
}

test("single widgets stay bounded and all mixed orders avoid stretching", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 1100 });
  const data = fixture("2026-10-22"),
    original = [...data.widgets];
  await page.route("**/v1/**", (route) => route.fulfill({ json: data }));
  for (const order of [
    [0],
    [1],
    [2],
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
  ]) {
    data.widgets = order.map((i) => original[i]);
    await page.goto("/#share/" + token);
    await page.reload();
    const cards = page.locator(".shared-widget");
    await expect(cards).toHaveCount(order.length);
    await expect
      .poll(async () =>
        cards.evaluateAll((els) =>
          els.every((el) => el.getBoundingClientRect().height > 100),
        ),
      )
      .toBe(true);
    if (order.length === 1) {
      const box = (await cards.first().boundingBox())!;
      expect(box.width).toBeLessThanOrEqual(540);
      expect(Math.abs(box.x + box.width / 2 - 720)).toBeLessThan(2);
    }
    for (let i = 0; i < order.length; i++)
      if (order[i] !== 2)
        expect((await cards.nth(i).boundingBox())!.height).toBeLessThan(430);
  }
});
