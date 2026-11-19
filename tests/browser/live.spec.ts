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
  await expect(page.getByText("Loading your data")).toHaveCount(0);
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.locator(".number").first()).toContainText("64.2");
  for (const name of ["Activity", "Sleep", "Trends", "Goals"]) {
    await page.getByRole("link", { name, exact: true }).click();
    await expect(
      page.getByRole("heading", { name, exact: true }),
    ).toBeVisible();
    await expect(page.getByRole("alert")).toHaveCount(0);
  }
  expect((await page.request.get("/v1/devices/DEMO-B/profile")).status()).toBe(
    404,
  );
  expect(
    (
      await page.request.put("/v1/devices/DEMO-A/profile", { data: {} })
    ).status(),
  ).toBe(403);
  await page.getByRole("button", { name: "Account menu" }).click();
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
  await expect(page.locator(".number").first()).toContainText("89.7");
  expect((await page.request.get("/v1/admin/stats")).status()).toBe(403);
  expect((await page.request.get("/v1/devices/DEMO-A/profile")).status()).toBe(
    404,
  );
  expect(errors).toEqual([]);
});
