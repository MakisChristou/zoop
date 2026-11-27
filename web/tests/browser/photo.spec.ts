import { readFileSync } from "node:fs";
import { test, expect, type Page } from "@playwright/test";
async function fixture(page: Page) {
  const module = readFileSync(
    new URL("../../nix/module.nix", import.meta.url),
    "utf8",
  );
  const imagePolicy = module.match(/img-src [^;]+/)![0];
  await page.route("http://127.0.0.1:5173/", async (route) => {
    const response = await route.fetch();
    await route.fulfill({
      response,
      headers: {
        ...response.headers(),
        "content-security-policy": imagePolicy,
      },
    });
  });
  const uploads: Buffer[] = [];
  let saved: Buffer | null = null,
    reject = false;
  await page.route("**/v1/**", async (route) => {
    const r = route.request(),
      path = new URL(r.url()).pathname;
    if (path.endsWith("/profile/photo")) {
      if (r.method() === "PUT") {
        if (reject)
          return route.fulfill({
            status: 503,
            json: {
              error: { message: "Could not save your photo. Try again." },
            },
          });
        expect(r.headers()["content-type"]).toBe("image/jpeg");
        saved = r.postDataBuffer()!;
        uploads.push(saved);
      }
      return saved
        ? route.fulfill({ status: 200, contentType: "image/jpeg", body: saved })
        : route.fulfill({
            status: 404,
            json: { error: { message: "Not found" } },
          });
    }
    const body = path.endsWith("/me")
      ? {
          account: { id: 1, email: "demo@example.test", is_admin: false },
          devices: ["DEMO"],
        }
      : path.endsWith("/profile")
        ? { tz: "UTC" }
        : path.endsWith("/weight-goal")
          ? { goal: null, summary: null }
          : path.endsWith("/insights")
            ? { state: "learning", metrics: [] }
            : [];
    await route.fulfill({ json: body });
  });
  await page.goto("/");
  return {
    uploads,
    fail: (value: boolean) => {
      reject = value;
    },
  };
}
async function open(page: Page) {
  await page.getByRole("button", { name: "Account menu" }).click();
  await page
    .locator(".menu")
    .getByRole("link", { name: "Profile", exact: true })
    .click();
  await page.getByRole("button", { name: "Change photo" }).click();
  await expect(
    page.getByRole("dialog", { name: "Profile photo" }),
  ).toBeVisible();
}
async function choose(page: Page) {
  const data = await page.evaluate(() => {
    const c = document.createElement("canvas");
    c.width = 800;
    c.height = 400;
    const ctx = c.getContext("2d")!;
    ctx.fillStyle = "#ff0000";
    ctx.fillRect(0, 0, 400, 400);
    ctx.fillStyle = "#0000ff";
    ctx.fillRect(400, 0, 400, 400);
    return c.toDataURL("image/png").split(",")[1];
  });
  await page.getByLabel("Choose photo file").setInputFiles({
    name: "example.png",
    mimeType: "image/png",
    buffer: Buffer.from(data, "base64"),
  });
  await expect(page.getByLabel("Zoom")).toBeVisible();
}
test("crop, keyboard positioning, save and reload share a small JPEG", async ({
  page,
}) => {
  const f = await fixture(page);
  await open(page);
  await choose(page);
  expect(f.uploads).toHaveLength(0);
  await page.getByLabel("Zoom").fill("2");
  await page.getByLabel("Photo crop", { exact: true }).focus();
  for (let i = 0; i < 20; i++) await page.keyboard.press("ArrowRight");
  await page.screenshot({ path: "/tmp/zoop-photo-desktop.png" });
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("dialog")).not.toBeVisible();
  expect(f.uploads).toHaveLength(1);
  expect(f.uploads[0].length).toBeLessThanOrEqual(262144);
  const output = await page.evaluate(async (data) => {
    const image = await createImageBitmap(
      await (await fetch("data:image/jpeg;base64," + data)).blob(),
    );
    const c = document.createElement("canvas");
    c.width = c.height = 512;
    const ctx = c.getContext("2d")!;
    ctx.drawImage(image, 0, 0);
    return {
      w: image.width,
      h: image.height,
      pixel: Array.from(ctx.getImageData(256, 256, 1, 1).data),
    };
  }, f.uploads[0].toString("base64"));
  expect(output.w).toBe(512);
  expect(output.h).toBe(512);
  expect(output.pixel[2]).toBeGreaterThan(240);
  expect(output.pixel[0]).toBeLessThan(15);
  await expect(
    page.getByRole("button", { name: "Account menu" }).locator("img"),
  ).toBeVisible();
  const avatar = page
    .getByRole("button", { name: "Account menu" })
    .locator("img");
  await expect
    .poll(() => avatar.evaluate((img: HTMLImageElement) => img.naturalWidth))
    .toBe(512);
  const firstURL = await avatar.getAttribute("src");
  await open(page);
  await choose(page);
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("dialog")).not.toBeVisible();
  await expect.poll(() => avatar.getAttribute("src")).not.toBe(firstURL);
  await expect
    .poll(() => avatar.evaluate((img: HTMLImageElement) => img.naturalWidth))
    .toBe(512);
  await page.reload();
  await expect(
    page.getByRole("button", { name: "Account menu" }).locator("img"),
  ).toBeVisible();
  await expect
    .poll(() => avatar.evaluate((img: HTMLImageElement) => img.naturalWidth))
    .toBe(512);
});
test("cancel does not upload and failed upload retains crop for retry", async ({
  page,
}) => {
  const f = await fixture(page);
  await open(page);
  await choose(page);
  await page.keyboard.press("Escape");
  expect(f.uploads).toHaveLength(0);
  await expect(
    page.getByRole("button", { name: "Account menu" }),
  ).toBeFocused();
  await open(page);
  await choose(page);
  f.fail(true);
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("Try again");
  await expect(page.getByLabel("Zoom")).toBeVisible();
  f.fail(false);
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("dialog")).not.toBeVisible();
});
test("invalid photo is rejected without upload", async ({ page }) => {
  const f = await fixture(page);
  await open(page);
  await page.getByLabel("Choose photo file").setInputFiles({
    name: "invalid.png",
    mimeType: "image/png",
    buffer: Buffer.from("not an image"),
  });
  await expect(page.getByRole("alert")).toContainText("Could not open");
  expect(f.uploads).toHaveLength(0);
});
test("compact crop works on touch widths and returns focus", async ({
  page,
}) => {
  await page.setViewportSize({ width: 320, height: 740 });
  await fixture(page);
  await open(page);
  await choose(page);
  const crop = page.getByLabel("Photo crop", { exact: true }),
    box = (await crop.boundingBox())!;
  const before = await crop.evaluate((c: HTMLCanvasElement) => c.toDataURL());
  await page.mouse.move(box.x + 128, box.y + 128);
  await page.mouse.down();
  await page.mouse.move(box.x + 80, box.y + 128, { steps: 5 });
  await page.mouse.up();
  expect(await crop.evaluate((c: HTMLCanvasElement) => c.toDataURL())).not.toBe(
    before,
  );
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeInViewport();
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual(320);
  await page.screenshot({ path: "/tmp/zoop-photo-mobile.png" });
  await page.getByRole("button", { name: "Close", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Account menu" }),
  ).toBeFocused();
});

for (const width of [768, 1440, 2560])
  test(`photo dialog remains compact at ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    await fixture(page);
    await open(page);
    await choose(page);
    const box = (await page.getByRole("dialog").boundingBox())!;
    expect(box.width).toBeLessThanOrEqual(380);
    await expect(
      page.getByRole("button", { name: "Save", exact: true }),
    ).toBeInViewport();
  });
test("photo editor supports enlarged text and RTL without overflow", async ({
  page,
}) => {
  await page.setViewportSize({ width: 640, height: 900 });
  await page.emulateMedia({ reducedMotion: "reduce" });
  await fixture(page);
  await open(page);
  await choose(page);
  await page.evaluate(() => {
    document.documentElement.dir = "rtl";
    document.documentElement.style.zoom = "2";
  });
  await expect(
    page.getByRole("button", { name: "Save", exact: true }),
  ).toBeVisible();
  const overflow = await page
    .getByRole("dialog")
    .evaluate((el) => el.scrollWidth > el.clientWidth);
  expect(overflow).toBe(false);
});
