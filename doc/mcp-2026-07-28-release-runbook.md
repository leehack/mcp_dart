# MCP 2026-07-28 Day-0 Release Runbook

Use this checklist after the official MCP `2026-07-28` specification is tagged.
Do not publish the stable Dart packages from a moving draft commit.

## Branch policy

- [PR #306](https://github.com/leehack/mcp_dart/pull/306) targets `main` and
  remains open until the final spec delta is understood.
- Keep `dev/2026-07-28-rc` as a read-only archive. Published
  `mcp_dart 2.3.0-dev.0`, `2.3.0-dev.1`, and matching CLI prereleases contain
  documentation URLs for that branch; deleting it would break their metadata.
- The default-branch monitor checks `dev/2026-07-28` daily. PR #306 deletes it
  as the normal interop schedule reaches `main`, avoiding duplicate schedules.

## 1. Freeze the official inputs

1. Record the final specification tag and commit SHA.
2. Diff that SHA against `tool/testing/mcp_2026_release_spec_ref.txt`.
3. Review every schema, example, conformance, and normative prose change in
   that range; do not rely only on generated schema diffs.
4. Update `tool/testing/mcp_2026_release_spec_ref.txt` to the final SHA.
5. Update the official conformance package and the published TypeScript and
   Python SDK fixtures only after each candidate passes locally in both
   supported directions.

The release is blocked if the final tag is unavailable, the pinned example
audit is not complete, or an official suite needs an unexplained expected
failure.

## 2. Run the release gate

From the repository root:

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
SPEC_REF="$(tr -d '[:space:]' < tool/testing/mcp_2026_release_spec_ref.txt)"
git clone --filter=blob:none --no-checkout \
  https://github.com/modelcontextprotocol/modelcontextprotocol.git \
  .dart_tool/mcp-spec
git -C .dart_tool/mcp-spec fetch --depth=1 origin "$SPEC_REF"
git -C .dart_tool/mcp-spec checkout --detach FETCH_HEAD
dart run tool/spec_example_audit.dart \
  .dart_tool/mcp-spec/schema/draft/examples
dart run test/conformance/run_2025_server_conformance.dart \
  --timeout-seconds 90 --isolate-scenarios
CONFORMANCE_VERSION=0.2.0-alpha.9 # Replace with the final compatible release.
npx -y "@modelcontextprotocol/conformance@$CONFORMANCE_VERSION" client \
  --command "dart run test/conformance/mcp_2026_07_28_rc_client.dart" \
  --suite all --spec-version 2025-11-25 --verbose
dart run test/conformance/run_2026_07_28_rc_server_conformance.dart \
  --timeout-seconds 90
dart run test/conformance/run_2026_07_28_rc_client_conformance.dart \
  --timeout-seconds 90
cd test/interop/ts_2026_07_28_rc && npm ci && cd ../../..
dart run tool/testing/run_ts_2026_07_28_rc_interop.dart
python3 -m venv .dart_tool/python-2026-interop
.dart_tool/python-2026-interop/bin/python -m pip install \
  -r test/interop/python_2026_07_28_rc/requirements.txt
MCP_PYTHON=.dart_tool/python-2026-interop/bin/python \
  dart run tool/testing/run_python_2026_07_28_rc_interop.dart
dart run tool/testing/run_browser_2026_07_28_rc_interop.dart
dart pub publish --dry-run
```

Also run the nested example and CLI validation already enforced by CI. The
release PR must have all required checks green and no unresolved review thread.

## 3. Prepare stable SDK metadata

On the final release-prep commit:

- Set the root package version to `2.3.0`.
- Restore root `documentation` and all user-facing repository links to `main`.
- Replace prerelease dependency snippets in the README, getting-started,
  quick-reference, and release docs with `mcp_dart: ^2.3.0`.
- Move the relevant root changelog entries under `## 2.3.0` and remove wording
  that presents the now-final protocol as draft-only.
- Keep migration and compatibility notes explicit: `McpProtocol.stable`
  selects the current stable protocol while legacy profiles remain opt-in.
- Run `dart pub publish --dry-run` again from a clean checkout of the exact
  release commit.

Merge the release PR to `main` only after this commit passes the complete gate.

## 4. Publish and verify `mcp_dart`

1. Dispatch `Create Release` for `mcp_dart` from the merged `main` commit.
   The workflow rejects stable versions dispatched from another ref or from a
   stale `main` commit.
2. Verify tag `v2.3.0`, the GitHub release, and the `Publish to pub.dev` workflow.
3. Confirm pub.dev shows version `2.3.0`, correct `main` documentation links,
   and a successful package analysis.
4. Create a clean temporary Dart project, resolve `mcp_dart: ^2.3.0`, and run a
   minimal 2026 client/server smoke test using only the published package.

Do not start the stable CLI release until the published SDK resolves publicly.

## 5. Prepare and publish `mcp_dart_cli`

- Set the CLI version and `packageVersion` constant to `0.2.0`.
- Set its SDK dependency to `mcp_dart: ^2.3.0`.
- Restore CLI homepage/documentation links to `main` and update templates and
  dependency snippets that still name prerelease SDK versions.
- Move CLI changelog entries under `## 0.2.0`.
- Validate against pub.dev rather than the monorepo override:

```bash
dart run tool/validate_cli_publish.dart --published-sdk
```

Then dispatch `Create Release` for `mcp_dart_cli`, verify the
`mcp_dart_cli-v0.2.0` publish, and verify the standalone binary workflow and
release assets for every supported platform.

## 6. Public day-0 verification

- Activate `mcp_dart_cli 0.2.0` from pub.dev in a clean environment.
- Generate a project, run its tests, start a server, and inspect/call it from a
  separate CLI process.
- Recheck GitHub release links, pub.dev documentation links, installer asset
  resolution, and both stable package versions.
- Confirm the release merge removed the temporary monitor and the normal
  `main` interop schedule is active.

If any public verification fails, stop promotion, document the exact affected
surface, and prepare a patch release. Never move or recreate an already
published tag.
