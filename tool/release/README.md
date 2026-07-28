# Release metadata gate

## Release prep workflow

`main` is the only release source and should remain the stable, current branch.
Checked-in release-facing links therefore use `main`. The publish workflows
copy the selected package to an isolated candidate and rewrite those links to
the package's immutable release tag; the working tree and `main` are not
modified.

Prepare every publication in a PR targeting `main` with the `release-prep`
label. The PR must increase the version in either `pubspec.yaml`,
`packages/mcp_dart_cli/pubspec.yaml`, or both. The version determines the
channel: a SemVer prerelease suffix selects a dev release, while a version
without one selects a stable release. A coordinated SDK and CLI prep must put
both packages on the same channel.

The prep PR should contain all release metadata and essential source changes:

- move each selected package's notes to an exact version heading in its
  changelog;
- update package versions, coordinated SDK constraints, generated version
  constants, templates, and the day-0 release manifest as applicable;
- finish release-facing documentation and record the exact reviewed inputs;
- keep same-repository source links on `main`.

`Validate Release Prep` derives the package set from version changes and runs
the shared metadata gate for each selected package. After a labeled prep PR is
merged, `Release Merged Prep` checks out the exact merge commit and invokes the
existing release authorization workflow automatically. Every automatic release
waits for all required push CI on that exact commit. When both packages are
selected, the SDK is released first and the workflow waits until that exact SDK
version is visible on pub.dev before releasing the CLI.

Each package release creates its immutable tag and GitHub release. The tag then
starts `Publish to pub.dev`, which publishes the already validated immutable
candidate through pub.dev OIDC. Manual `Create Release` dispatch remains only
as a recovery path; never push release tags by hand or move an existing tag.

Before using the automation, create the repository label `release-prep` and
keep the existing `RELEASE_PAT` Actions secret available for the narrowly
scoped tag push. Branch protection should require the normal SDK, CLI, interop,
and `Validate Release Prep` checks before a prep PR can merge.

`dart tool/validate_release_metadata.dart` is the shared metadata gate used by
both the GitHub release workflow and the tag-triggered pub.dev publish
workflow. It validates SDK/CLI version coordination, tag names, immutable
prerelease documentation URLs, exact-version changelog headings with
substantive release notes, protocol compatibility constants, and pinned
day-0 inputs.

The `mcp_2026_07_28_release_metadata.json` manifest records the exact inputs
reviewed for the release. Stable publication is gated by exact reviewed inputs,
not by the publication timing of every upstream project. When a later final
artifact becomes available before publication, review and record it without
silently changing the audited contract. The following fields record whether
final upstream artifacts were available and reviewed, but they are
informational and do not block publication:

- `coreSpecification.finalReleaseReviewed`
- `missingRequiredClientCapability.coreFinalReleaseReviewed`
- `subscriptionTermination.finalTextsAgree`
- `releaseDocumentation.finalReleaseReviewed`
- `officialConformance.finalReleaseReviewed`
- `publishedInteropFixtures.finalReleaseReviewed`

The Core and experimental Tasks refs must be full commit SHAs matching their
files under `tool/testing/`. Tasks remains separately pinned, but its upstream
repository describes it as experimental and not an official MCP extension; a
stable Core release does not wait for a nonexistent final Tasks release. The
capability error code must match the SDK implementation, and the conformance
version must match Core CI and every conformance wrapper.
Core CI audits the schema examples and specification document inventory from
the exact pinned Core commit. The reviewed final Core uses the versioned
`schema/2026-07-28` and `docs/specification/2026-07-28` paths. The validator
requires the active audit commands to use that recorded checkout layout
exactly; update those expectations together if a later reviewed input uses a
different layout.
Published TypeScript and Python versions must match the interop fixtures. A
stable release also requires both published-SDK directions to pass without an
`--expect-published-*-client-gap` allowance in CI or any release-facing interop
command or guide.
Stable SDK and CLI checks also reject prerelease dependency/version references
on their current user-facing release surfaces. The SDK gate scans `README.md`,
`llms.txt`, and every Markdown file under `doc/` and `example/`. The CLI gate
also scans its package and generated-template Markdown, and requires the simple
template's `mcp_dart` dependency to match `generatedSdkConstraint`. Historical
changelog entries and the completed prerelease rehearsal in the runbook remain
intact.

