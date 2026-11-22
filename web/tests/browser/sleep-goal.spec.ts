import { test, expect } from "@playwright/test";

for (const [seconds, minutes, fraction] of [
  [21600, 480, 0.75],
  [28800, 480, 1],
  [30240, 480, 1],
  [28800, 600, 0.8],
  [null, 480, null],
] as const) {
  test(`private and shared sleep rings agree: ${seconds} seconds / ${minutes} minutes`, async ({
    page,
  }, info) => {
    const day = new Date().toISOString().slice(0, 10);
    await page.route("**/v1/**", async (route) => {
      const path = new URL(route.request().url()).pathname;
      let body: unknown = [];
      if (path.endsWith("/setup")) body = { available: false };
      else if (path.endsWith("/me"))
        body = {
          account: { id: 1, email: "demo@example.test", is_admin: false },
          devices: ["DEMO"],
        };
      else if (path.endsWith("/profile")) body = { tz: "UTC" };
      else if (path.endsWith("/sleep-goal"))
        body = { minutes, configured: true };
      else if (path.endsWith("/weight-goal"))
        body = { goal: null, summary: null };
      else if (path.endsWith("/insights"))
        body = {
          state: "insufficient",
          outlook: { state: "insufficient" },
          metrics: [],
        };
      else if (path.endsWith("/sleep-sessions"))
        body =
          seconds == null
            ? []
            : [
                {
                  id: 1,
                  kind: "main",
                  start_ts: day + "T00:00:00Z",
                  end_ts: day + "T09:00:00Z",
                  sleep: {
                    window: { asleep_s: seconds },
                    physiology: {},
                    stages: {},
                  },
                },
              ];
      else if (path === "/v1/public/dashboard") {
        expect(route.request().headers().cookie).toBeUndefined();
        body = {
          title: "Sleep",
          timezone: "UTC",
          from: day,
          to: day,
          paged: false,
          widgets: [
            {
              key: "daily_rings",
              day,
              sleep_seconds: seconds,
              sleep_goal_minutes: minutes,
              load: null,
              recovery: null,
            },
          ],
        };
      }
      await route.fulfill({ json: body });
    });
    await page.goto("/");
    const ring = page.locator(".rings .ring-item").first();
    await expect(ring).toContainText("Sleep");
    const arc = ring.locator("circle[stroke-dasharray]");
    if (fraction == null) await expect(arc).toHaveCount(0);
    else
      await expect(arc).toHaveAttribute(
        "stroke-dasharray",
        `${383 * fraction} 383`,
      );
    const reading = await ring.locator("strong").innerText();
    await page.goto("/#share/" + "e".repeat(64));
    await expect(page.locator(".shared-rings")).toBeVisible();
    await expect(ring.locator("strong")).toHaveText(reading);
    if (fraction == null) await expect(arc).toHaveCount(0);
    else
      await expect(arc).toHaveAttribute(
        "stroke-dasharray",
        `${383 * fraction} 383`,
      );
    if (seconds === 30240) {
      for (const width of [320, 1440]) {
        await page.setViewportSize({ width, height: 900 });
        await page.screenshot({
          path: info.outputPath(`sleep-full-${width}.png`),
        });
      }
    }
  });
}
