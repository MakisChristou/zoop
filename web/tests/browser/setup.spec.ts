import { test, expect } from "@playwright/test";

for (const width of [320, 1440]) {
  test(`first-run setup is compact and does not retain its code at ${width}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 900 });
    let available = true;
    let signedIn = false;
    let payload: Record<string, string> | undefined;
    await page.route("**/v1/**", async (route) => {
      const path = new URL(route.request().url()).pathname;
      if (path === "/v1/setup" && route.request().method() === "GET")
        return route.fulfill({ json: { available } });
      if (path === "/v1/setup") {
        payload = route.request().postDataJSON();
        available = false;
        return route.fulfill({ status: 201, json: { created: true } });
      }
      if (path === "/v1/auth/login") {
        signedIn = true;
        return route.fulfill({ json: {} });
      }
      if (path === "/v1/auth/me")
        return route.fulfill({
          status: signedIn ? 200 : 401,
          json: signedIn
            ? {
                account: { id: 1, email: "owner@example.test", is_admin: true },
                devices: [],
              }
            : {},
        });
      return route.fulfill({ json: {} });
    });
    await page.goto("/");
    await expect(
      page.getByRole("heading", { name: "Set up Zoop" }),
    ).toBeVisible();
    await page.screenshot({
      path: `test-results/setup-${width}.png`,
      fullPage: true,
    });
    await page
      .getByLabel("Setup code", { exact: true })
      .fill("synthetic setup code");
    await page.getByLabel("Email", { exact: true }).fill("owner@example.test");
    await page
      .getByLabel("Password", { exact: true })
      .fill("synthetic owner password");
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.getByRole("button", { name: "Create admin account" }).click();
    expect(payload?.device).toBeNull();
    await expect(
      page.getByRole("heading", { name: "Connect your iPhone" }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Set up Zoop" }),
    ).toHaveCount(0);
    expect(
      await page.evaluate(() => JSON.stringify(localStorage)),
    ).not.toContain("synthetic setup code");
    await page.reload();
    await expect(page.getByLabel("Setup code", { exact: true })).toHaveCount(0);
  });
}

test("setup discovery failure offers retry and does not allow submission", async ({
  page,
}) => {
  let fails = true;
  await page.route("**/v1/auth/me", (r) =>
    r.fulfill({ status: 401, json: {} }),
  );
  await page.route("**/v1/setup", (r) =>
    r.fulfill({
      status: fails ? 503 : 200,
      json: fails ? {} : { available: true },
    }),
  );
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "Sign in", exact: true }),
  ).toBeDisabled();
  await expect(page.getByRole("alert")).toContainText("Couldn’t check");
  fails = false;
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Set up Zoop" }),
  ).toBeVisible();
});

test("reserved bands wait for their first upload instead of fetching missing charts", async ({
  page,
}) => {
  const paths: string[] = [];
  await page.route("**/v1/**", (route) => {
    const path = new URL(route.request().url()).pathname;
    paths.push(path);
    return route.fulfill({
      json: {
        account: { id: 1, email: "owner@example.test", is_admin: true },
        devices: ["RESERVED"],
        pending_devices: ["RESERVED"],
      },
    });
  });
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Connect your iPhone" }),
  ).toBeVisible();
  await expect(
    page.getByText("Your band is linked.", { exact: false }),
  ).toBeVisible();
  expect(paths.some((p) => p.includes("/devices/"))).toBe(false);
  await expect(
    page.getByRole("button", { name: "Check for recordings" }),
  ).toBeVisible();
});
