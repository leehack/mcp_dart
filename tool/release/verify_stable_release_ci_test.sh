#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
VERIFY_SCRIPT="$REPO_ROOT/tool/release/verify_stable_release_ci.sh"
RELEASE_SHA=1111111111111111111111111111111111111111
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/success.json" <<JSON
{
  "workflow_runs": [
    {
      "name": "A renamed core workflow",
      "path": ".github/workflows/test_core.yml",
      "head_sha": "$RELEASE_SHA",
      "event": "push",
      "status": "completed",
      "conclusion": "success"
    },
    {
      "name": "A renamed CLI workflow",
      "path": ".github/workflows/test_cli.yml",
      "head_sha": "$RELEASE_SHA",
      "event": "push",
      "status": "completed",
      "conclusion": "success"
    },
    {
      "name": "A renamed interop workflow",
      "path": ".github/workflows/interop_2026_07_28.yml",
      "head_sha": "$RELEASE_SHA",
      "event": "push",
      "status": "completed",
      "conclusion": "success"
    }
  ]
}
JSON

RELEASE_WORKFLOW_RUNS_FILE="$FIXTURE_DIR/success.json" \
  bash "$VERIFY_SCRIPT" mcp_dart "$RELEASE_SHA" >/dev/null

cat >"$FIXTURE_DIR/display-name-decoys.json" <<JSON
{
  "workflow_runs": [
    {
      "name": "Run Core Tests on PR",
      "path": ".github/workflows/display_name_decoy.yml",
      "head_sha": "$RELEASE_SHA",
      "event": "push",
      "status": "completed",
      "conclusion": "success"
    },
    {
      "name": "Run CLI Tests on PR",
      "path": ".github/workflows/display_name_decoy.yml",
      "head_sha": "$RELEASE_SHA",
      "event": "push",
      "status": "completed",
      "conclusion": "success"
    },
    {
      "name": "Run MCP 2026-07-28 Interop",
      "path": ".github/workflows/display_name_decoy.yml",
      "head_sha": "$RELEASE_SHA",
      "event": "push",
      "status": "completed",
      "conclusion": "success"
    }
  ]
}
JSON

if RELEASE_WORKFLOW_RUNS_FILE="$FIXTURE_DIR/display-name-decoys.json" \
  bash "$VERIFY_SCRIPT" mcp_dart "$RELEASE_SHA" >/dev/null 2>&1; then
  echo "Display-name decoys unexpectedly satisfied the workflow provenance gate." >&2
  exit 1
fi

echo "Stable release workflow provenance fixtures passed."
