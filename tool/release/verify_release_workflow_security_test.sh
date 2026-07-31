#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

VALIDATION_JOB="$FIXTURE_DIR/validation-job.yml"
WRITE_JOB="$FIXTURE_DIR/write-job.yml"
sed -n '/^  validate-release:/,/^  create-release:/p' "$WORKFLOW" >"$VALIDATION_JOB"
sed -n '/^  create-release:/,$p' "$WORKFLOW" >"$WRITE_JOB"
WRITE_RUN_SCRIPTS="$FIXTURE_DIR/write-run-scripts.sh"
awk '
  /^        run: \|$/ {
    in_run = 1
    next
  }
  in_run && /^      - / {
    in_run = 0
  }
  in_run {
    print
  }
' "$WRITE_JOB" >"$WRITE_RUN_SCRIPTS"

fail() {
  echo "$1" >&2
  exit 1
}

grep -q '^  validate-release:' "$VALIDATION_JOB" ||
  fail "The read-only release validation job is missing."
grep -q '^  create-release:' "$WRITE_JOB" ||
  fail "The minimal release write job is missing."
grep -q '      contents: read$' "$VALIDATION_JOB" ||
  fail "Release validation must have read-only repository contents."
if grep -qE 'RELEASE_PAT|contents: write|statuses: write' "$VALIDATION_JOB"; then
  fail "Release validation unexpectedly has a release credential or write permission."
fi
grep -q 'SOURCE_DIRECTORY=packages/mcp_dart_cli' "$VALIDATION_JOB" ||
  fail "CLI release staging must copy only the nested package."
grep -q 'SOURCE_DIRECTORY=\.' "$VALIDATION_JOB" ||
  fail "SDK release staging must copy the repository package root."
grep -q -- '--exclude pubspec_overrides.yaml' "$VALIDATION_JOB" ||
  fail "Release staging must remove monorepo SDK overrides."
grep -q 'dart tool/release/update_release_links.dart' "$VALIDATION_JOB" ||
  fail "Release validation must pin staged documentation links to the tag."
grep -q 'bash tool/release/verify_release_source.sh' "$VALIDATION_JOB" ||
  fail "Every release must use the default-branch source gate."
grep -q 'bash tool/release/verify_release_ci.sh' "$VALIDATION_JOB" ||
  fail "Every release must use the exact-commit CI gate."
# Match the literal shell expansion in the workflow.
# shellcheck disable=SC2016
grep -Fq 'VERSION_WITHOUT_BUILD=${VERSION%%+*}' "$VALIDATION_JOB" ||
  fail "Release type detection must ignore SemVer build metadata."
if grep -q "if: steps.release-type.outputs.prerelease == 'false'" \
  "$VALIDATION_JOB"; then
  fail "Source and CI provenance checks must not be stable-only."
fi
LINK_UPDATE_LINE=$(grep -n 'dart tool/release/update_release_links.dart' \
  "$VALIDATION_JOB" | cut -d: -f1)
DRY_RUN_LINE=$(grep -n 'run: dart pub publish --dry-run' \
  "$VALIDATION_JOB" | cut -d: -f1)
if [[ -z "$LINK_UPDATE_LINE" || -z "$DRY_RUN_LINE" ]] ||
  ((LINK_UPDATE_LINE >= DRY_RUN_LINE)); then
  fail "Release links must be pinned before publish validation."
fi
grep -q '      contents: write' "$WRITE_JOB" ||
  fail "The release write job cannot create tags or releases."
grep -q '      statuses: write$' "$WRITE_JOB" ||
  fail "The release write job cannot authorize the exact commit."
grep -q '      actions: read$' "$WRITE_JOB" ||
  fail "The release write job cannot download validated release notes."

if [[ $(grep -c 'uses: actions/checkout@' "$WORKFLOW") -ne 3 ]]; then
  fail "The release workflow must have package, control, and write checkouts."
fi
if [[ $(grep -c 'persist-credentials: false' "$WORKFLOW") -ne 3 ]]; then
  fail "All release checkouts must disable persisted credentials."
fi
if [[ $(grep -c 'RELEASE_PAT:' "$WORKFLOW") -ne 2 ]]; then
  fail "RELEASE_PAT must be declared for callers and exposed only to the tag push."
fi
grep -A3 '^    secrets:$' "$WORKFLOW" | grep -q 'RELEASE_PAT:' ||
  fail "The reusable release workflow must declare its tag-push secret."
