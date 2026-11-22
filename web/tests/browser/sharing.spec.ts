import { test, expect, type Page } from "@playwright/test";
const token = "a".repeat(64);
const config = {
  title: "Training journal",
  display_name: "",
  show_photo: false,
  range: "last30",
  from: null,
  to: null,
  widgets: ["sleep", "steps", "weight", "recovery"],
};
function dashboard(year = 2026, keys = config.widgets) {
  return {
    title: config.title,
    display_name: "",
    photo: null,
    timezone: "UTC",
    from: `${year}-10-22`,
    to: `${year}-11-20`,
    paged: true,
    first_year: 2020,
    last_year: 2026,
    widgets: keys.map((key) => ({
      key,
      points: Array.from({ length: 30 }, (_, i) => ({
        day: new Date(Date.UTC(year, 9, 22 + i)).toISOString().slice(0, 10),
        value:
          key === "sleep"
            ? 25200 + (i % 5) * 600
            : key === "steps"
              ? 8000 + (i % 7) * 700
              : key === "weight"
                ? 70 - i * 0.03
                : 65 + (i % 5),
      })),
    })),
  };
}
async function visitor(page: Page, locked = false) {
  const paths: string[] = [];
  await page.route("**/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    paths.push(path);
    expect(path).toBe("/v1/public/dashboard");
    expect(route.request().headers()["cookie"]).toBeUndefined();
    const body = route.request().postDataJSON();
    if (locked && body.password !== "open sesame")
      return route.fulfill({ status: 401, json: {} });
    await route.fulfill({ json: dashboard(body.year ?? 2026) });
  });
  return paths;
}
test("public visitor only requests scoped projection; password and year browsing work", async ({
  page,
}) => {
  await page.context().addCookies([
    {
      name: "zoop_session",
      value: "private-test-cookie",
      url: "http://127.0.0.1:5173",
    },
  ]);
  const paths = await visitor(page, true);
  await page.goto("/#share/" + token);
  await expect(page.getByLabel("Password", { exact: true })).toBeVisible();
  await page.getByLabel("Password", { exact: true }).fill("open sesame");
  await page.getByRole("button", { name: "Open dashboard" }).click();
  await expect(
    page.getByRole("heading", { name: "Training journal" }),
  ).toBeVisible();
  await page.getByLabel("Dashboard year").selectOption("2020");
  await expect(page.locator(".chart-frame").first()).toBeVisible();
  expect(paths.every((p) => p === "/v1/public/dashboard")).toBe(true);
  await expect(page.getByRole("button", { name: "Account menu" })).toHaveCount(
    0,
  );
  expect(await page.evaluate(() => localStorage.length)).toBe(0);
});
test("invalid and revoked links do not fall through to account login", async ({
  page,
}) => {
  await page.route("**/v1/**", (r) => r.fulfill({ status: 404, json: {} }));
  await page.goto("/#share/" + token);
  await expect(page.getByRole("alert")).toHaveText(
    "This link is no longer available.",
  );
  await expect(
    page.getByRole("button", { name: "Sign in", exact: true }),
  ).toHaveCount(0);
});
test("editor previews selected scope before creating and supports removal", async ({
  page,
}) => {
  let saved: any = null;
  const writes: string[] = [];
  await page.route("**/v1/**", async (route) => {
    const r = route.request(),
      p = new URL(r.url()).pathname;
    let body: unknown = [];
    if (p === "/v1/auth/me")
      body = {
        account: { id: 1, email: "demo@example.test", is_admin: false },
        devices: ["DEMO"],
      };
    else if (p.endsWith("/profile/photo"))
      return route.fulfill({ status: 404, json: {} });
    else if (p === "/v1/shares/preview") {
      writes.push("preview");
      const b = r.postDataJSON();
      body = dashboard(b.year ?? 2026, b.config.widgets);
    } else if (p === "/v1/shares" && r.method() === "POST") {
      writes.push("create");
      saved = {
        ...r.postDataJSON(),
        id: 1,
        token,
        revision: 1,
        password_protected: false,
      };
      body = saved;
    } else if (p === "/v1/shares/1" && r.method() === "DELETE") {
      writes.push("delete");
      saved = null;
      return route.fulfill({ status: 204 });
    } else if (p === "/v1/shares") body = saved ? [saved] : [];
    await route.fulfill({ json: body });
  });
  await page.goto("/#Shares");
  await page.getByRole("button", { name: "New dashboard" }).click();
  await page
    .getByRole("button", { name: "Sharing settings", exact: true })
    .first()
    .click();
  await expect(page.getByLabel("History", { exact: true })).toHaveValue(
    "last30",
  );
  await page.getByLabel("Title", { exact: true }).fill("Training journal");
  await page.getByLabel("History", { exact: true }).selectOption("all");
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeEnabled();
  expect(writes.every((p) => p === "preview")).toBe(true);
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Training journal" }),
  ).toBeVisible();
  expect(saved.config.range).toBe("all");
  expect(saved.config.widgets).toContain("weight");
  await page.getByRole("button", { name: "Edit", exact: true }).click();
  await page
    .getByRole("button", { name: "Sharing settings", exact: true })
    .first()
    .click();
  await page.getByRole("button", { name: "Delete link" }).click();
  await page.getByRole("button", { name: "Delete", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Share the metrics you choose." }),
  ).toBeVisible();
});
for (const width of [320, 768, 1440, 2560])
  test(`shared charts align at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    await visitor(page);
    await page.goto("/#share/" + token);
    await expect(page.locator(".shared-widget")).toHaveCount(4);
    await expect(page.locator(".recharts-surface").first()).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const cards = await page.locator(".shared-widget").evaluateAll((nodes) =>
      nodes.map((n) => ({
        x: n.getBoundingClientRect().x,
        y: n.getBoundingClientRect().y,
        width: n.getBoundingClientRect().width,
        height: n.getBoundingClientRect().height,
      })),
    );
    if (width >= 768) {
      expect(cards[0].y).toBe(cards[1].y);
      expect(cards[0].height).toBe(cards[1].height);
    }
    if (width >= 1440) expect(cards[0].width).toBeLessThan(560);
    await page.locator(".chart-frame").first().focus();
    await page.keyboard.press("ArrowRight");
    await page.screenshot({
      path: `/tmp/zoop-shared-${width}.png`,
      fullPage: true,
    });
  });
test("empty, slow and failed projections have clear states", async ({
  page,
}) => {
  let fail = false;
  await page.route("**/v1/**", async (r) => {
    await new Promise((resolve) => setTimeout(resolve, 200));
    await r.fulfill(
      fail
        ? { status: 503, json: {} }
        : { json: { ...dashboard(), widgets: [{ key: "steps", points: [] }] } },
    );
  });
  await page.goto("/#share/" + token);
  await expect(page.getByRole("progressbar")).toBeVisible();
  await expect(page.getByText("No readings for this period")).toBeVisible();
  fail = true;
  await page.getByLabel("Dashboard year").selectOption("2020");
  await expect(page.getByRole("alert")).toContainText("Could not load");
  await expect(page.getByRole("button", { name: "Try again" })).toBeVisible();
});

for (const width of [320, 1440])
  test(`editor is compact and keyboard usable at ${width}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.route("**/v1/**", async (r) => {
      const p = new URL(r.request().url()).pathname;
      await r.fulfill(
        p.endsWith("/photo")
          ? { status: 404, json: {} }
          : {
              json: p.endsWith("/me")
                ? {
                    account: {
                      id: 1,
                      email: "demo@example.test",
                      is_admin: false,
                    },
                    devices: ["DEMO"],
                  }
                : p.endsWith("/preview")
                  ? dashboard()
                  : [],
            },
      );
    });
    await page.goto("/#Shares");
    await page.getByRole("button", { name: "New dashboard" }).click();
    await page
      .getByRole("button", { name: "Sharing settings", exact: true })
      .first()
      .click();
    await page.getByLabel("Title", { exact: true }).fill("Training journal");
    await page
      .getByRole("button", { name: "Sharing settings", exact: true })
      .first()
      .click();
    await page.getByRole("button", { name: "Move Sleep", exact: true }).focus();
    await page.keyboard.press("ArrowDown");
    await expect(
      page.getByRole("button", { name: "Save", exact: true }),
    ).toBeEnabled();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `/tmp/zoop-share-editor-${width}.png`,
      fullPage: true,
    });
    await page.evaluate(() => {
      document.documentElement.dir = "rtl";
      document.documentElement.style.fontSize = "200%";
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  });
