# Sleep goal

The sleep ring shows main-sleep duration divided by the owner's saved target,
clamped to 0–100%. This is a display preference, not physiological sleep need;
it does not change Recovery or trigger reanalysis.

- `GET /v1/devices/{deviceId}/sleep-goal` returns `minutes` and `configured`.
  An unset target returns 480 minutes and `configured: false`.
- The iPhone saves with `PUT` on the same route: `minutes` (60–1440 in
  15-minute steps), optional `initialize_only`, and `tz` for a new profile.
  Existing body fields and time zone are preserved. Normal account ownership
  and native write authorization apply; browser sessions can read the target.
- On upgrade, iPhone initializes an unset target from its previous local setting.
  This is atomic: an already-saved server target always wins. A local one-way
  scope fingerprint prevents that old setting migrating into another account.
- Main web and iPhone rings read the same endpoint. The public `daily_rings`
  projection includes only `sleep_goal_minutes` alongside the selected readings;
  it never exposes the full profile. Shared previews use that same projection.
- Missing sleep or an unavailable target has no progress arc. Same-account
  refreshes retain confirmed values; failed edits stay open for retry.

Deploy migration 0023 and the API before updating clients. Old profile writes
preserve the new target. No sleep history needs recomputing.
