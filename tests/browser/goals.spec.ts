import { test, expect, type Page } from "@playwright/test";
const day = (offset: number) => {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
};
async function fixture(
  page: Page,
  phase: "cut" | "bulk" | "maintenance" = "cut",
) {
  let goal = {
    phase,
    maintenance_reference_kg: phase === "maintenance" ? 64 : null,
    maintenance_range_pct: 1,
    id: 1,
    revision: 1,
    active: true,
    started_at: day(-4) + "T08:00:00Z",
    pace_started_at: day(-4) + "T08:00:00Z",
    updated_at: day(0) + "T08:00:00Z",
    timezone: "UTC",
    finish_date: phase === "maintenance" ? null : day(24),
    weekly_loss_kg: 0.35,
    daily_steps_goal: null,
    reminder_enabled: false,
    reminder_weekday: 1,
    reminder_minute: 1200,
  };
  let summary = {
    algorithm_version: 2,
    maintenance_lower_kg: phase === "maintenance" ? 63.36 : null,
    maintenance_upper_kg: phase === "maintenance" ? 64.64 : null,
    start: day(-4),
    end: day(2),
    state: phase === "maintenance" ? "stable" : "on_pace",
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
          const replacement = !q.active || (q.phase && q.phase !== goal.phase);
          if (goal.active && replacement)
            history.unshift({
              id: goal.id,
              goal: { ...goal },
              summary,
              ended_at: new Date().toISOString(),
              end_reason: "manual",
            });
          const id = goal.id,
            revision = goal.revision;
          goal = { ...goal, ...q, revision: revision + 1 };
          if (replacement) {
            goal = {
              ...goal,
              id: id + 1,
              active: true,
              started_at: new Date().toISOString(),
              pace_started_at: new Date().toISOString(),
            };
            if (!q.active)
              goal = {
                ...goal,
                phase: "maintenance",
                weekly_loss_kg: 0,
                finish_date: null,
                daily_steps_goal: null,
                maintenance_reference_kg: null,
              };
            summary = {
              ...summary,
              state: "building_trend",
              maintenance_lower_kg: null,
              maintenance_upper_kg: null,
              progress: {
                ...summary.progress,
                target_weight_kg:
                  goal.phase === "maintenance" ? (null as any) : 63.2,
                weigh_ins: [],
              },
            };
          }
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
    page.getByRole("dialog", { name: "End this goal?" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Keep going" }).click();
  expect(f.writes).toHaveLength(0);
  await page.getByLabel("Goal options").click();
  await page.getByRole("button", { name: "End goal", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "End goal", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Maintenance", exact: true }),
  ).toBeVisible();
  await expect(page.getByText("Ended early", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: /Cut Ended early/ }).click();
  await expect(
    page.getByRole("dialog", { name: "Cut", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Close", exact: true }).click();
  await page.getByLabel("Goal options").click();
  await page.getByRole("button", { name: "Edit goal", exact: true }).click();
  await page.getByLabel("Goal", { exact: true }).selectOption("cut");
  await page.getByLabel("Weekly loss · kg").fill("0.4");
  await page.getByRole("button", { name: "Start goal", exact: true }).click();
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

for (const phase of ["bulk", "maintenance"] as const) {
  test(`${phase} has its own setup and responsive chart`, async ({ page }) => {
    const f = await fixture(page, phase);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/#Goals");
    await expect(
      page.getByRole("heading", {
        name: phase === "bulk" ? "Bulk" : "Maintenance",
        exact: true,
      }),
    ).toBeVisible();
    await page.screenshot({
      path: `test-results/phase-${phase}-mobile.png`,
      fullPage: true,
    });
    await page.getByLabel("Goal options").click();
    await page.getByRole("button", { name: "Edit goal", exact: true }).click();
    await expect(page.getByLabel("Goal", { exact: true })).toHaveValue(phase);
    if (phase === "maintenance") {
      await expect(page.getByLabel("Weekly loss · kg")).toHaveCount(0);
      await expect(page.getByLabel("Finish date")).toHaveCount(0);
      await page.getByLabel("Range · ±%").fill("1.5");
    } else await page.getByLabel("Weekly gain · kg").fill("0.2");
    await page.screenshot({
      path: `test-results/phase-${phase}-setup.png`,
      fullPage: true,
    });
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    expect(f.writes[0].phase).toBe(phase);
    if (phase === "maintenance") {
      expect(f.writes[0].weekly_loss_kg).toBe(0);
      expect(f.writes[0].finish_date).toBeNull();
    }
  });
}
