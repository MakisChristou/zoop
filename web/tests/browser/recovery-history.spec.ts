import { test, expect, type Page } from "@playwright/test";
import { addDays } from "../../src/calendar";
const today = new Date().toISOString().slice(0, 10);
function rows(from: string, to: string) {
  const result = [];
  for (let day = from, i = 0; day <= to; day = addDays(day, 1), i++) {
    if (i === 5 || i === 20) continue;
    const score =
      i === 0 ? 0 : [33, 34, 66, 67, 100, 76, 48, 81, 29, 56, 91][i % 11];
    result.push({
      day,
      recovery: {
        version: 1,
        method: "zoop-recovery-v1",
        state: "ready",
        score,
        band: score < 34 ? "low" : score < 67 ? "moderate" : "high",
      },
      hrv_ms: 77,
      resting_hr: 47,
    });
  }
  return result;
}
async function fixture(page: Page) {
  await page.route("**/v1/**", async (route) => {
    const url = new URL(route.request().url()),
      path = url.pathname;
    let body: unknown = [];
    if (path.endsWith("/setup")) body = { available: false };
    else if (path.endsWith("/me"))
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: false },
        devices: ["DEMO", "SECOND"],
      };
    else if (path.endsWith("/profile")) body = { tz: "UTC" };
    else if (path.endsWith("/insights"))
      body = { state: "ready", metrics: [], outlook: { state: "good" } };
    else if (path.endsWith("/weight-goal"))
      body = { goal: null, summary: null };
    else if (path.endsWith("/recovery"))
      body = rows(url.searchParams.get("from")!, url.searchParams.get("to")!);
    await route.fulfill({ json: body });
  });
  await page.goto("/#Trends");
  await expect(
    page.getByRole("heading", { name: "Daily recovery", exact: true }),
  ).toBeVisible();
}
test("daily chart preserves gaps, colours, keyboard selection and bounded ranges", async ({
  page,
}) => {
  await fixture(page);
  const card = page.locator(".recovery-history"),
    plot = card.getByRole("group", {
      name: "Daily recovery history",
      exact: true,
    });
  await expect(card.getByRole("table").getByRole("row")).toHaveCount(91);
  await expect(card.locator(".recharts-bar-rectangle path")).toHaveCount(88);
  for (const band of ["low", "moderate", "high"])
    await expect(
      card.locator(`path[fill="var(--recovery-${band})"]`).first(),
    ).toBeVisible();
  await plot.focus();
  await page.keyboard.press("Home");
  await expect(card.locator(".recovery-tooltip")).toContainText("0%");
  await expect(card.locator(".recovery-tooltip")).toContainText("77 ms");
  await page.keyboard.press("ArrowRight");
  await expect(card.locator(".recovery-tooltip")).toContainText("34%");
  await page.keyboard.press("Escape");
  await expect(card.locator(".recovery-tooltip")).toHaveCount(0);
  const request = page.waitForRequest((r) =>
    r.url().includes(`/recovery?from=${addDays(today, -29)}`),
  );
  await card.getByRole("button", { name: "30 days", exact: true }).click();
  await request;
  await expect(card.getByRole("table").getByRole("row")).toHaveCount(31);
  await expect(card.locator(".recharts-bar-rectangle path")).toHaveCount(28);
});
test("history preserves cached data on failure and clears on device changes", async ({
  page,
}) => {
  await fixture(page);
  const card = page.locator(".recovery-history");
  await expect(card.locator(".recharts-bar-rectangle path")).toHaveCount(88);
  await page.route("**/recovery?*", (route) =>
    route.fulfill({ status: 503, json: { error: { message: "Unavailable" } } }),
  );
  await page.getByRole("button", { name: "Refresh data", exact: true }).click();
  await expect(card.getByRole("alert")).toContainText(
    "Recovery history unavailable",
  );
  await expect(card.locator(".recharts-bar-rectangle path")).toHaveCount(88);
  await page.getByRole("combobox", { name: "Device" }).selectOption("SECOND");
  await expect(card.getByRole("alert")).toBeVisible();
  await expect(card.locator(".recharts-bar-rectangle path")).toHaveCount(0);
  await page.unroute("**/recovery?*");
  await card.getByRole("button", { name: "Retry" }).click();
  await expect(card.locator(".recharts-bar-rectangle path")).toHaveCount(88);
});
test("responsive recovery card, touch selection, loading and empty states", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await fixture(page);
  const card = page.locator(".recovery-history");
  for (const width of [320, 768, 1440, 2560]) {
    await page.setViewportSize({ width, height: 1000 });
    await expect(card.locator(".recharts-bar-rectangle path")).toHaveCount(88);
    await card
      .getByRole("group", { name: "Daily recovery history", exact: true })
      .focus();
    await page.keyboard.press("End");
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await card.screenshot({ path: `test-results/daily-recovery-${width}.png` });
  }
  await page.setViewportSize({ width: 320, height: 1000 });
  await page.evaluate(() => {
    document.documentElement.dir = "rtl";
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await card.screenshot({ path: "test-results/daily-recovery-rtl.png" });
  await page.evaluate(() => {
    document.documentElement.dir = "ltr";
    document.body.style.zoom = "1";
  });
  let finish: (() => void) | undefined;
  await page.route("**/recovery?*", async (route) => {
    await new Promise<void>((resolve) => {
      finish = resolve;
    });
    await route.fulfill({ json: [] });
  });
  await card.getByRole("button", { name: "30 days", exact: true }).click();
  await expect(
    card.getByRole("progressbar", { name: "Loading recovery history" }),
  ).toBeVisible();
  await expect(
    card.getByText("No recovery readings for this period"),
  ).toHaveCount(0);
  finish!();
  await expect(
    card.getByText("No recovery readings for this period"),
  ).toBeVisible();
  await expect(card.getByRole("progressbar")).toHaveCount(0);
});
test("touch can inspect a bar", async ({ browser }) => {
  const context = await browser.newContext({
    hasTouch: true,
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  await fixture(page);
  const card = page.locator(".recovery-history");
  await card.locator(".recharts-bar-rectangle path").nth(10).tap();
  await expect(card.locator(".recovery-tooltip")).toBeVisible();
  await context.close();
});
