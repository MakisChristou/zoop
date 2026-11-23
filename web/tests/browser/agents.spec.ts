import { test, expect, type Page } from "@playwright/test";
const connection = {
  id: 1,
  name: "My assistant",
  scopes: ["sleep:read"],
  history_days: 30,
  expires_at: "2099-01-01T00:00:00Z",
  revoked_at: null as string | null,
  last_used_at: null,
  client_id: null,
};
async function mock(page: Page, delay = false) {
  let rows: (typeof connection)[] = [];
  let saved: any = null;
  const writes: string[] = [];
  await page.route("**/v1/**", async (route) => {
    const req = route.request(),
      path = new URL(req.url()).pathname;
    if (path === "/v1/auth/me")
      return route.fulfill({
        json: {
          account: { id: 1, email: "owner@example.test", is_admin: true },
          devices: ["TEST"],
        },
      });
    if (path.endsWith("profile/photo")) return route.fulfill({ status: 404 });
    if (path === "/v1/agent-connections") {
      if (req.method() === "GET") {
        if (delay) await new Promise((r) => setTimeout(r, 350));
        return route.fulfill({
          json: {
            connections: rows,
            mcp_url: "https://zoop.example/mcp",
            api_url: "https://zoop.example/v1/agent",
          },
        });
      }
      writes.push(path);
      saved = req.postDataJSON();
      rows = [connection];
      return route.fulfill({
        json: { connection, key: "zoop_ak_" + "a".repeat(64) },
      });
    }
    if (path === "/v1/agent-connections/1") {
      writes.push(path);
      rows = [{ ...connection, revoked_at: new Date().toISOString() }];
      return route.fulfill({ status: 204 });
    }
    if (path === "/v1/agent-authorization") {
      if (req.method() === "GET")
        return route.fulfill({
          json: {
            client_name: "My assistant",
            redirect_uri: "http://127.0.0.1:9000/callback",
            scopes: ["sleep:read"],
          },
        });
      writes.push(path);
      saved = req.postDataJSON();
      return route.fulfill({
        status: 403,
        json: {
          error: {
            message: "Connection expired. Start again from your agent.",
          },
        },
      });
    }
    return route.fulfill({ json: [] });
  });
  return { writes, saved: () => saved };
}
test("explicit permissions, one-time secret, no browser persistence and revocation", async ({
  page,
}) => {
  const state = await mock(page, true);
  await page.goto("/#Agents");
  await expect(page.getByRole("progressbar")).toBeVisible();
  await page.getByRole("button", { name: "Connect your agent" }).click();
  await expect(page.getByLabel("MCP server URL")).toHaveValue(
    "https://zoop.example/mcp",
  );
  await page.getByRole("button", { name: "Close", exact: true }).click();
  await page.getByText("Access keys Advanced", { exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Create access key" }),
  ).toBeDisabled();
  await page.getByLabel("Name", { exact: true }).fill("My assistant");
  await page.getByRole("checkbox", { name: "Sleep Timing and stages" }).check();
  await page.getByRole("button", { name: "Create access key" }).click();
  await expect(page.getByLabel("Access key", { exact: true })).toHaveValue(
    "zoop_ak_" + "a".repeat(64),
  );
  expect(state.saved()).toMatchObject({
    device_id: "TEST",
    scopes: ["sleep:read"],
    history_days: 30,
    expires_in_days: 90,
  });
  expect(
    await page.evaluate(() => [localStorage.length, sessionStorage.length]),
  ).toEqual([0, 0]);
  await page.evaluate(() => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: undefined,
    });
  });
  await page
    .getByRole("button", { name: "Copy access key", exact: true })
    .click();
  await expect(page.getByLabel("Access key", { exact: true })).toHaveAttribute(
    "type",
    "text",
  );
  await expect(
    page.getByText("Copy unavailable. Select the value to copy it."),
  ).toBeVisible();
  await page.getByRole("button", { name: "Done", exact: true }).click();
  await expect(page.getByLabel("Access key", { exact: true })).toHaveCount(0);
  await page.getByLabel("Details for My assistant").click();
  await page.getByRole("button", { name: "Disconnect", exact: true }).click();
  await expect(page.getByText("Last 30 days · Disconnected")).toBeVisible();
  expect(state.writes).toEqual([
    "/v1/agent-connections",
    "/v1/agent-connections/1",
  ]);
});
test("OAuth consent stays explicit, restricted to requested scopes and handles failure", async ({
  page,
}) => {
  const state = await mock(page);
  const query = new URLSearchParams({
    client_id: "test",
    redirect_uri: "http://127.0.0.1:9000/callback",
    response_type: "code",
    code_challenge: "a".repeat(43),
    code_challenge_method: "S256",
    resource: "https://zoop.example/mcp",
    scope: "sleep:read",
    state: "test",
  });
  await page.goto("/#agent-authorize?" + query);
  await expect(
    page.getByRole("heading", { name: "My assistant" }),
  ).toBeVisible();
  await expect(page.getByRole("checkbox")).toHaveCount(1);
  await expect(
    page.getByRole("button", { name: "Allow read access" }),
  ).toBeDisabled();
  await page.getByRole("checkbox").check();
  query.set("state", "new-authorization-request");
  await page.evaluate((hash) => {
    location.hash = hash;
  }, "#agent-authorize?" + query);
  await expect(page.getByRole("checkbox")).not.toBeChecked();
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Allow read access" }).click();
  await expect(page.getByRole("alert")).toHaveText(
    "Connection expired. Start again from your agent.",
  );
  expect(state.saved().consent.scopes).toEqual(["sleep:read"]);
  expect(state.saved().authorization.state).toBe("new-authorization-request");
  await expect(
    page.getByRole("button", { name: "Allow read access" }),
  ).toBeEnabled();
  expect(state.writes).toEqual(["/v1/agent-authorization"]);
});
for (const width of [320, 768, 1440, 2560])
  test(`agent setup fits ${width}px, keyboard controls and reduced motion`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    await mock(page);
    await page.goto("/#Agents");
    await page.getByRole("button", { name: "Connect your agent" }).click();
    await page.getByRole("button", { name: "Close", exact: true }).click();
    await page.getByText("Access keys Advanced", { exact: true }).focus();
    await page.keyboard.press("Enter");
    await page.getByLabel("Name", { exact: true }).fill("Local assistant");
    await page
      .getByRole("checkbox", { name: "Sleep Timing and stages" })
      .focus();
    await page.keyboard.press("Space");
    await expect(
      page.getByRole("checkbox", { name: "Sleep Timing and stages" }),
    ).toBeChecked();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `/tmp/zoop-agents-${width}.png`,
      fullPage: true,
    });
  });