# Match the literal GitHub expression.
# shellcheck disable=SC2016
if grep -Fq '${{ needs.validate-release.outputs' "$WRITE_RUN_SCRIPTS"; then
  fail "Validated repository values must enter privileged scripts through env."
fi
# Privileged scripts must neither execute Dart nor reference repository tooling.
FORBIDDEN_WRITE_TOOLING_PATTERN='(^|[^[:alnum:]_.-])dart([^[:alnum:]_.-]|$)|tool/|prepare_release_notes'
for forbidden_command in \
  'dart' \
  $'dart\t--version' \
  '"/opt/sdk/bin/dart" --version' \
  $'bash \\\n  tool/release/example.sh' \
  'sh tool/release/example.sh' \
  './tool/release/example.sh'; do
  if ! grep -qE "$FORBIDDEN_WRITE_TOOLING_PATTERN" \
    <<<"$forbidden_command"; then
    fail "The write-job tooling guard must reject: $forbidden_command"
  fi
done
for allowed_command in \
  'echo dartboard' \
  'echo dart-sdk' \
  'echo example.dart' \
  'echo my_dart_tool'; do
  if grep -qE "$FORBIDDEN_WRITE_TOOLING_PATTERN" <<<"$allowed_command"; then
    fail "The write-job tooling guard must allow: $allowed_command"
  fi
done
if grep -qE "$FORBIDDEN_WRITE_TOOLING_PATTERN" "$WRITE_RUN_SCRIPTS"; then
  fail "The release write job must not execute Dart or reference repository tooling."
fi

CONTROL_CHECKOUT="$FIXTURE_DIR/control-checkout.yml"
sed -n \
  '/- name: Checkout release-note control tooling/,/- name: Prepare immutable release notes/p' \
  "$VALIDATION_JOB" >"$CONTROL_CHECKOUT"
# Match the literal GitHub expressions.
# shellcheck disable=SC2016
grep -Fq 'repository: ${{ job.workflow_repository }}' "$CONTROL_CHECKOUT" ||
  fail "Release-note control tooling must come from the reusable workflow repository."
# shellcheck disable=SC2016
grep -Fq 'ref: ${{ job.workflow_sha }}' "$CONTROL_CHECKOUT" ||
  fail "Release-note control tooling must be pinned to the reusable workflow SHA."
grep -q 'path: release-control' "$CONTROL_CHECKOUT" ||
  fail "Release-note control tooling must use an isolated checkout path."
grep -q 'persist-credentials: false' "$CONTROL_CHECKOUT" ||
  fail "The control checkout must not persist credentials."
# Match the literal shell path in workflow code.
# shellcheck disable=SC2016
grep -Fq \
  'dart "$GITHUB_WORKSPACE/release-control/tool/release/prepare_release_notes.dart"' \
  "$VALIDATION_JOB" ||
  fail "Release notes must use the pinned control renderer."
if grep -q 'dart tool/release/prepare_release_notes.dart' "$VALIDATION_JOB"; then
  fail "Release notes must not execute a renderer from the release checkout."
fi

CANDIDATE_LINE=$(grep -n -- '- name: Prepare release candidate' \
  "$VALIDATION_JOB" | cut -d: -f1)
CONTROL_LINE=$(grep -n -- '- name: Checkout release-note control tooling' \
  "$VALIDATION_JOB" | cut -d: -f1)
RENDER_LINE=$(grep -n -- '- name: Prepare immutable release notes' \
  "$VALIDATION_JOB" | cut -d: -f1)
UPLOAD_LINE=$(grep -n -- '- name: Upload immutable release notes' \
  "$VALIDATION_JOB" | cut -d: -f1)
DEPENDENCIES_LINE=$(grep -n -- '- name: Install release dependencies' \
  "$VALIDATION_JOB" | cut -d: -f1)
if [[ -z "$CANDIDATE_LINE" || -z "$CONTROL_LINE" || -z "$RENDER_LINE" ||
  -z "$UPLOAD_LINE" || -z "$DEPENDENCIES_LINE" ]] ||
  ((CANDIDATE_LINE >= CONTROL_LINE ||
    CONTROL_LINE >= RENDER_LINE ||
    RENDER_LINE >= UPLOAD_LINE ||
    UPLOAD_LINE >= DEPENDENCIES_LINE)); then
  fail "Release notes must be rendered and uploaded after staging and before dependencies."
