# HSI test fixtures

These payloads are vendored verbatim from the canonical HSI repository
(https://github.com/synheart-ai/hsi) and serve as the regression net for
`HSIPayload.fromJson` in `lib/src/models/hsi_export.dart`. The
companion test `test/hsi_parser_compat_test.dart` iterates every file
under this directory and asserts the parser accepts it without
throwing.

## Layout

| Path | Source | Purpose |
|---|---|---|
| `v1_0/minimal.json` | `hsi/test-vectors/v1.0/` | Smallest-valid 1.0 payload. |
| `v1_1/minimal.json` | `hsi/test-vectors/v1.1/` | Smallest-valid 1.1 payload. |
| `v1_2/*.json` | `hsi/examples/valid/` | Full 1.2 examples covering every axis-domain combination + edge cases (null score, runtime snapshot, behavior-only, etc.). |
| `cross_version/*.json` | `hsi/test-vectors/` | Schema-version-agnostic edge cases (degraded sources, low confidence, partial axes). |

## Updating

When a new HSI version ships:

1. Pull the latest from `https://github.com/synheart-ai/hsi`.
2. Copy new test vectors / examples into the matching `vN_M/`
   subdirectory here.
3. Add the version string to `kKnownHsiVersions` in
   `lib/src/models/hsi_export.dart`.
4. Run `flutter test test/hsi_parser_compat_test.dart` — it should
   stay green (or fail loudly with the exact field that drifted, which
   tells you what to update in the parser).

## Why vendor instead of git-submodule

A submodule would always test against `main`, which is fine for active
development but brittle for release branches that need a pinned
contract. Vendoring lets each tag of `synheart-core-flutter` declare
exactly which HSI fixture set it's known-good against, and a CI step
can periodically diff vendored copies against upstream to surface
drift as a PR.
