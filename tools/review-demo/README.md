# Synthetic App Review data

This fixture creates 56 days of invented sleep, weight, steps and workouts. It
contains no exported user records. Use a separate installation for review.

1. Create a dedicated PostgreSQL database named `zoop_review` and apply the current
   migrations with `zoop migrate` using that installation's configuration.
2. Apply `seed.sql` to that database with `psql -v ON_ERROR_STOP=1 -f seed.sql`.
   It refuses a different database name or any existing devices/accounts. The
   entire seed is transactional; it never replaces existing data.
3. Use `zoop account create` to create a private operator administrator and a
   separate ordinary reviewer. Supply passwords through protected files, never
   command-line arguments or source control.
4. Assign `ZOOP-REVIEW-SYNTHETIC` to the reviewer with `zoop account bind-device`.
5. Verify sign-in, charts, changes and account deletion using the release app.
   The reviewer must be able to delete their account without deleting the operator.

The fixture is for a private reviewer account, not a shared public login. Do not
seed a copy of production, use production credentials, or restore its backups
here. Block band uploads on the reviewer instance so it cannot collect real strap
recordings. Keep the operator credentials out of App Review notes.

If the reviewer deletes the account, recreate the dedicated synthetic instance
and issue fresh credentials. Never reset an installation using a user-supplied
database URL; verify the isolated service, database and storage first.

Dates are generated when the seed runs. Rebuild the disposable reviewer instance
before review so the data is recent. Hardware capture still needs a separate
real-device demonstration; synthetic charts do not prove Bluetooth or HealthKit.

## Review-only availability

This is not a hosted service for customers: no public signup, no published password,
and no advertised demo login. Give Apple only the ordinary reviewer account.
Preserve its credentials rather than applying an expiry timer. Keep the service
available throughout active reviews, including follow-up reviews. It can be stopped
between review windows and brought back before another submission; check the saved
review credentials and current synthetic data every time. Turning off the service
must not erase its database or affect a personal installation.

Apple requires an active, non-expiring demo account and a reachable backend during
review: [review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information),
[review guidelines](https://developer.apple.com/app-store/review/guidelines/).