test("connection failure offers retry without showing a false empty state", async ({
  page,
}) => {
  await mock(page);
  await page.route("**/v1/agent-connections", (route) =>
    route.fulfill({
      status: 503,
      json: { error: { message: "Try again shortly." } },
    }),
  );
  await page.goto("/#Agents");
  await expect(page.getByRole("alert")).toContainText("Try again shortly.");
  await expect(page.getByText("No connected apps")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Retry" })).toBeVisible();
});

test("band selection is explicit and enlarged RTL consent stays contained", async ({
  page,
}) => {
  const state = await mock(page);
  await page.route("**/v1/auth/me", (route) =>
    route.fulfill({
      json: {
        account: { id: 1, email: "owner@example.test", is_admin: true },
        devices: ["TEST", "SECOND"],
      },
    }),
  );
  await page.setViewportSize({ width: 768, height: 1200 });
  await page.goto("/#Agents");
  await page.getByRole("button", { name: "Connect your agent" }).click();
  await page.getByRole("button", { name: "Close", exact: true }).click();
  await page.getByText("Access keys Advanced", { exact: true }).click();
  await page.getByLabel("Name", { exact: true }).fill("Local assistant");
  await page
    .getByRole("combobox", { name: "Band", exact: true })
    .selectOption("SECOND");
  await page.getByRole("checkbox", { name: "Sleep Timing and stages" }).check();
  await page.evaluate(() => {
    document.documentElement.dir = "rtl";
    document.documentElement.style.zoom = "2";
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.getByRole("button", { name: "Create access key" }).click();
  await expect(page.getByLabel("Access key", { exact: true })).toBeVisible();
  expect(state.saved().device_id).toBe("SECOND");
});

test("logo picker is keyboard accessible, closes with Escape and restores focus", async ({
  page,
}) => {
  await mock(page);
  await page.goto("/#Settings/agents");
  const trigger = page.getByRole("button", {
    name: "Connect your agent",
    exact: true,
  });
  await trigger.click();
  const dialog = page.getByRole("dialog", { name: "Connect your agent" });
  await expect(dialog).toBeVisible();
  await expect(
    dialog.getByRole("button", { name: "Claude", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await dialog.getByRole("button", { name: "ChatGPT", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(
    dialog.getByRole("button", { name: "ChatGPT", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(
    dialog.getByRole("link", { name: "Open ChatGPT" }),
  ).toHaveAttribute("rel", "noopener noreferrer");
  await expect(dialog.locator(".provider-picker")).not.toContainText("Claude");
  await page.screenshot({ path: "/tmp/zoop-connector-picker.png" });
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
  await expect(trigger).toBeFocused();
  await page.getByRole("link", { name: "Profile", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Profile", exact: true }),
  ).toBeVisible();
});

test("cancel returns to the verified client without granting access", async ({
  page,
}) => {
  const state = await mock(page);
  let cancelled: any;
  await page.route("**/v1/agent-authorization/deny", (route) => {
    cancelled = route.request().postDataJSON();
    return route.fulfill({ json: { redirect_to: "/#Settings/agents" } });
  });
  await page.goto("/#agent-authorize?client_id=test&state=original");
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Settings", exact: true }),
  ).toBeVisible();
  expect(cancelled).toEqual({ client_id: "test", state: "original" });
  expect(state.writes).toEqual([]);
});

test("sign-in preserves the exact authorization request", async ({ page }) => {
  await mock(page);
  let signedIn = false;
  await page.route("**/v1/auth/me", (route) =>
    signedIn
      ? route.fulfill({
          json: {
            account: { id: 1, email: "owner@example.test", is_admin: false },
            devices: ["TEST"],
          },
        })
      : route.fulfill({ status: 401, json: { error: { message: "Sign in" } } }),
  );
  await page.route("**/v1/auth/login", (route) => {
    signedIn = true;
    return route.fulfill({ json: {} });
  });
  const hash =
    "#agent-authorize?client_id=test&state=preserve-this&scope=sleep%3Aread";
  await page.goto("/" + hash);
  await page.getByLabel("Email", { exact: true }).fill("owner@example.test");
  await page
    .getByLabel("Password", { exact: true })
    .fill("synthetic-test-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "My assistant" }),
  ).toBeVisible();
  expect(new URL(page.url()).hash).toBe(hash);
  await expect(page.getByRole("checkbox")).not.toBeChecked();
});

for (const width of [390, 1440])
  test(`connected apps and logo picker render at ${width}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 900 });
    await mock(page);
    await page.route("**/v1/agent-connections", (route) =>
      route.fulfill({
        json: {
          mcp_url: "https://zoop.example/mcp",
          api_url: "https://zoop.example/v1/agent",
          connections: [
            {
              ...connection,
              name: "Claude",
              client_id: "https://claude.ai/oauth/mcp-oauth-client-metadata",
              scopes: ["sleep:read", "recovery:read"],
            },
            {
              ...connection,
              id: 2,
              name: "ChatGPT",
              client_id: "https://chatgpt.com/oauth/client.json",
              scopes: ["activity:read"],
            },
          ],
        },
      }),
    );
    await page.goto("/#Settings/agents");
    await expect(page.getByRole("heading", { name: "Claude" })).toBeVisible();
    await expect(page.locator(".agent-row img")).toHaveCount(2);
    const row = await page.locator(".agent-row").first().boundingBox();
    expect(row!.height).toBeLessThan(150);
    const nav = await page
      .getByRole("navigation", { name: "Settings", exact: true })
      .boundingBox();
    expect(nav!.y).toBeLessThan(row!.y + 30);
    await page.screenshot({
      path: `/tmp/zoop-connected-apps-${width}.png`,
      fullPage: true,
    });
    await page
      .getByRole("button", { name: "Connect your agent", exact: true })
      .click();
    await expect(page.getByLabel("MCP server URL")).toHaveValue(
      "https://zoop.example/mcp",
    );
    const bounds = await page.getByRole("dialog").boundingBox();
    expect(bounds!.x).toBeGreaterThanOrEqual(0);
    expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(width);
    await page.screenshot({ path: `/tmp/zoop-connect-dialog-${width}.png` });
  });
