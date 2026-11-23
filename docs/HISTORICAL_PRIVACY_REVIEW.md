# Historical privacy review

Reviewed 23 November 2026 against an anonymous public mirror, with main at
`d8c1b4a9bf0581d242ec5d6d4a45fa23be2594e3`. This is a scoped audit record, not a
guarantee that published history is anonymous.

## Decision

The owner explicitly accepted the disclosed historical sensor data and local
build metadata on 23 November and instructed that existing history be kept.
Health screenshots were already approved for publication. No history rewrite,
repository visibility change, deployment or release was performed for this review.

## Findings

- **Own sensor captures:** six unique packets, 488 bytes total, duplicated in old
  Swift and Rust decoder tests. They expose capture timestamps, a brief biometric
  snapshot, movement/step data and raw device fields. These are not a longitudinal
  export. Current fixtures are synthetic; the originals remain in history. No
  credential or readable strap serial was identified, but opaque fields are not
  certified anonymous.
- **Generated build files:** 2,362 historical blobs under
  `Packages/SnoopProtocol/.build/` include local account/source paths and SDK/build
  metadata. Four `build.db` versions contain Xcode build tables, not health tables.
  They were removed from tracking in `c225ac6`.
- **Screenshots:** all 27 raster image blobs were inspected, including icons and
  current/older screenshots. Historical screenshots contain approved health readings
  and a profile avatar. No GPS metadata was found.
- **Earlier third-party fixtures:** the removed `wearable5_golden.json` contains
  15 synthetic examples and three records labelled real. Its frame bytes match
  [the public upstream corpus](https://github.com/LeonardSEO/wearable5.0/blob/main/fixtures/golden.json),
  whose [license is MIT](https://github.com/LeonardSEO/wearable5.0/blob/main/LICENSE).
  This verifies provenance, not original participant consent. The corpus was
  removed in `2e2baea`; it must not be described as wholly synthetic or owner data.

## Checks and limits

- Inventoried 287 reachable commits and 5,129 unique file blobs, including public
  branch and pull-request refs. Scanned Git history, commit metadata and about
  66 MB of printable strings from generated files. No credentials or signing keys
  were confirmed. The normal history scan retains the exact, documented synthetic
  token exception. Fifteen additional binary-string scanner hits were reviewed:
  fourteen Swift compiler symbols and one Apple SDK header index, not credentials.
- Inspected public GitHub release, artifact, issue/comment and wiki surfaces:
  no releases or retained artifacts; eight pull requests, two Dependabot comments,
  no ordinary issues, review comments or attached files; wiki disabled.
- Inventoried 480 workflow runs and reviewed all 35 historical workflow-definition
  versions. None referenced a personal host, a self-hosted runner or explicit
  repository secrets. Sampled logs from the earliest iOS run, the first security
  audit and the passing release-check run; **not every historical log was scanned**.
- Unreachable objects, other clones/caches, private App Store review attachments
  and ignored local research are outside this review. No personal database was
  queried and no credential was tested against a live service.

Retaining history accepts the exposures above; deleting files in a later commit
does not remove their earlier versions. New captures or screenshots require their
own review. Never reintroduce real recordings as routine test fixtures.
