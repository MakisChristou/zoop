import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve("build");
async function files(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  return (
    await Promise.all(
      entries.map((e) =>
        e.isDirectory()
          ? files(path.join(dir, e.name))
          : [path.join(dir, e.name)],
      ),
    )
  ).flat();
}
const built = await files(root);
const publicPages = [
  "index.html",
  "404.html",
  "search/index.html",
  "docs/get-started/index.html",
  "docs/iphone/index.html",
  "docs/self-hosting/index.html",
  "docs/help/index.html",
  "docs/measurements/index.html",
  "docs/data-privacy/index.html",
].sort();
assert.deepEqual(
  built
    .filter((f) => f.endsWith(".html"))
    .map((f) => path.relative(root, f))
    .sort(),
  publicPages,
  "Only reviewed public routes may be generated",
);
for (const name of publicPages) {
  const html = await readFile(path.join(root, name), "utf8");
  if (name === "index.html" || name.startsWith("docs/")) {
    assert.doesNotMatch(
      html,
      /<meta[^>]+name="robots"[^>]+content="[^"]*noindex/,
      `${name} must be indexable`,
    );
    assert.match(
      html,
      /rel="canonical" href="https:\/\/zoop\.health\//,
      `${name} must use the public domain`,
    );
  }
  assert.doesNotMatch(
    html,
    /atlantikou|shallot|RELEASE_READINESS|APP_STORE\.md/i,
    "Published pages must not contain personal deployment details or internal guides",
  );
}
const indexes = built.filter((f) => /search-index.*\.json$/.test(f));
assert.ok(indexes.length, "Local search must have a built index");
for (const file of indexes) {
  const index = await readFile(file, "utf8");
  assert.match(index, /backup|back up/i);
  assert.doesNotMatch(
    index,
    /RELEASE_READINESS|APP_STORE|REPOSITORY\.md|atlantikou|shallot/i,
    "Search must not publish internal guides or personal deployment details",
  );
}
console.log(
  `Checked ${publicPages.length} public routes and ${indexes.length} search index.`,
);
