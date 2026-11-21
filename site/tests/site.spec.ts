import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("responsive homepage and product previews", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  for (const width of [320, 390, 768, 1440, 2560]) {
    await page.setViewportSize({ width, height: width < 600 ? 844 : 1000 });
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toContainText(
      "Your WHOOP.",
    );
    await page.evaluate(() => document.fonts.ready);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const image = page.locator("#product-image img");
    await expect(image).toBeVisible();
    expect(
      await image.evaluate(
        (img: HTMLImageElement) => img.complete && img.naturalWidth > 0,
      ),
    ).toBe(true);
    await page.getByRole("button", { name: "Activity", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "Activity", exact: true }),
    ).toHaveAttribute("aria-pressed", "true");
    await expect(image).toHaveAttribute("alt", /Activity dashboard/);
    await page.getByRole("button", { name: "Goals", exact: true }).focus();
    await page.keyboard.press("Enter");
    await expect(image).toHaveAttribute("alt", /Goals dashboard/);
    await page.getByRole("button", { name: "Today", exact: true }).click();
    if (width === 390 || width === 1440) {
      await page.evaluate(() => scrollTo(0, 0));
      await page.screenshot({ path: `test-results/home-top-${width}.png` });
      await page.screenshot({
        path: `test-results/home-${width}.png`,
        fullPage: true,
      });
    }
  }
  expect(errors).toEqual([]);
});

test("guides, anchors and responsive reading", async ({ page }) => {
  const paths = [
    "get-started",
    "iphone",
    "self-hosting",
    "help",
    "measurements",
    "data-privacy",
  ];
  for (const slug of paths) {
    await page.goto(`/docs/${slug}/`);
    await expect(page.locator("article h1")).toHaveCount(1);
    for (const width of [320, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      ).toBe(true);
    }
    const anchors = await page
      .locator('article a[href*="#"]')
      .evaluateAll((links) => links.map((a) => (a as HTMLAnchorElement).href));
    for (const href of anchors) {
      if (!href.startsWith("http://127.0.0.1:3000/")) continue;
      await page.goto(href);
      const hash = new URL(href).hash;
      await expect(
        page.locator(`[id="${decodeURIComponent(hash.slice(1))}"]`),
      ).toHaveCount(1);
    }
  }
  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    await page.goto("/docs/get-started/");
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: `test-results/docs-top-${width}.png` });
    await page.screenshot({
      path: `test-results/docs-${width}.png`,
      fullPage: true,
    });
  }
});

test("local search reaches the backup guide", async ({ page }) => {
  await page.goto("/docs/get-started/");
  // The server-rendered input is visible before React installs search handlers.
  await expect(page.locator("html")).toHaveAttribute(
    "data-has-hydrated",
    "true",
  );
  const search = page.getByLabel("Search", { exact: true });
  await search.fill("backup");
  await expect(page.getByRole("option").first()).toBeVisible();
  await search.press("ArrowDown");
  await search.press("ArrowUp");
  await search.press("Enter");
  await expect(page).toHaveURL(/\/docs\/self-hosting/);
  await expect(page.locator("#back-up-and-restore")).toBeVisible();
});

test("mobile menu and keyboard entry", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.keyboard.press("Tab");
  await expect(
    page.getByRole("link", { name: "Skip to main content" }),
  ).toBeFocused();
  await page.keyboard.press("Enter");
  await page.getByRole("button", { name: "Toggle navigation bar" }).click();
  await page
    .locator(".navbar-sidebar")
    .getByRole("link", { name: "Docs", exact: true })
    .click();
  await expect(page.locator("article h1")).toHaveText("Get started");
  await expect(page.locator(".navbar-sidebar")).not.toBeInViewport();
});

test("mobile search, text enlargement and self-contained assets", async ({
  page,
}) => {
  const external: string[] = [];
  page.on("request", (request) => {
    const url = request.url();
    if (url.startsWith("http") && !url.startsWith("http://127.0.0.1:3000/"))
      external.push(url);
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/docs/get-started/");
  await expect(page.locator("html")).toHaveAttribute(
    "data-has-hydrated",
    "true",
  );
  const search = page.getByLabel("Search", { exact: true });
  await search.fill("backup");
  await expect(page.getByRole("option").first()).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.keyboard.press("Escape");
  await page.setViewportSize({ width: 720, height: 1000 });
  for (const route of ["/", "/docs/get-started/"]) {
    await page.goto(route);
    await page.evaluate(
      () => (document.documentElement.style.fontSize = "200%"),
    );
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  }
  expect(external).toEqual([]);
});

test("accessible in dark and light themes", async ({ page }) => {
  // Exercise the text shortcut hint even when these tests run on a Mac.
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "platform", { get: () => "Linux x86_64" });
  });
  for (const theme of ["dark", "light"]) {
    await page.addInitScript(
      (value) => localStorage.setItem("theme", value),
      theme,
    );
    for (const route of [
      "/",
      "/docs/get-started/",
      "/docs/self-hosting/",
      "/docs/iphone/",
      "/docs/help/",
      "/docs/measurements/",
      "/docs/data-privacy/",
    ]) {
      await page.goto(route);
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme);
      await page.evaluate(() => document.fonts.ready);
      const audit = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
        .analyze();
      expect(audit.violations).toEqual([]);
    }
  }
});