The Tasks acknowledgements are deliberately separate. Fetching the pinned
commit is not a content audit: inspect its specification, SEP, and schema
against the SDK and tests. Record the upstream experimental status and known
wire differences, including:

- failed-task `error` prose describes a JSON-RPC error shape, the schema
  accepts a generic JSON object, and the SDK exposes `JsonRpcErrorData`;
- `ttlMs` and `pollIntervalMs` are integer milliseconds in prose, unrestricted
  JSON numbers in the schema, and mathematically integral `int` values in Dart;
- experimental Tasks uses `-32003` for
  `MissingRequiredClientCapability`, while the final Core release and this
  SDK use `-32021`;
- Tasks has no official-conformance or checked-in cross-SDK coverage.

These differences are outside the stable Core claim. The gate requires their
experimental status and disclosure to be reviewed; it does not misrepresent
them as a final Tasks contract.

The final Core specification remains internally ambiguous about server-initiated
subscription teardown. Its cancellation page requires a
`notifications/cancelled` message, while the subscriptions page describes a
terminal empty response followed by stream closure and the schema describes
the server notification specifically for stdio. The current SDK sends both
the cancellation and terminal response on stdio, and the terminal response on
Streamable HTTP. Reconcile those final texts and the transport-specific wire
tests before setting `subscriptionTermination.finalTextsAgree`; leaving this
informational field false does not block a release whose documented behavior
and regression tests pass.

Every tag requires exact-commit `mcp_dart/release/<package>` authorization from
`Create Release`; manually pushed stable and prerelease tags cannot publish.
The workflow validates metadata and the pub.dev dry run in a read-only job,
then a minimal write job checks the exact validated commit and tag before
writing authorization. New-tag authorization transitions through `pending`
and becomes `success` only after the PAT-backed tag push succeeds; failures
overwrite it with `failure`. The publish workflow waits for that transition.
Every tag additionally requires the latest default-branch source and exact-SHA
CI runs, and the publish workflow repeats the exact-SHA CI check.
CI provenance is matched by the exact workflow files
`.github/workflows/test_core.yml`, `.github/workflows/test_cli.yml`, and, for
the SDK, `.github/workflows/interop_2026_07_28.yml`; matching display names are
not sufficient. For CLI candidates, both workflows remove the monorepo
override, pin and verify only the declared minimum SDK from pub.dev while
resolving other dependencies normally, run the non-interop test suite and
analysis, compile and smoke-test the binary, and run the publish dry-run before
authorization or publication.

Run `bash tool/release/verify_release_ci_test.sh` to exercise the local
workflow-provenance fixtures without calling GitHub.

Run `bash tool/release/verify_release_source_test.sh` to exercise the
latest-default-branch and immutable-tag recovery gates against a local Git
remote.

Run `bash tool/release/verify_release_workflow_security_test.sh` to ensure
release validation stays read-only and the PAT remains scoped to the new-tag
push step.

Run `bash tool/release/verify_release_prep_workflow_test.sh` to verify labeled
prep detection, exact-merge provenance, release-CI waiting, permission scope,
and coordinated SDK-before-CLI ordering.

`Release Merged Prep` defaults to 60 CI checks every 30 seconds and 60 pub.dev
checks every 15 seconds. Maintainers can tune those limits with the positive
integer repository variables `RELEASE_CI_ATTEMPTS`,
`RELEASE_CI_INTERVAL_SECONDS`, `RELEASE_PUB_ATTEMPTS`, and
`RELEASE_PUB_INTERVAL_SECONDS` without editing the workflow.

Run `bash tool/release/verify_publish_workflow_security_test.sh` to verify the
pre-checkout authorization gate, immutable candidate handoff, and OIDC job
isolation, including prerelease rejection and pending-status polling.

Run `bash tool/release/verify_cli_binary_workflow_test.sh` to verify that
standalone CLI build jobs are read-only, remove the monorepo SDK override, and
resolve the exact minimum hosted SDK before compiling release binaries. Only
the final asset-attachment job retains repository write permission.
