import { test, expect } from "@playwright/test";
const token = "c".repeat(64);
const config = {
  title: "Training",
  range: "last30",
  widgets: ["daily_rings", "activity_heatmap", "recent_workouts", "by_sport"],
  display_name: "",
  show_photo: false,
};
function dashboard(layout = [] as { key: string; x: number; y: number }[]) {
  return {
    title: "Training",
    display_name: "",
    photo: null,
    timezone: "UTC",
    from: "2026-10-22",
    to: "2026-11-20",
    paged: false,
    first_year: 2026,
    last_year: 2026,
    layout,
    widgets: [
      {
        key: "daily_rings",
        day: "2026-11-20",
        sleep_seconds: 27000,
        load: 12.3,
        recovery: {
          version: 1,
          method: "zoop-recovery-v1",
          score: 73,
          band: "high",
          state: "ready",
        },
      },
      {
        key: "activity_heatmap",
        points: Array.from({ length: 30 }, (_, i) => ({
          day: new Date(Date.UTC(2026, 9, 22 + i)).toISOString().slice(0, 10),
          value: (i % 4) + 8,
        })),
        activities: [],
      },
      {
        key: "recent_workouts",
        activities: Array.from({ length: 16 }, (_, i) => ({
          day: `2026-11-${20 - Math.floor(i / 2)}`,
          kind: i % 2 ? "walk" : "resistance",
          duration_s: 2700,
          load: 9,
        })),
      },
      {
        key: "by_sport",
        sports: [
          { kind: "resistance", seconds: 21600, count: 8 },
          { kind: "walk", seconds: 21600, count: 8 },
        ],
      },
    ],
  };
}
for (const width of [320, 768, 1440, 2560])
  test(`fixed shared widgets and daily rings at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1100 });
    const paths: string[] = [];
    await page.route("**/v1/**", async (r) => {
      paths.push(new URL(r.request().url()).pathname);
      await r.fulfill({ json: dashboard() });
    });
    await page.goto("/#share/" + token);
    await expect(page.locator(".shared-rings .ring-item")).toHaveCount(3);
    await expect(page.locator(".shared-rings")).toContainText("7h 30m");
    await expect(page.locator(".shared-rings")).toContainText("73");
    await expect(page.locator(".shared-rings")).toContainText("12.3");
    await expect(page.locator(".shared-rings button")).toHaveCount(0);
    const circles = await page
      .locator(".shared-rings .ring")
      .evaluateAll((els) => els.map((e) => e.getBoundingClientRect().width));
    expect(new Set(circles).size).toBe(1);
    const heatmap = page.locator(".shared-activity_heatmap"),
      timeline = page.locator(".shared-recent_workouts");
    if (width >= 768) {
      const h = (await heatmap.boundingBox())!,
        t = (await timeline.boundingBox())!;
      expect(h.width).toBeGreaterThan(t.width * 1.9);
      expect(h.height).toBe(272);
      expect(t.height).toBe(752);
    }
    await expect(
      page.locator(".training-heatmap button:not(:disabled)"),
    ).toHaveCount(30);
    await expect(page.locator(".training-heatmap button:disabled")).toHaveCount(
      341,
    );
    const before = (await timeline.boundingBox())!.height;
    await page.getByRole("button", { name: "Next workouts" }).click();
    expect((await timeline.boundingBox())!.height).toBe(before);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `/tmp/zoop-fixed-rings-${width}.png`,
      fullPage: true,
    });
    expect(paths.every((p) => p === "/v1/public/dashboard")).toBe(true);
  });
test("arrange snaps by pointer and keyboard, saves placements and reopens them", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 1100 });
  let saved: any;
  await page.route("**/v1/**", async (r) => {
    const p = new URL(r.request().url()).pathname;
    let body: any = [];
    if (p.endsWith("/me"))
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: false },
        devices: ["DEMO"],
      };
    else if (p.endsWith("/photo")) return r.fulfill({ status: 404, json: {} });
    else if (p === "/v1/shares" && r.request().method() === "POST") {
      saved = r.request().postDataJSON();
      body = { ...saved, id: 1, token, revision: 1 };
    } else if (p === "/v1/shares")
      body = saved ? [{ ...saved, id: 1, token, revision: 1 }] : [];
    else if (p.endsWith("/preview")) {
      const c = r.request().postDataJSON().config;
      body = {
        ...dashboard(c.layout),
        widgets: dashboard().widgets.filter((w) => c.widgets.includes(w.key)),
      };
    } else if (p === "/v1/public/dashboard")
      body = dashboard(saved.config.layout);
    await r.fulfill({ json: body });
  });
  await page.goto("/#Shares");
  await page.getByRole("button", { name: "New dashboard" }).click();
  for (const name of [
    "Sleep",
    "Weight",
    "Steps",
    "Recent activities",
    "Daily rings",
  ])
    await page
      .getByRole("button", { name: `Remove ${name}`, exact: true })
      .click();
  for (const name of [
    "Daily rings",
    "Every day",
    "Recent activities",
    "By sport",
  ])
    await page
      .getByRole("button", { name: `Add ${name}`, exact: true })
      .click();
  await page
    .getByRole("button", { name: "Sharing settings", exact: true })
    .first()
    .click();
  await expect(
    page.getByRole("combobox", { name: "Heatmap history" }),
  ).toHaveValue("dashboard");
  await page
    .getByRole("combobox", { name: "Heatmap history" })
    .selectOption("year");
  await page
    .getByRole("button", { name: "Sharing settings", exact: true })
    .first()
    .click();
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
  const handle = page.getByRole("button", {
      name: "Move By sport",
      exact: true,
    }),
    before = await page.locator(".shared-by_sport").getAttribute("style");
  await handle.focus();
  await page.keyboard.press("ArrowDown");
  expect(await page.locator(".shared-by_sport").getAttribute("style")).not.toBe(
    before,
  );
  const afterKey = await page
    .locator(".shared-by_sport")
    .evaluate((el) => Number(getComputedStyle(el).gridRowStart));
  await handle.evaluate((el) => el.scrollIntoView({ block: "center" }));
  const box = (await handle.boundingBox())!;
  await page.mouse.move(box.x + 12, box.y + 12);
  await page.mouse.down();
  await page.mouse.move(box.x + 12, box.y + 108, { steps: 5 });
  await page.mouse.up();
  expect(
    await page
      .locator(".shared-by_sport")
      .evaluate((el) => Number(getComputedStyle(el).gridRowStart)),
  ).toBe(afterKey + 1);
  await page.screenshot({
    path: "/tmp/zoop-layout-editor.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Save", exact: true }).click();
  expect(saved.config.layout).toHaveLength(4);
  expect(saved.config.heatmap_year).toBe(true);
  await page.goto("/#share/" + token);
  await expect(page.locator(".shared-rings")).toBeVisible();
  for (const p of saved.config.layout)
    expect(
      await page
        .locator(`.shared-${p.key}`)
        .evaluate((el) => getComputedStyle(el).gridRowStart),
    ).toBe(String(p.y + 1));
});
test("unavailable recovery and missing day values stay empty", async ({
  page,
}) => {
  const data = dashboard();
  data.widgets = [
    {
      key: "daily_rings",
      day: "2026-11-20",
      sleep_seconds: null,
      load: null,
      recovery: {
        version: 1,
        method: "zoop-recovery-v1",
        score: null,
        band: null,
        state: "learning",
      },
    },
  ] as any;
  await page.route("**/v1/**", (r) => r.fulfill({ json: data }));
  await page.goto("/#share/" + token);
  await expect(page.locator(".shared-rings .ring-reading strong")).toHaveText([
    "—",
    "—",
    "—",
  ]);
  await expect(
    page.locator(".shared-rings circle[stroke-dasharray]"),
  ).toHaveCount(0);
});

test("independent heatmap year enables only its own calendar", async ({
  page,
}) => {
  const data = dashboard();
  Object.assign(data.widgets[1], { from: "2025-11-21", to: "2026-11-20" });
  await page.route("**/v1/**", (r) => r.fulfill({ json: data }));
  await page.goto("/#share/" + token);
  await expect(
    page.locator(".training-heatmap button:not(:disabled)"),
  ).toHaveCount(365);
  await expect(page.locator(".training-heatmap button:disabled")).toHaveCount(
    6,
  );
  await page.evaluate(() => (document.documentElement.dir = "rtl"));
  await page.setViewportSize({ width: 640, height: 1000 });
  await page.evaluate(() => (document.body.style.zoom = "2"));
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test.describe("touch footprints", () => {
  test.use({ hasTouch: true, isMobile: true });
  for (const width of [390, 1024])
    test(`heatmap stays inside its fixed card at ${width}`, async ({
      page,
    }) => {
      await page.setViewportSize({ width, height: 1000 });
      await page.route("**/v1/**", (r) => r.fulfill({ json: dashboard() }));
      await page.goto("/#share/" + token);
      const card = (await page
        .locator(".shared-activity_heatmap")
        .boundingBox())!;
      const legend = (await page.locator(".heatmap-legend").boundingBox())!;
      expect(legend.y + legend.height).toBeLessThan(card.y + card.height - 8);
      await page.screenshot({
        path: `/tmp/zoop-shared-touch-${width}.png`,
        fullPage: true,
      });
    });
});
