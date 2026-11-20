import { test, expect, type Page } from "@playwright/test";
const day = (offset: number) => {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
};
async function fixture(page: Page) {
  let goal = {
    id: 1,
    revision: 1,
    active: true,
    started_at: day(-4) + "T08:00:00Z",
    pace_started_at: day(-4) + "T08:00:00Z",
    updated_at: day(0) + "T08:00:00Z",
    timezone: "UTC",
    finish_date: day(24),
    weekly_loss_kg: 0.35,
    daily_steps_goal: null,
    reminder_enabled: false,
    reminder_weekday: 1,
    reminder_minute: 1200,
  };
  const summary = {
    algorithm_version: 1,
    start: day(-4),
    end: day(2),
    state: "starting",
    week_number: 1,
    median_kg: 64.2,
    change_kg: null,
    weeks: [{ start: day(-4), end: day(2), median_kg: 64.2, count: 5 }],
    progress: {
      weigh_ins: [64.6, 64.2, 64.4, 64, 63.9].map((kg, i) => ({
        day: day(i - 4),
        kg,
      })),
      starting_weight_kg: 64.6,
      current_weight_kg: 63.9,
      total_lost_kg: 0.7,
      target_weight_kg: 63.2,
      finish_date: day(24),
      completed: false,
    },
  };
  const history: any[] = [];
  let fail = false;
  const writes: any[] = [];
  await page.route("**/v1/**", async (route) => {
    const req = route.request(),
      path = new URL(req.url()).pathname;
    let body: unknown = [],
      status = 200;
    if (path.endsWith("/me"))
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: false },
        devices: ["DEMO"],
      };
    else if (path.endsWith("/profile")) body = { tz: "UTC" };
    else if (path.endsWith("/weight-goal")) {
      if (req.method() === "PUT") {
        const q = req.postDataJSON();
        writes.push(q);
        if (fail) {
          status = 409;
          body = {
            error: { message: "Your goal changed. Refresh before saving." },
          };
          fail = false;
        } else {
          if (goal.active && !q.active)
            history.unshift({
              id: goal.id,
              goal: { ...goal },
              summary,
              ended_at: new Date().toISOString(),
              end_reason: "manual",
            });
          if (!goal.active && q.active)
            goal = {
              ...goal,
              id: goal.id + 1,
              started_at: new Date().toISOString(),
            };
          goal = { ...goal, ...q, revision: goal.revision + 1 };
          body = goal;
        }
      } else body = { goal, summary: goal.active ? summary : null };
    } else if (path.endsWith("/weight-goals"))
      body = { items: history, next_cursor: null };
    else if (path.includes("/weight-goals/"))
      body = history.find((p) => String(p.id) === path.split("/").at(-1));
    else if (path.endsWith("/insights"))
      body = { state: "learning", outlook: { state: "learning" }, metrics: [] };
    await route.fulfill({
      status,
      contentType: "application/json",
      body: JSON.stringify(body),
    });
  });
  return {
    writes,
    endElsewhere: () => {
      history.unshift({
        id: goal.id,
        goal: { ...goal },
        summary,
        ended_at: new Date().toISOString(),
        end_reason: "manual",
      });
      goal = { ...goal, active: false, revision: goal.revision + 1 };
    },
    failNext: () => {
      fail = true;
    },
  };
}
test("end, inspect history, and start a distinct cut on web", async ({
  page,
}) => {
  const f = await fixture(page);
  await page.goto("/#Goals");
  await expect(
    page.getByRole("heading", { name: "Progress", exact: true }),
  ).toBeVisible();
  await page.getByLabel("Goal options").click();
  await page.getByRole("button", { name: "End goal", exact: true }).click();
  await expect(
    page.getByRole("dialog", { name: "End this cut?" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Keep going" }).click();
  expect(f.writes).toHaveLength(0);
  await page.getByRole("button", { name: "End goal", exact: true }).click();
  await page.getByRole("button", { name: "End cut", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Maintenance", exact: true }),
  ).toBeVisible();
  await expect(page.getByText("Ended early", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: /Cut Ended early/ }).click();
  await expect(
    page.getByRole("dialog", { name: "Cut", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Close", exact: true }).click();
  await page.getByRole("button", { name: "Start a goal" }).click();
  await page.getByLabel("Weekly loss · kg").fill("0.4");
  await page.getByRole("button", { name: "Start cut", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Cut", exact: true }),
  ).toBeVisible();
  expect(f.writes).toHaveLength(2);
  expect(f.writes[1].revision).toBe(2);
  await page.screenshot({
    path: "test-results/goals-lifecycle.png",
    fullPage: true,
  });
});
test("conflict keeps edit draft and prevents a false success", async ({
  page,
}) => {
  const f = await fixture(page);
  await page.goto("/#Goals");
  await page.getByLabel("Goal options").click();
  await page.getByRole("button", { name: "Edit goal" }).click();
  await page.getByLabel("Weekly loss · kg").fill("0.6");
  f.failNext();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("Your goal changed");
  await expect(page.getByLabel("Weekly loss · kg")).toHaveValue("0.6");
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeDisabled();
  await page.getByRole("button", { name: "Discard edits and reload" }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
});
for (const width of [320, 768, 1440, 2560]) {
  test("goal layout at " + width, async ({ page }) => {
    await fixture(page);
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/#Goals");
    await expect(
      page.getByRole("heading", { name: "Progress", exact: true }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: "test-results/goals-" + width + ".png",
      fullPage: true,
    });
  });
}

test("refresh picks up an iPhone closure without leaving Goals", async ({
  page,
}) => {
  const f = await fixture(page);
  await page.goto("/#Goals");
  await expect(
    page.getByRole("heading", { name: "Progress", exact: true }),
  ).toBeVisible();
  f.endElsewhere();
  await page.getByRole("button", { name: "Refresh data" }).click();
  await expect(
    page.getByRole("heading", { name: "Maintenance", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Past goals", exact: true }),
  ).toBeVisible();
});
