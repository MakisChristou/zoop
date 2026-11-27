import { test, expect } from "@playwright/test";
test("real API: private data, admin stats, read-only access and session logout", async ({
  page,
}) => {
  test.skip(
    process.env.ZOOP_E2E_REAL !== "1",
    "Requires isolated development API and fixture accounts",
  );
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/");
  await page.getByLabel("Email", { exact: true }).fill("admin@example.test");
  await page
    .getByLabel("Password", { exact: true })
    .fill(process.env.ZOOP_E2E_PASSWORD!);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Today", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".today-grid")).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.locator(".today-grid .panel-value").first()).toContainText(
    "64.2",
  );
  for (const name of ["Activity", "Sleep", "Trends", "Goals"]) {
    await page.getByRole("link", { name, exact: true }).click();
    await expect(
      page.getByRole("heading", { name, exact: true }),
    ).toBeVisible();
    await expect(page.getByRole("alert")).toHaveCount(0);
  }
  await page.getByRole("button", { name: "Edit goal", exact: true }).click();
  await page.getByLabel("Goal", { exact: true }).selectOption("cut");
  await page.getByRole("button", { name: "Start goal", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Cut", exact: true }),
  ).toBeVisible();
  const before = await (
    await page.request.get("/v1/devices/DEMO-A/weight-goal")
  ).json();
  await page.getByLabel("Goal options").click();
  await page.getByRole("button", { name: "End goal", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "End goal", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Maintenance", exact: true }),
  ).toBeVisible();
  const archive = await (
    await page.request.get("/v1/devices/DEMO-A/weight-goals")
  ).json();
  expect(
    archive.items.filter(
      (item: { goal: { phase: string } }) => item.goal.phase === "cut",
    ),
  ).toHaveLength(1);
  expect(archive.items[0].id).toBe(before.goal.id);
  expect(archive.items[0].summary.progress.current_weight_kg).toBe(64.2);
  expect(archive.items[0].summary.progress.total_lost_kg).toBe(0);
  await page.getByRole("button", { name: "Edit goal", exact: true }).click();
  await page.getByLabel("Goal", { exact: true }).selectOption("cut");
  await page.getByRole("button", { name: "Start goal", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Cut", exact: true }),
  ).toBeVisible();
  const after = await (
    await page.request.get("/v1/devices/DEMO-A/weight-goal")
  ).json();
  expect(after.goal.id).not.toBe(before.goal.id);
  expect((await page.request.get("/v1/devices/DEMO-B/profile")).status()).toBe(
    404,
  );
  expect(
    (
      await page.request.put("/v1/devices/DEMO-A/profile", { data: {} })
    ).status(),
  ).toBe(403);
  await page.getByRole("button", { name: "Account menu" }).click();
  await page
    .locator(".menu")
    .getByRole("link", { name: "Profile", exact: true })
    .click();
  await page.getByRole("link", { name: "Admin", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Backend", exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
  await page.screenshot({
    path: "test-results/live-admin.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Account menu" }).click();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(
    page.getByRole("heading", { name: "Sign in to Zoop" }),
  ).toBeVisible();
  expect((await page.request.get("/v1/auth/me")).status()).toBe(401);
  await page.getByLabel("Email", { exact: true }).fill("member@example.test");
  await page
    .getByLabel("Password", { exact: true })
    .fill(process.env.ZOOP_E2E_PASSWORD!);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.locator(".today-grid .panel-value").first()).toContainText(
    "89.7",
  );
  expect((await page.request.get("/v1/admin/stats")).status()).toBe(403);
  expect((await page.request.get("/v1/devices/DEMO-A/profile")).status()).toBe(
    404,
  );
  expect(errors).toEqual([]);
});
