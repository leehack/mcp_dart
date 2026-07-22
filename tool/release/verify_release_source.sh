#!/usr/bin/env bash
set -euo pipefail

DEFAULT_BRANCH="${1:-}"
TAG="${2:-}"
REMOTE="${RELEASE_SOURCE_REMOTE:-origin}"

if [[ -z "$DEFAULT_BRANCH" || -z "$TAG" ]]; then
  echo "Usage: $0 <default-branch> <release-tag>" >&2
  exit 64
fi

if [[ "${GITHUB_REF_TYPE:-}" != "branch" ||
  "${GITHUB_REF_NAME:-}" != "$DEFAULT_BRANCH" ]]; then
  echo "❌ Releases must be dispatched from $DEFAULT_BRANCH." >&2
  exit 1
fi

HEAD_SHA=$(git rev-parse HEAD)
DEFAULT_SHA=$(git ls-remote "$REMOTE" "refs/heads/$DEFAULT_BRANCH" |
  awk 'NR == 1 { print $1 }')
if [[ -z "$DEFAULT_SHA" ]]; then
  echo "❌ Could not resolve $REMOTE/$DEFAULT_BRANCH." >&2
  exit 1
fi

TAG_REF=$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG" |
  awk 'NR == 1 { print $1 }')
if [[ -n "$TAG_REF" ]]; then
  git fetch --quiet --force "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"
  TAG_COMMIT=$(git rev-list -n 1 "$TAG")
  if [[ "$HEAD_SHA" != "$TAG_COMMIT" ]]; then
    echo "❌ Existing tag $TAG points to $TAG_COMMIT, not $HEAD_SHA." >&2
    echo "   Never move or recreate a published tag; bump the version instead." >&2
    exit 1
  fi
  echo "✅ Release recovery matches existing tag $TAG."
  exit 0
fi

if [[ "$HEAD_SHA" != "$DEFAULT_SHA" ]]; then
  echo "❌ Releases must use the latest $REMOTE/$DEFAULT_BRANCH commit." >&2
  exit 1
fi

echo "✅ Release source matches $REMOTE/$DEFAULT_BRANCH."
