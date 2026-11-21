# Public website and docs

This workspace builds the public Zoop homepage and selected guides with Docusaurus.
It is independent of the signed-in dashboard in `web/` and every personal installation.

- Keep the app’s Geist typography, neutral surfaces and chart colours. Use the
  product itself to explain Zoop; avoid slogans, ornamental badges and repeated copy.
- Write for someone installing Zoop for the first time. State prerequisites and
  real limitations. Do not claim App Store availability, published containers,
  supported hardware or medical validation before they exist.
- Root `docs/` is the source of truth. `docusaurus.config.ts` explicitly allows the
  public guides; never replace that list with a wildcard. Internal release audits,
  local instructions and private artifacts must not enter the site or search index.
- Screenshots use synthetic fixtures only. Do not connect this site to a personal
  API, database, authenticated browser session or public share link.
- Bundle fonts and use local search. Do not add analytics or external services
  without a product decision.
- The approved public site is indexable at `zoop.health`. Publishing uses the manual
  GitHub Pages workflow on `main`; normal pushes and pull requests only run checks.
  Each production deployment or DNS change still needs explicit approval. Never
  give pull-request builds deployment permissions.
- Run formatting, type checking, content checks, the production build and browser
  tests. Inspect real desktop/mobile screenshots. Check keyboard navigation,
  contrast, reduced motion, narrow viewports and both themes.
