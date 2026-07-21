# Release metadata gate

`dart tool/validate_release_metadata.dart` is the shared metadata gate used by
both the GitHub release workflow and the tag-triggered pub.dev publish
workflow. It validates SDK/CLI version coordination, tag names, immutable
prerelease documentation URLs, exact-version changelog headings with
substantive stable release notes, protocol compatibility constants, and pinned
day-0 inputs.

The `mcp_2026_07_28_release_metadata.json` manifest records the exact inputs
reviewed for the release. Before the final specification is published, its
review acknowledgements intentionally remain `false`; prereleases still pass,
but a stable SDK or CLI release is blocked. On release day, update the refs and
version pins first, complete the full review, and only then set:

- `coreSpecification.finalReleaseReviewed`
- `tasksExtension.finalReleaseReviewed`
- `tasksExtension.pinnedContentsReviewed`
- `tasksExtension.failedStateErrorShapeReviewed`
- `tasksExtension.timingFieldIntegerSemanticsReviewed`
- `missingRequiredClientCapability.finalTextsAgree`
- `subscriptionTermination.finalTextsAgree`
- `releaseDocumentation.finalReleaseReviewed`
- `officialConformance.finalReleaseReviewed`
- `publishedInteropFixtures.finalReleaseReviewed`

The core and Tasks refs must be full commit SHAs matching their files under
`tool/testing/`. The capability error code must match the SDK implementation,
and the conformance version must match Core CI and every conformance wrapper.
Stable Core CI must audit the immutable `schema/2026-07-28` and
`docs/specification/2026-07-28` paths rather than the moving draft paths.
The validator inspects active workflow `run` commands and rejects comment-only
dated paths or any additional active audit that still targets `draft`.
Published TypeScript and Python versions must match the interop fixtures. A
stable release also requires both published-SDK directions to pass without an
`--expect-published-*-client-gap` allowance in CI or any release-facing interop
command or guide.
`releaseDocumentation.finalReleaseReviewed` is set only after the day-of sweep
has removed stale preview, release-candidate, prerelease-version, and old
protocol-constant claims from every current release-facing surface. Historical
changelog entries and the completed prerelease rehearsal remain unchanged.
Stable SDK and CLI checks also reject prerelease dependency/version references
on their current user-facing release surfaces. The SDK gate scans `README.md`,
`llms.txt`, and every Markdown file under `doc/` and `example/`. The CLI gate
also scans its package and generated-template Markdown, and requires the simple
template's `mcp_dart` dependency to match `generatedSdkConstraint`. Historical
changelog entries and the completed prerelease rehearsal in the runbook remain
intact.

The Tasks acknowledgements are deliberately separate. Fetching the pinned
commit is not a content audit: inspect its specification, SEP, and schema
against the SDK and tests. In particular, reconcile the normative failed-task
`error` prose (a JSON-RPC error shape) with the current schema's generic JSON
object and the SDK's `JsonRpcErrorData` representation before acknowledging the
stable gate.

Also reconcile the Tasks prose that defines `ttlMs` and `pollIntervalMs` as
integer milliseconds with the current generated schema's unrestricted JSON
`number` fields. The SDK deliberately accepts only mathematically integral
values and stores them as `int`; record the final decision through
`tasksExtension.timingFieldIntegerSemanticsReviewed` before stable release.

The pinned Core draft is also internally ambiguous about server-initiated
subscription teardown. Its cancellation page requires a
`notifications/cancelled` message, while the subscriptions page describes a
terminal empty response followed by stream closure and the schema describes
the server notification specifically for stdio. The current SDK sends both
the cancellation and terminal response on stdio, and the terminal response on
Streamable HTTP. Reconcile those final texts and the transport-specific wire
tests before setting `subscriptionTermination.finalTextsAgree`.

Every tag requires exact-commit `mcp_dart/release/<package>` authorization from
`Create Release`; manually pushed stable and prerelease tags cannot publish.
The workflow validates metadata and the pub.dev dry run in a read-only job,
then a minimal write job checks the exact validated commit and tag before
writing authorization. New-tag authorization transitions through `pending`
and becomes `success` only after the PAT-backed tag push succeeds; failures
overwrite it with `failure`. The publish workflow waits for that transition.
Stable tags additionally require the latest default-branch source, exact-SHA
CI runs, and final-spec acknowledgements, and the publish workflow repeats the
exact-SHA CI check.
CI provenance is matched by the exact workflow files
`.github/workflows/test_core.yml`, `.github/workflows/test_cli.yml`, and, for
the SDK, `.github/workflows/interop_2026_07_28.yml`; matching display names are
not sufficient. For CLI candidates, both workflows remove the monorepo
override, downgrade to and verify the declared minimum SDK from pub.dev, run
the non-interop test suite and analysis, compile and smoke-test the binary, and
run the publish dry-run before authorization or publication.

Run `bash tool/release/verify_stable_release_ci_test.sh` to exercise the local
workflow-provenance fixtures without calling GitHub.

Run `bash tool/release/verify_stable_release_source_test.sh` to exercise the
latest-default-branch and immutable-tag recovery gates against a local Git
remote.

Run `bash tool/release/verify_release_workflow_security_test.sh` to ensure
release validation stays read-only and the PAT remains scoped to the new-tag
push step.

Run `bash tool/release/verify_publish_workflow_security_test.sh` to verify the
pre-checkout authorization gate, immutable candidate handoff, and OIDC job
isolation, including prerelease rejection and pending-status polling.
