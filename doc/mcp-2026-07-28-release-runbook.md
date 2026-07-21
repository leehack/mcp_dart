# MCP 2026-07-28 Day-0 Release Runbook

Use this checklist after the official MCP `2026-07-28` specification is tagged.
Do not publish the stable Dart packages from a moving draft commit.

## Branch policy

- [PR #306](https://github.com/leehack/mcp_dart/pull/306) merged the MCP
  2026-07-28 implementation line into `main`. Prepare prereleases and the
  eventual stable release on focused branches cut from the latest `main`.
- Keep `dev/2026-07-28-rc` as a read-only archive. Published
  `mcp_dart 2.3.0-dev.0`, `2.3.0-dev.1`, and matching CLI prereleases contain
  documentation URLs for that branch; deleting it would break their metadata.
- The normal `Run MCP 2026-07-28 Interop` schedule now runs from `main`; the
  temporary default-branch monitor and `dev/2026-07-28` branch are retired.
- Before release day, confirm the `RELEASE_PAT` repository secret is valid and
  can push tags. The release workflow uses it so tag pushes start the separate
  pub.dev publish and CLI-binary workflows; a tag pushed with the default
  `GITHUB_TOKEN` would not start those workflows.
- Every pub.dev publication requires the exact release commit to carry the
  `mcp_dart/release/<package>` success status. Only `Create Release` writes
  that status, after metadata and publish dry-run checks; stable releases also
  require latest-`main`, exact-SHA CI, and final-spec gates. New tags remain
  `pending` until their PAT-backed push succeeds, and a failed push records
  `failure`. A manually pushed stable or prerelease tag therefore cannot
  bypass the release workflow.

## Completed prerelease rehearsal

The coordinated `dev.2` rehearsal completed on 2026-07-15. SDK tag
[`v2.3.0-dev.2`](https://github.com/leehack/mcp_dart/releases/tag/v2.3.0-dev.2)
and CLI tag
[`mcp_dart_cli-v0.2.0-dev.2`](https://github.com/leehack/mcp_dart/releases/tag/mcp_dart_cli-v0.2.0-dev.2)
both resolve to validated commit
`c961c33a8151d32ae605d239124c19657797b0a0`. Both packages were published to
pub.dev with 160/160 scores, and the CLI release contains Linux x64, macOS x64,
macOS arm64, and Windows x64 binaries. Package metadata and README links use
the immutable prerelease tags so they remain valid after source branches are
removed.

Do not dispatch either `dev.2` release again from a newer commit. The release
workflow intentionally rejects an existing tag that does not identify the
selected source commit.

The prerelease is a public workflow rehearsal and interoperability preview. It
does not replace the final-spec delta review or authorize a stable release.

## 1. Freeze the official inputs

1. Record the final core specification tag and commit SHA.
2. Diff that SHA against `tool/testing/mcp_2026_07_28_spec_ref.txt`.
3. Record the independently released Tasks extension tag and commit SHA, then
   diff it against `tool/testing/mcp_2026_07_28_tasks_spec_ref.txt`. Review
   `specification/draft/tasks.md`, `seps/2663-tasks-extension.md`, and
   `schema/draft/schema.json`; the extension is not versioned by the core
   specification repository. Audit the actual pinned checkout contents and
   their wire contracts; a successful fetch or matching commit ID alone is not
   evidence that the extension is implemented.
4. Review every schema, example, conformance, and normative prose change in
   both ranges; do not rely only on generated schema diffs.
   Explicitly reconcile the Tasks failed-state `error` contract: current
   normative prose describes the JSON-RPC error shape, the current schema
   accepts a generic JSON object, and the SDK currently exposes
   `JsonRpcErrorData`. Do not acknowledge the stable gate until the final text,
   schema, SDK type, and wire tests agree.
5. Reconcile the Tasks timing-field contract. Current prose defines `ttlMs`
   and `pollIntervalMs` as integer milliseconds, while the generated schema
   accepts any JSON number. The SDK accepts mathematically integral values and
   stores them as `int`. Do not set
   `tasksExtension.timingFieldIntegerSemanticsReviewed` until the final prose,
   schema, SDK representation, and negative fractional-value tests agree.
6. Resolve the current cross-repository error-code conflict before publishing:
   the core MCP 2026-07-28 specification requires
   `MissingRequiredClientCapability`
   (`-32021`) for missing per-request capabilities, while the Tasks extension
   draft still names `-32003`. The SDK follows the core error registry; stop
   the release if the final texts do not establish one interoperable value.
7. Reconcile server-initiated subscription termination across the final Core
   cancellation, subscriptions, transport, and schema texts. The current
   draft requires `notifications/cancelled` in the cancellation page, describes
   a terminal empty response followed by close in the subscriptions page, and
   describes server cancellation specifically for stdio in the schema. The
   SDK currently sends cancellation before the terminal completion or error
   response on stdio and the terminal response only on Streamable HTTP. Update
   behavior and tests if
   the final contract differs, then set
   `subscriptionTermination.finalTextsAgree`.
8. Update both `tool/testing/mcp_2026_07_28_spec_ref.txt` and
   `tool/testing/mcp_2026_07_28_tasks_spec_ref.txt` to the reviewed final SHAs.
9. Update `tool/release/mcp_2026_07_28_release_metadata.json` with those exact
   SHAs. Set each `finalReleaseReviewed` field only after its complete delta
   review, record the agreed capability error code, and acknowledge the final
   error-code, conformance, and published-peer checks only after they pass.
   Set `tasksExtension.pinnedContentsReviewed` and
   `tasksExtension.failedStateErrorShapeReviewed`, and
   `tasksExtension.timingFieldIntegerSemanticsReviewed` independently; none is
   implied by `finalReleaseReviewed`.
   These explicit acknowledgements intentionally block stable publishing now
   while leaving coordinated prereleases available.
10. Update the official conformance package and the published TypeScript and
   Python SDK fixtures only after each candidate passes locally in both
   supported directions.
11. Sweep every release-facing surface, including `README.md`, `llms.txt`,
   `CHANGELOG.md`, `example/example.md`, `doc/`, the CLI README/changelog/docs,
    generated templates, package metadata, and public API examples. Remove
    prerelease claims only when the final tag supports them, and keep known
    peer/referee gaps explicit. Set
    `releaseDocumentation.finalReleaseReviewed` only after this sweep is
    complete; the stable metadata gate intentionally rejects an unacknowledged
    documentation review.
12. Confirm the final conformance runner defaults, expected-failure manifests,
   SDK fixture pins, dated spec paths, and document/example inventories all
   point at the same reviewed release inputs.

The release is blocked if either final source is unavailable, the pinned
example audit is not complete, the core and Tasks extension disagree on a wire
contract, or an official suite needs an unexplained expected failure.

## 2. Run the release gate

From the repository root:

```bash
dart pub get
dart pub get --no-precompile -C packages/mcp_dart_cli
dart pub get --no-precompile -C example/anthropic-client
dart pub get --no-precompile -C example/fetch-server
dart pub get --no-precompile -C example/gemini-client
dart pub get --no-precompile -C example/jaspr-client
flutter pub get --no-precompile -C example/flutter_http_client
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart tool/validate_release_metadata.dart --package mcp_dart
dart tool/validate_release_metadata.dart --package mcp_dart_cli
SPEC_REF="$(tr -d '[:space:]' < tool/testing/mcp_2026_07_28_spec_ref.txt)"
git clone --filter=blob:none --no-checkout \
  https://github.com/modelcontextprotocol/modelcontextprotocol.git \
  .dart_tool/mcp-spec
git -C .dart_tool/mcp-spec fetch --depth=1 origin "$SPEC_REF"
git -C .dart_tool/mcp-spec checkout --detach FETCH_HEAD
dart run tool/spec_example_audit.dart \
  .dart_tool/mcp-spec/schema/2026-07-28/examples
dart run tool/spec_document_inventory_audit.dart \
  .dart_tool/mcp-spec/docs/specification/2026-07-28
TASKS_SPEC_REF="$(tr -d '[:space:]' \
  < tool/testing/mcp_2026_07_28_tasks_spec_ref.txt)"
git clone --filter=blob:none --no-checkout \
  https://github.com/modelcontextprotocol/ext-tasks.git \
  .dart_tool/mcp-ext-tasks
git -C .dart_tool/mcp-ext-tasks fetch --depth=1 origin "$TASKS_SPEC_REF"
git -C .dart_tool/mcp-ext-tasks checkout --detach FETCH_HEAD
dart run tool/testing/audit_tasks_extension.dart \
  .dart_tool/mcp-ext-tasks
JSON_SCHEMA_SUITE_REF="$(tr -d '[:space:]' \
  < tool/testing/json_schema_test_suite_ref.txt)"
git clone --filter=blob:none --no-checkout \
  https://github.com/json-schema-org/JSON-Schema-Test-Suite.git \
  .dart_tool/json-schema-test-suite
git -C .dart_tool/json-schema-test-suite fetch --depth=1 \
  origin "$JSON_SCHEMA_SUITE_REF"
git -C .dart_tool/json-schema-test-suite checkout --detach FETCH_HEAD
dart run tool/testing/run_json_schema_2020_12_suite.dart \
  .dart_tool/json-schema-test-suite/tests/draft2020-12
dart run tool/testing/run_json_schema_draft7_suite.dart \
  .dart_tool/json-schema-test-suite/tests/draft7
dart run test/conformance/run_2025_server_conformance.dart \
  --timeout-seconds 90 --isolate-scenarios
CONFORMANCE_VERSION=0.2.0-alpha.9 # Replace with the final compatible release.
npx -y "@modelcontextprotocol/conformance@$CONFORMANCE_VERSION" client \
  --command "dart run test/conformance/mcp_2026_07_28_client.dart" \
  --suite all --spec-version 2025-11-25 --verbose
dart run test/conformance/run_2026_07_28_server_conformance.dart \
  --timeout-seconds 90
dart run test/conformance/run_2026_07_28_client_conformance.dart \
  --timeout-seconds 90
cd test/interop/ts_2026_07_28 && npm ci && cd ../../..
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=dart-to-ts
dart run tool/testing/run_ts_2026_07_28_interop.dart \
  --direction=ts-to-dart
python3 -m venv .dart_tool/python-2026-interop
.dart_tool/python-2026-interop/bin/python -m pip install \
  -r test/interop/python_2026_07_28/requirements.txt
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_interop.dart \
  --direction=dart-to-python
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_interop.dart \
  --direction=python-to-dart \
  --expect-published-python-client-gap
dart run tool/testing/run_browser_2026_07_28_interop.dart
dart run tool/testing/run_flutter_web_example_e2e.dart
dart pub publish --dry-run
```

Resolve every standalone package before the repository-wide format check so
the formatter uses each package's language version and configuration. In
particular, formatting the Flutter example without resolving its
`flutter_lints` include can report false drift.

Confirm the final repository's dated schema layout before running this command;
do not substitute `schema/draft`, which may advance to the next protocol after
the release tag. Update CI and any pinned audit helpers to the same dated path.
The stable metadata gate inspects active Core CI `run` commands, so dated paths
in comments cannot hide an audit that still targets `draft`.

Also run the nested example and CLI validation already enforced by CI. Require
the Dart 3.4 minimum-SDK lane and the `dart_apitool` comparison against
published `mcp_dart 2.2.2` to pass, including the checked-in compile fixtures
for interfaces and callbacks. Review any ignored requiredness diagnostics
instead of treating the compatibility tool configuration as blanket approval.
The release PR must have all required checks green and no unresolved review
thread.

## 3. Prepare stable SDK metadata

On the final release-prep commit:

- Set the root package version to `2.3.0`.
- Restore root `documentation` and all user-facing repository links to `main`.
- Replace prerelease dependency snippets in the README, getting-started,
  quick-reference, and release docs with `mcp_dart: ^2.3.0`.
- Keep the durable `2026-07-28` document, fixture, command, and workflow names;
  update only maturity wording that changes when the final specification ships.
- Promote `stableProtocolVersion` and `defaultProtocolVersion` to the final
  `2026-07-28` constant, but keep `latestInitializationProtocolVersion` and
  `legacyProtocolVersions.first` at `2025-11-25`. Run the profile regression
  tests to prove `McpProtocol.legacy` never sends a stateless version through
  `initialize`.
- Preserve the mcp_dart 2.2 values of deprecated `latestProtocolVersion` and
  `supportedProtocolVersions`. Keep the former aliased to
  `latestInitializationProtocolVersion` and the latter to
  `legacyProtocolVersions`; promote `allSupportedProtocolVersions`, not either
  compatibility alias, to the final version.
- Stop presenting `previewProtocolVersion` as the preferred public name. Keep
  it only as a deprecated alias of `stableProtocolVersion` for prerelease
  adopters, and update examples to use the stable/default constants.
- Move the relevant root changelog entries under `## 2.3.0` and remove wording
  that presents the now-final protocol as draft-only.
- Keep migration and compatibility notes explicit: `McpProtocol.stable`
  selects the current stable protocol while legacy profiles remain opt-in.
- Run `dart pub publish --dry-run` again from a clean checkout of the exact
  release commit. Do not create the release tag until this succeeds.
- Run the shared metadata validator with `--package mcp_dart --tag v2.3.0`.
  It must report no pending final-input acknowledgement, require substantive
  notes under the exact `## 2.3.0` changelog heading, and verify that the
  default protocol is `2026-07-28` while the initialization and deprecated
  compatibility aliases remain at `2025-11-25`.
- Verify the tag-triggered publish workflow rejects an SDK or CLI tag whose
  version does not match the selected package `pubspec.yaml`. The release
  workflow derives its candidate tag from that same package version.
- Verify the release workflow finds successful push runs from the exact
  `.github/workflows/test_core.yml` and `.github/workflows/test_cli.yml` files
  for the stable release commit. SDK releases additionally require
  `.github/workflows/interop_2026_07_28.yml`. Display-name matches from another
  workflow do not satisfy the gate, and a missing or unsuccessful run blocks
  the stable tag.
- Verify `Create Release` runs repository code and its publish dry run in the
  read-only validation job. Its minimal write job must write
  `mcp_dart/release/mcp_dart` only after the existing tag is verified or the
  new tag push succeeds. The tag-triggered workflow must wait for and require
  that exact-commit status, then repeat the exact-SHA CI lookup before
  requesting pub.dev OIDC.

Merge the release PR to `main` only after this commit passes the complete gate.

## 4. Publish and verify `mcp_dart`

1. Dispatch `Create Release` for `mcp_dart` from the merged `main` commit.
   New stable tags require the latest `main` commit. A retry may reuse an
   existing tag only when that tag resolves to the exact original release
   commit; the workflow never moves it.
2. Verify tag `v2.3.0`, the GitHub release, and the `Publish to pub.dev` workflow.
   If GitHub release creation fails after the tag was pushed, use **Re-run all
   jobs** on the original failed `Create Release` run so the workflow retains
   the original release commit. Do not start a fresh dispatch after `main`
   advances; it will correctly reject an existing tag that resolves to a
   different commit. If publication fails after the tag was pushed, rerun the
   failed tag-triggered `Publish to pub.dev` workflow; reusing a tag does not
   emit another push event.
3. Confirm pub.dev shows version `2.3.0`, correct `main` documentation links,
   and a successful package analysis.
4. Create a clean temporary Dart project, resolve `mcp_dart: ^2.3.0`, and run a
   minimal MCP 2026-07-28 client/server smoke test using only the published
   package.

Do not start the stable CLI release until the published SDK resolves publicly.

## 5. Prepare and publish `mcp_dart_cli`

- Set the CLI version and `packageVersion` constant to `0.2.0`, and set
  `generatedSdkConstraint` to `^2.3.0`.
- Set its SDK dependency to `mcp_dart: ^2.3.0`.
- Restore CLI homepage/documentation links to `main` and update templates and
  dependency snippets that still name prerelease SDK versions.
- Move CLI changelog entries under `## 0.2.0`.
- Run the shared metadata validator with `--package mcp_dart_cli --tag
  mcp_dart_cli-v0.2.0`; it also requires substantive notes under the exact
  `## 0.2.0` heading and verifies `packageVersion`, the generated SDK
  constraint, the SDK dependency, tagged template URL, and stable metadata.
- Validate against pub.dev rather than the monorepo override:

```bash
dart run tool/validate_cli_publish.dart --published-sdk
dart pub global activate pana
cd packages/mcp_dart_cli
dart pub global run pana --no-warning --exit-code-threshold 0
```

Then dispatch `Create Release` for `mcp_dart_cli`, verify the
`mcp_dart_cli-v0.2.0` publish, and verify the standalone binary workflow and
release assets for every supported platform. If the binary workflow must be
dispatched manually, supply the release tag; both build and asset jobs verify
and check out that exact tag before attaching files.
The standalone build matrix removes the monorepo override and verifies the
declared minimum hosted SDK before compiling each platform binary. `Create
Release` and the tag-triggered publish workflow each repeat that override-free
resolution from a clean candidate, then run the non-interop CLI tests,
analysis, compilation, and smoke test. All three gates therefore exercise the
already-published minimum SDK rather than the monorepo checkout or a newer
compatible 2.3.x release.

## 6. Public day-0 verification

- Activate `mcp_dart_cli 0.2.0` from pub.dev in a clean environment.
- Generate a project and run its tests. Verify stdio with `mcp_dart inspect`
  from the generated directory. Then start Streamable HTTP with
  `mcp_dart serve --transport http --host 127.0.0.1 --port 3000` and inspect
  `http://localhost:3000/mcp` from a separate process.
- Recheck GitHub release links, pub.dev documentation links, installer asset
  resolution, and both stable package versions.
- Confirm the normal `main` interop schedule is active and there is no duplicate
  temporary monitor.

If any public verification fails, stop promotion, document the exact affected
surface, and prepare a patch release. Never move or recreate an already
published tag.
