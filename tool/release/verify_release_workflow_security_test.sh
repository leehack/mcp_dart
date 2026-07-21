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
# Match the literal shell variable in workflow code.
# shellcheck disable=SC2016
grep -Fq 'packages/mcp_dart_cli/ "$PUBLISH_ROOT/"' "$VALIDATION_JOB" ||
  fail "CLI release staging must copy only the nested package."
grep -q -- '--exclude pubspec_overrides.yaml' "$VALIDATION_JOB" ||
  fail "CLI release staging must remove its monorepo SDK override."
grep -q '      contents: write' "$WRITE_JOB" ||
  fail "The release write job cannot create tags or releases."
grep -q '      statuses: write$' "$WRITE_JOB" ||
  fail "The release write job cannot authorize the exact commit."

if [[ $(grep -c 'persist-credentials: false' "$WORKFLOW") -ne 2 ]]; then
  fail "Both release checkouts must disable persisted credentials."
fi
if [[ $(grep -c 'RELEASE_PAT:' "$WORKFLOW") -ne 1 ]]; then
  fail "RELEASE_PAT must be exposed only to the new-tag push step."
fi
# Match the literal GitHub expression.
# shellcheck disable=SC2016
if grep -Fq '${{ needs.validate-release.outputs' "$WRITE_RUN_SCRIPTS"; then
  fail "Validated repository values must enter privileged scripts through env."
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
