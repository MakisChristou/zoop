import { test, expect, type Page } from "@playwright/test";
const day = new Date().toISOString().slice(0, 10);
async function fixture(page: Page, missing = false) {
  const night = {
    id: 1,
    kind: "main",
    start_ts: `${day}T01:00:00Z`,
    end_ts: `${day}T10:02:00Z`,
    timezone: "UTC",
    sleep: {
      window: {
        onset: `${day}T02:43:00Z`,
        offset: `${day}T10:02:00Z`,
        asleep_s: 26340,
        efficiency: 0.98,
        waso_s: 120,
      },
      physiology: { resting_hr: 50, hrv_rmssd_ms: 83 },
      stages: { deep_s: 4320, rem_s: 8400, light_s: 13440, wake_s: 120 },
      segments: missing
        ? []
        : [
            {
              stage: "deep",
              start: `${day}T02:43:00Z`,
              end: `${day}T03:00:00Z`,
            },
            {
              stage: "light",
              start: `${day}T03:00:00Z`,
              end: `${day}T04:00:00Z`,
            },
            {
              stage: "rem",
              start: `${day}T04:20:00Z`,
              end: `${day}T05:00:00Z`,
            },
            {
              stage: "wake",
              start: `${day}T06:00:00Z`,
              end: `${day}T06:02:00Z`,
            },
            {
              stage: "light",
              start: `${day}T06:02:00Z`,
              end: `${day}T08:00:00Z`,
            },
            {
              stage: "deep",
              start: `${day}T08:00:00Z`,
              end: `${day}T08:55:00Z`,
            },
            {
              stage: "rem",
              start: `${day}T08:55:00Z`,
              end: `${day}T10:02:00Z`,
            },
          ],
    },
  };
  const writes: string[] = [];
  await page.route("**/v1/**", (route) => {
    if (route.request().method() !== "GET") writes.push(route.request().url());
    const path = new URL(route.request().url()).pathname;
    const json = path.endsWith("/me")
      ? {
          account: { id: 1, email: "demo@example.test", is_admin: false },
          devices: ["DEMO"],
        }
      : path.endsWith("/profile")
        ? { tz: "UTC" }
        : path.endsWith("/sleep-sessions")
          ? [night]
          : path.endsWith("/weight-goal")
            ? { goal: null, summary: null }
            : path.endsWith("/insights")
              ? {
                  state: "learning",
                  outlook: { state: "learning" },
                  metrics: [],
                }
              : [];
    return route.fulfill({ json });
  });
  return writes;
}
for (const width of [320, 390, 1440, 2560]) {
  test(`sleep card matches the approved hierarchy at ${width}`, async ({
    page,
  }) => {
    const writes = await fixture(page);
    await page.setViewportSize({ width, height: 1000 });
    await page.goto("/#Sleep");
    await expect(page.locator(".sleep-night-duration")).toHaveText("7h 19m");
    await expect(page.locator(".sleep-stage-plot rect")).toHaveCount(7);
    await expect(page.locator(".sleep-stage-times")).toHaveText(
      "03:0006:0009:00",
    );
    await expect(page.locator(".sleep-times")).toContainText("02:43");
    await expect(page.locator(".stage-grid > div").first()).toContainText(
      "17%",
    );
    await expect(
      page.getByRole("img", { name: "Sleep stages from 02:43 to 10:02" }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Sleep duration", exact: true }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({
      path: `test-results/sleep-card-${width}.png`,
      fullPage: true,
    });
    await page.getByRole("button", { name: "Open sleep details" }).focus();
    await page.keyboard.press("Enter");
    await expect(
      page.getByRole("button", { name: "Back", exact: true }),
    ).toBeVisible();
    await expect(page.getByText("Load", { exact: true })).toHaveCount(0);
    await expect(page.locator(".sleep-night-duration")).toHaveText("7h 19m");
    await page.getByRole("button", { name: "Back", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "Open sleep details" }),
    ).toBeVisible();
    expect(writes).toHaveLength(0);
  });
}
test("missing stages keep the duration without inventing a timeline", async ({
  page,
}) => {
  await fixture(page, true);
  await page.goto("/#Sleep");
  await expect(page.getByText("Stages unavailable")).toBeVisible();
  await expect(page.locator(".sleep-night-duration")).toHaveText("7h 19m");
  await expect(page.locator(".sleep-stage-plot rect")).toHaveCount(0);
});
test("sleep card survives enlarged text and RTL", async ({ page }) => {
  await fixture(page);
  await page.setViewportSize({ width: 640, height: 900 });
  await page.goto("/#Sleep");
  await expect(page.locator(".sleep-stage-plot rect")).toHaveCount(7);
  await page.evaluate(() => {
    document.documentElement.style.zoom = "2";
    document.documentElement.dir = "rtl";
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.getByRole("button", { name: "Open sleep details" }).click();
  await expect(
    page.getByRole("button", { name: "Back", exact: true }),
  ).toBeVisible();
});
