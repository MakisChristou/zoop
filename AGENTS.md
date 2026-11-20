# Zoop web

React/TypeScript companion to Zoop API. Develop and test separately from
production. Never activate a NixOS deployment without explicit approval.

- For every UI change, read and apply [Zoop interface](.agents/skills/zoop-interface/SKILL.md).
  Its layout, loading, chart accessibility and concise-copy checks are required.
- Preserve the approved Marc Lou health-page direction: Geist, black/charcoal,
  compact regular headings, purple sleep, blue activity, neutral weight. No welcome
  essays, duplicate facts or invented scores. Use measurements and clear hierarchy.
- Browser sessions may start, edit and end their own goals through the same revisioned API as iPhone. All other health writes remain iPhone-only. Enforce ownership and same-origin protection on the server.
- The API owns authorization and metric calculations. Never ship bearer credentials,
  implement client-only security, or silently replace unavailable data with zeros.
- Admin is operational visibility, not permission to inspect other users' records.
- Use same-origin HttpOnly cookies; never store credentials in localStorage.
- Test cross-user denial in the backend and browser behavior on desktop and mobile.
  Include partial/empty/error data, calendar boundaries and missing observations.
- Run `npm test`, `npm run build`, `npm run test:e2e` and `nix build` before shipping.
- No personal data, credentials or generated test screenshots in source control.
- Conventional commits, without AI attribution or session links.

## Metric parity

- **iPhone and web must display the same backend-owned metrics.** Use the same metric definition, source field, day/timezone and goal scope. Clients may format values, convert display units and render goal progress; they must not independently derive health metrics or substitute a different raw/filtered value. Missing data stays missing. Refresh timing may differ, but equal backend snapshots must produce equal readings.
- Displayed steps use backend walking/running-filtered counts (`steps_walking` in daily summaries, `walking` in hourly steps), never the raw strap counter. Cover source selection with regression tests when changing metric presentation.
