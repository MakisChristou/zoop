# Contributing

Zoop's iPhone app, API and web dashboard live in this repository. Discuss changes
to behavior or data handling before implementing them. Keep fixes focused and add
regression coverage for data or security changes.

## Find your workspace

| Component | Working directory | Setup and checks |
| --- | --- | --- |
| iPhone | Repository root | [iPhone setup](docs/IPHONE_SETUP.md), [development](docs/DEVELOPMENT.md) |
| API | `server/` | [Server README](server/README.md), [architecture](server/docs/ARCHITECTURE.md) |
| Web | `web/` | [Web README](web/README.md), [development](web/docs/DEVELOPMENT.md) |

GitHub runs all three workflows from `.github/workflows/`. Run the relevant checks
locally and include their results with your change. API changes must preserve
account isolation and the shared meaning of measurements on iPhone and web.

Use synthetic fixtures. Never commit tokens, private configuration, health captures,
local databases or generated test screenshots. Curated documentation screenshots
must use sample data. Report vulnerabilities through [SECURITY.md](SECURITY.md).

Submit changes against `main`. Use a short Conventional Commit message describing
the change. Contributions remain under the existing MIT license; retain third-party
notices. See [repository migration](docs/REPOSITORY.md) for the preserved histories.
