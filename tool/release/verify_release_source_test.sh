#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
VERIFY_SCRIPT="$REPO_ROOT/tool/release/verify_release_source.sh"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

REMOTE="$FIXTURE_DIR/remote.git"
CANDIDATE="$FIXTURE_DIR/candidate"
UPDATER="$FIXTURE_DIR/updater"

git init --quiet --bare "$REMOTE"
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main
git init --quiet --initial-branch=main "$CANDIDATE"
git -C "$CANDIDATE" config user.name "Release fixture"
git -C "$CANDIDATE" config user.email "release-fixture@example.invalid"
git -C "$CANDIDATE" commit --quiet --allow-empty -m "Candidate"
git -C "$CANDIDATE" remote add origin "$REMOTE"
git -C "$CANDIDATE" push --quiet --set-upstream origin main

run_gate() {
  (
    cd "$CANDIDATE"
    GITHUB_REF_TYPE=branch \
      GITHUB_REF_NAME=main \
      RELEASE_SOURCE_REMOTE=origin \
      bash "$VERIFY_SCRIPT" main "$1"
  )
}

run_gate v2.3.0 >/dev/null

git clone --quiet "$REMOTE" "$UPDATER"
git -C "$UPDATER" config user.name "Release fixture"
git -C "$UPDATER" config user.email "release-fixture@example.invalid"
git -C "$UPDATER" commit --quiet --allow-empty -m "Advance default branch"
git -C "$UPDATER" push --quiet origin main

if run_gate v2.3.0 >/dev/null 2>&1; then
  echo "A stale untagged candidate unexpectedly passed the source gate." >&2
  exit 1
fi

git -C "$CANDIDATE" tag -a v2.3.0 -m "Recovery tag"
git -C "$CANDIDATE" push --quiet origin v2.3.0
run_gate v2.3.0 >/dev/null

git -C "$UPDATER" tag -a v2.4.0 -m "Different release tag"
git -C "$UPDATER" push --quiet origin v2.4.0
if run_gate v2.4.0 >/dev/null 2>&1; then
  echo "A candidate that did not match the existing tag unexpectedly passed." >&2
  exit 1
fi

if (
  cd "$CANDIDATE"
  GITHUB_REF_TYPE=branch \
    GITHUB_REF_NAME=feature \
    RELEASE_SOURCE_REMOTE=origin \
    bash "$VERIFY_SCRIPT" main v2.3.0
) >/dev/null 2>&1; then
  echo "A release dispatched from a non-default branch unexpectedly passed." >&2
  exit 1
fi

echo "Release source fixtures passed."
