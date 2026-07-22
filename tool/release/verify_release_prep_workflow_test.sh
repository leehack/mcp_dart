#!/usr/bin/env bash
set -euo pipefail

PREP_WORKFLOW=.github/workflows/release_prep.yml
MERGE_WORKFLOW=.github/workflows/release_on_prep_merge.yml
RELEASE_WORKFLOW=.github/workflows/release.yml

for WORKFLOW in "$PREP_WORKFLOW" "$MERGE_WORKFLOW" "$RELEASE_WORKFLOW"; do
  test -f "$WORKFLOW"
done

grep -q "contains(github.event.pull_request.labels.*.name, 'release-prep')" \
  "$PREP_WORKFLOW" || {
  echo 'Release prep validation must require the release-prep label.' >&2
  exit 1
}
grep -q 'BASE_BRANCH.*github.event.pull_request.base.ref' "$PREP_WORKFLOW" || {
  echo 'Release prep validation must inspect the PR base branch.' >&2
  exit 1
}
grep -q 'detect_release_prep.dart' "$PREP_WORKFLOW" || {
  echo 'Release prep validation must derive the plan from version changes.' >&2
  exit 1
}
grep -q -- '--package mcp_dart' "$PREP_WORKFLOW" || {
  echo 'Release prep validation must gate SDK metadata.' >&2
  exit 1
}
grep -q -- '--package mcp_dart_cli' "$PREP_WORKFLOW" || {
  echo 'Release prep validation must gate CLI metadata.' >&2
  exit 1
}

grep -q 'pull_request_target:' "$MERGE_WORKFLOW" || {
  echo 'Merged prep releases must use a trusted base workflow.' >&2
  exit 1
}
grep -q 'github.event.pull_request.merged == true' "$MERGE_WORKFLOW" || {
  echo 'The automatic release must require an actually merged PR.' >&2
  exit 1
}
grep -q 'github.event.pull_request.base.ref == github.event.repository.default_branch' \
  "$MERGE_WORKFLOW" || {
  echo 'The automatic release must only accept the default branch.' >&2
  exit 1
}
grep -q "contains(github.event.pull_request.labels.*.name, 'release-prep')" \
  "$MERGE_WORKFLOW" || {
  echo 'The automatic release must require the release-prep label.' >&2
  exit 1
}
if grep -q 'github.event.pull_request.head.sha' "$MERGE_WORKFLOW"; then
  echo 'The privileged merged-prep workflow must never check out a PR head.' >&2
  exit 1
fi
# Match literal GitHub expressions.
# shellcheck disable=SC2016
grep -q 'ref: \${{ github.event.pull_request.merge_commit_sha }}' \
  "$MERGE_WORKFLOW" || {
  echo 'The automatic release must check out the exact merge commit.' >&2
  exit 1
}
# shellcheck disable=SC2016
grep -q 'release_sha: \${{ needs.detect.outputs.release_sha }}' \
  "$MERGE_WORKFLOW" || {
  echo 'Every release call must receive the detected exact merge SHA.' >&2
  exit 1
}
if [ "$(grep -c '^      contents: write$' "$MERGE_WORKFLOW")" -ne 2 ] ||
  [ "$(grep -c '^      statuses: write$' "$MERGE_WORKFLOW")" -ne 2 ]; then
  echo 'Only the SDK and CLI release calls may request write permissions.' >&2
  exit 1
fi
if grep -q 'secrets: inherit' "$MERGE_WORKFLOW" ||
  [ "$(grep -c '^      RELEASE_PAT:.*secrets.RELEASE_PAT' "$MERGE_WORKFLOW")" -ne 2 ]; then
  echo 'Release calls must receive only the narrowly scoped tag-push secret.' >&2
  exit 1
fi
grep -q 'verify_release_ci.sh' "$MERGE_WORKFLOW" || {
  echo 'Automatic releases must wait for exact-commit push CI.' >&2
  exit 1
}
for VARIABLE in \
  RELEASE_CI_ATTEMPTS \
  RELEASE_CI_INTERVAL_SECONDS \
  RELEASE_PUB_ATTEMPTS \
  RELEASE_PUB_INTERVAL_SECONDS; do
  grep -q "$VARIABLE" "$MERGE_WORKFLOW" || {
    echo "Automatic release polling must support $VARIABLE." >&2
    exit 1
  }
done

SDK_RELEASE_LINE=$(grep -n '^  release-sdk:$' "$MERGE_WORKFLOW" | cut -d: -f1)
SDK_WAIT_LINE=$(grep -n '^  wait-for-sdk:$' "$MERGE_WORKFLOW" | cut -d: -f1)
CLI_RELEASE_LINE=$(grep -n '^  release-cli:$' "$MERGE_WORKFLOW" | cut -d: -f1)
if [ -z "$SDK_RELEASE_LINE" ] || [ -z "$SDK_WAIT_LINE" ] ||
  [ -z "$CLI_RELEASE_LINE" ] || [ "$SDK_RELEASE_LINE" -ge "$SDK_WAIT_LINE" ] ||
  [ "$SDK_WAIT_LINE" -ge "$CLI_RELEASE_LINE" ]; then
  echo 'Coordinated releases must publish SDK, wait for pub.dev, then release CLI.' >&2
  exit 1
fi
grep -q 'https://pub.dev/api/packages/mcp_dart' "$MERGE_WORKFLOW" || {
  echo 'Coordinated releases must verify SDK propagation on pub.dev.' >&2
  exit 1
}

grep -q '^  workflow_call:$' "$RELEASE_WORKFLOW" || {
  echo 'Create Release must remain callable by the prep-merge workflow.' >&2
  exit 1
}
# shellcheck disable=SC2016
grep -q 'ref: \${{ inputs.release_sha || github.sha }}' "$RELEASE_WORKFLOW" || {
  echo 'Create Release must validate the caller-selected exact commit.' >&2
  exit 1
}

echo 'Release prep workflow checks passed.'
