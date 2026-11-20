# Zoop website

The public homepage and documentation for `zoop.health`, built with Docusaurus,
React and Markdown. The private health dashboard lives separately in `../web/`.

## Preview

Use Node 24 and npm:

```sh
npm ci
npm run build
npm run serve
```

Open **http://localhost:3000**. For live editing, use `npm start` instead. Local
search needs a production build to generate its index.

## Edit

- Homepage: `src/pages/index.tsx`.
- Colours, typography and layout: `src/css/custom.css`.
- Guides: the six explicitly included files in `../docs/`.
- Navigation: `sidebars.ts` and `docusaurus.config.ts`.
- Product images: `static/img/`, captured from the actual web dashboard with
  synthetic browser-test fixtures at desktop and mobile widths.

The build never copies the full docs directory. The public page allowlist is checked
against generated HTML and the local search index. Keep release reports and
engineering notes out of it. Geist’s license is included in `static/Geist-OFL.txt`.

## Check

```sh
npm run format:check
npm run typecheck
npm run build
npm run check:content
npx playwright install chromium
npm test
```

Browser tests cover the preview selector, documentation links, local search,
mobile navigation, keyboard focus, responsive layouts and accessibility in both
themes. Screenshots are written to ignored `test-results/`.

`tinypool`, `serialize-javascript` and SockJS’s `uuid` have patched dependency
overrides for upstream security advisories. Reassess them when upgrading Docusaurus;
the production build and browser tests must pass before removing them.

## Publishing

This is a review preview, with search-engine indexing disabled. CI builds and
tests it but does not deploy. `build/` is a static artifact suitable for static
hosting; it needs no API, database, account credentials or production access.

Before launch, get approval for hosting and `zoop.health` DNS, finish the repository
publication review, recheck installation instructions against the released version,
and remove `noIndex`. A demo, if added, must use an isolated synthetic dataset.
