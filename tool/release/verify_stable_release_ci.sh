#!/usr/bin/env bash
set -euo pipefail

PACKAGE="${1:-}"
RELEASE_SHA="${2:-}"

if [[ "$PACKAGE" != "mcp_dart" && "$PACKAGE" != "mcp_dart_cli" ]]; then
  echo "Usage: $0 <mcp_dart|mcp_dart_cli> <release-sha>" >&2
  exit 64
fi
if [[ ! "$RELEASE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Release SHA must be a full 40-character commit SHA." >&2
  exit 64
fi

if [[ -n "${RELEASE_WORKFLOW_RUNS_FILE:-}" ]]; then
  if [[ ! -r "$RELEASE_WORKFLOW_RUNS_FILE" ]]; then
    echo "Workflow-runs fixture is not readable: $RELEASE_WORKFLOW_RUNS_FILE" >&2
    exit 66
  fi
  RUNS=$(<"$RELEASE_WORKFLOW_RUNS_FILE")
else
  : "${GH_TOKEN:?GH_TOKEN is required}"
  : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
  RUNS=$(gh api \
    -H "Accept: application/vnd.github+json" \
    "/repos/$GITHUB_REPOSITORY/actions/runs?head_sha=$RELEASE_SHA&per_page=100")
fi

REQUIRED_WORKFLOWS=(
  ".github/workflows/test_core.yml|Core tests"
  ".github/workflows/test_cli.yml|CLI tests"
)
if [[ "$PACKAGE" == "mcp_dart" ]]; then
  REQUIRED_WORKFLOWS+=(
    ".github/workflows/interop_2026_07_28.yml|MCP 2026-07-28 interop"
  )
fi

for WORKFLOW_ENTRY in "${REQUIRED_WORKFLOWS[@]}"; do
  IFS='|' read -r WORKFLOW_PATH WORKFLOW_LABEL <<<"$WORKFLOW_ENTRY"
  if ! jq -e \
    --arg workflow_path "$WORKFLOW_PATH" \
    --arg release_sha "$RELEASE_SHA" '
    .workflow_runs
    | any(
        .path == $workflow_path and
        .head_sha == $release_sha and
        .event == "push" and
        .status == "completed" and
        .conclusion == "success"
      )
  ' <<<"$RUNS" >/dev/null; then
    echo "❌ $WORKFLOW_LABEL ($WORKFLOW_PATH) has not succeeded for $RELEASE_SHA on push."
    exit 1
  fi
  echo "✅ $WORKFLOW_LABEL ($WORKFLOW_PATH) succeeded for $RELEASE_SHA."
done