fi
grep -qE 'actions/upload-artifact@[0-9a-f]{40} ' "$VALIDATION_JOB" ||
  fail "The release-note upload action must be pinned to a commit SHA."
grep -q 'path:.*release-notes/release-notes.md' "$VALIDATION_JOB" ||
  fail "Only the rendered release-note file should be uploaded."
grep -q 'sha256sum.*release-notes.md' "$VALIDATION_JOB" ||
  fail "The read-only job must hash the rendered release notes."

VALIDATION_OUTPUTS="$FIXTURE_DIR/validation-outputs.yml"
sed -n '/^    outputs:/,/^    steps:/p' \
  "$VALIDATION_JOB" >"$VALIDATION_OUTPUTS"
grep -q 'release_notes_artifact:' "$VALIDATION_OUTPUTS" ||
  fail "The release-note artifact name must cross the job boundary."
grep -q 'release_notes_sha:' "$VALIDATION_OUTPUTS" ||
  fail "The release-note digest must cross the job boundary."
if grep -qE 'release_notes_(body|path)' "$VALIDATION_OUTPUTS"; then
  fail "Release-note bodies and paths must not cross through job outputs."
fi

grep -qE 'actions/download-artifact@[0-9a-f]{40} ' "$WRITE_JOB" ||
  fail "The release-note download action must be pinned to a commit SHA."
grep -q 'sha256sum --check --strict' "$WRITE_JOB" ||
  fail "The release write job must verify the release-note digest."
DOWNLOAD_LINE=$(grep -n -- '- name: Download immutable release notes' \
  "$WRITE_JOB" | cut -d: -f1)
VERIFY_LINE=$(grep -n -- '- name: Verify immutable release notes' \
  "$WRITE_JOB" | cut -d: -f1)
RESOLVE_TAG_LINE=$(grep -n -- '- name: Resolve release tag' \
  "$WRITE_JOB" | cut -d: -f1)
if [[ -z "$DOWNLOAD_LINE" || -z "$VERIFY_LINE" ||
  -z "$RESOLVE_TAG_LINE" ]] ||
  ((DOWNLOAD_LINE >= VERIFY_LINE || VERIFY_LINE >= RESOLVE_TAG_LINE)); then
  fail "Release notes must be downloaded and verified before tag mutation."
fi
grep -q 'body_path:.*release-notes/release-notes.md' "$WRITE_JOB" ||
  fail "GitHub releases must use the verified release-note file."
grep -q 'append_body: false' "$WRITE_JOB" ||
  fail "Recovery must replace stale release text instead of appending to it."
if grep -qE 'generate_release_notes:|^          body:' "$WRITE_JOB"; then
  fail "GitHub-generated or inline release bodies must stay disabled."
fi

grep -A12 -- '- name: Push new release tag' "$WORKFLOW" |
  grep -q 'RELEASE_PAT:' ||
  fail "The new-tag push step is missing RELEASE_PAT."
grep -A2 -- '- name: Authorize existing release tag' "$WRITE_JOB" |
  grep -q "needs_push == 'false'" ||
  fail "Existing tags must be authorized only after exact-tag validation."
PUSH_STEP="$FIXTURE_DIR/push-step.yml"
sed -n '/- name: Push new release tag/,/- name: Create GitHub Release/p' \
  "$WRITE_JOB" >"$PUSH_STEP"
for REQUIRED_FRAGMENT in \
  'post_status pending' \
  'post_status failure' \
  'post_status success' \
  'trap finish_push EXIT'; do
  grep -q "$REQUIRED_FRAGMENT" "$PUSH_STEP" ||
    fail "The new-tag push lacks safe status transition: $REQUIRED_FRAGMENT"
done
PENDING_LINE=$(grep -n 'post_status pending' "$PUSH_STEP" | cut -d: -f1)
PUSH_LINE=$(grep -n 'git push origin' "$PUSH_STEP" | cut -d: -f1)
SUCCESS_LINE=$(grep -n 'post_status success' "$PUSH_STEP" | cut -d: -f1)
if ((PENDING_LINE >= PUSH_LINE || PUSH_LINE >= SUCCESS_LINE)); then
  fail "New-tag authorization must transition pending, push, then success."
fi

echo "Release workflow permission-separation checks passed."
