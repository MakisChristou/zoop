import { test, expect, type Page } from "@playwright/test";
const day = (offset: number) => {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
};
async function fixture(
  page: Page,
  phase: "cut" | "bulk" | "maintenance" = "cut",
  showcase = false,
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
    daily_steps_goal: showcase ? 10000 : null,
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
  const history: any[] = showcase
    ? [
        {
          id: 10,
          goal: { ...goal, started_at: day(-46) + "T08:00:00Z", active: false },
          ended_at: day(-5) + "T00:00:00Z",
          end_reason: "manual",
          summary: {
            ...summary,
            progress: { ...summary.progress, total_lost_kg: 1.2 },
          },
        },
        {
          id: 11,
          goal: {
            ...goal,
            phase: "maintenance",
            started_at: day(-80) + "T08:00:00Z",
            finish_date: null,
            active: false,
          },
          ended_at: day(-46) + "T00:00:00Z",
          end_reason: "replaced",
          summary: {
            ...summary,
            progress: {
              ...summary.progress,
              total_lost_kg: -0.1,
              target_weight_kg: null,
            },
          },
        },
      ]
    : [];
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
    else if (path.endsWith("/days"))
      body = [{ day: day(0), steps: 9500, steps_walking: 8000 }];
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
    addEarlierWeek: () => {
      goal.started_at = day(-11) + "T08:00:00Z";
      summary.weeks.unshift({
        start: day(-11),
        end: day(-5),
        median_kg: 64.8,
        count: 5,
      });
      summary.progress.weigh_ins.unshift({ day: day(-10), kg: 64.8 });
    },
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
  await page.getByRole("button", { name: /Cut .*Ended early/ }).click();
  await expect(
    page.getByRole("dialog", { name: "Cut", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Close", exact: true }).click();
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

for (const width of [320, 390, 768, 1440, 2560]) {
  test(`approved composition with steps and history at ${width}`, async ({
    page,
  }) => {
    const f = await fixture(page, "cut", true);
    await page.setViewportSize({ width, height: 1000 });
    await page.goto("/#Goals");
    await expect(
      page.getByRole("progressbar", { name: "Steps today" }),
    ).toHaveAttribute("aria-valuenow", "80");
    await expect(page.getByText("8,000 / 10,000")).toBeVisible();
    const weight = await page.locator(".goal-weight").boundingBox();
    const progress = await page.locator(".goal-progress").boundingBox();
    const history = await page.locator(".goal-history").boundingBox();
    if (width > 900) {
      expect(weight!.y).toBe(progress!.y);
      expect(weight!.height).toBe(progress!.height);
      expect(weight!.width / progress!.width).toBeCloseTo(1.7, 1);
    } else expect(progress!.y).toBeGreaterThan(weight!.y + weight!.height);
    expect(history!.y).toBeGreaterThan(progress!.y + progress!.height);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({
      path: `test-results/goals-approved-${width}.png`,
      fullPage: true,
    });
    expect(f.writes).toHaveLength(0);
  });
}

test("weekly browsing stays inline and never gives older weeks today's status", async ({
  page,
}) => {
  const f = await fixture(page);
  f.addEarlierWeek();
  await page.goto("/#Goals");
  await expect(page.locator(".goal-status")).toHaveText("On pace");
  await page.getByRole("button", { name: "Weekly", exact: true }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Weekly", exact: true }),
  ).toBeFocused();
  await expect(page.locator(".goal-current-weight")).toHaveText("64.2 kg");
  await page.getByLabel("Previous goal week").click();
  await expect(page.locator(".goal-current-weight")).toHaveText("64.8 kg");
  await expect(page.getByText("On pace", { exact: true })).toHaveCount(0);
  await expect(page.getByLabel("Previous goal week")).toBeDisabled();
  await page.screenshot({
    path: "test-results/goals-weekly.png",
    fullPage: true,
  });
  await page.getByLabel("Next goal week").click();
  await expect(page.getByText("On pace", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Phase", exact: true }).click();
  const chart = page.getByRole("group", { name: "kg history", exact: true });
  await chart.focus();
  await page.keyboard.press("End");
  await expect(page.locator(".chart-tooltip")).toContainText("63.9");
  expect(f.writes).toHaveLength(0);
});

test("dialogs restore visible focus and mobile editor fits at 200 percent", async ({
  page,
}) => {
  await fixture(page);
  await page.goto("/#Goals");
  const edit = page.locator(".goal-edit");
  await edit.click();
  await page.keyboard.press("Escape");
  await expect(edit).toBeFocused();
  await page.setViewportSize({ width: 640, height: 900 });
  await page.evaluate(() => (document.documentElement.style.zoom = "2"));
  const options = page.getByLabel("Goal options");
  await options.click();
  await page.getByRole("button", { name: "Edit goal", exact: true }).click();
  expect(
    await page
      .getByLabel("Weekly loss · kg")
      .evaluate((el) => getComputedStyle(el).fontSize),
  ).toBe("16px");
  expect(
    await page
      .getByRole("dialog")
      .evaluate((el) => el.scrollWidth <= el.clientWidth),
  ).toBe(true);
  await page.keyboard.press("Escape");
  await expect(options).toBeFocused();
});

test("RTL target label fits and maintenance has no artificial deadline", async ({
  page,
}) => {
  await fixture(page);
  await page.setViewportSize({ width: 320, height: 900 });
  await page.goto("/#Goals");
  await page.evaluate(() => (document.documentElement.dir = "rtl"));
  const label = page.locator(".goal-weight .recharts-reference-line text");
  await expect(label).toHaveText("Target");
  await expect
    .poll(() =>
      label.evaluate((el) => {
        const label = el.getBoundingClientRect();
        const plot = el.closest(".chart")!.getBoundingClientRect();
        return (
          label.width > 0 &&
          label.left >= plot.left &&
          label.right <= plot.right
        );
      }),
    )
    .toBe(true);
  await page.screenshot({ path: "test-results/goals-rtl.png", fullPage: true });
  await fixture(page, "maintenance");
  await page.reload();
  await expect(page.getByText("Maintaining", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("progressbar", { name: "Time", exact: true }),
  ).toHaveCount(0);
  await expect(page.getByText(/days left/)).toHaveCount(0);
  await expect(
    page.getByRole("progressbar", { name: "Steps today" }),
  ).toHaveCount(0);
});

test("failed goal fetch is shown once and retry restores the page", async ({
  page,
}) => {
  await fixture(page);
  await page.route("**/weight-goal", (r) =>
    r.fulfill({
      status: 503,
      json: { error: { message: "Could not load goal." } },
    }),
  );
  await page.goto("/#Goals");
  await expect(page.getByRole("alert")).toHaveCount(1);
  await expect(page.getByRole("alert")).toContainText("Could not load goal.");
  await page.unroute("**/weight-goal");
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Progress", exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("goal loading retains readings and partial history failure stays local", async ({
  page,
}) => {
  await fixture(page, "cut", true);
  await page.goto("/#Goals");
  await expect(page.locator(".goal-current-weight")).toHaveText("63.9 kg");
  await expect(page.locator(".goal-history .goal-period-row")).toHaveCount(2);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  await page.route("**/weight-goal", async (route) => {
    await gate;
    await route.fallback();
  });
  await page.route("**/weight-goals", (route) =>
    route.fulfill({
      status: 503,
      json: { error: { message: "History unavailable" } },
    }),
  );
  await page.getByRole("button", { name: "Refresh data" }).click();
  await expect(
    page.getByRole("progressbar", { name: "Loading data" }),
  ).toBeVisible();
  await expect(page.locator(".goal-current-weight")).toHaveText("63.9 kg");
  release();
  await expect(page.getByRole("alert")).toContainText("History unavailable");
  await expect(page.locator(".goal-current-weight")).toHaveText("63.9 kg");
  await expect(page.locator(".goal-history .goal-period-row")).toHaveCount(2);
});

test("empty goals stay actionable without inventing readings or history", async ({
  page,
}) => {
  await fixture(page);
  await page.route("**/weight-goal", (route) =>
    route.fulfill({ json: { goal: null, summary: null } }),
  );
  await page.goto("/#Goals");
  await expect(
    page.getByRole("button", { name: "Start a goal" }),
  ).toBeEnabled();
  await expect(page.locator(".goal-current-weight")).toHaveText("— kg");
  await expect(page.locator(".goal-history")).toHaveCount(0);
  await expect(page.locator(".goal-progress")).toHaveCount(0);
});
