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

The site is hosted at **https://zoop.health** through GitHub Pages. It is a static
build with no API, database, account credentials or access to personal installations.

After approval to publish, open **Actions → Website checks → Run workflow** on
`main`. Formatting, type checking, content checks and browser tests must pass before
the same run uploads and deploys `site/build`. Ordinary pushes and pull requests
only run checks; they cannot deploy. Deployment permissions belong to the separate
`github-pages` job, never to pull-request builds.

GitHub repository settings use **Pages → GitHub Actions**, with `zoop.health` as
the custom domain. DNS points the apex to GitHub Pages and `www` to
`makischristou.github.io`; GitHub redirects `www` to the canonical apex. GitHub
manages the TLS certificate. Keep domain-verification TXT records in DNS.

The public docs are explicitly allowlisted, search runs locally, and screenshots
use synthetic data. Recheck installation instructions and the rendered pages before
each publication. Any future interactive demo must use an isolated synthetic dataset.
