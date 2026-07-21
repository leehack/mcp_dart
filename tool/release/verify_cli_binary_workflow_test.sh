#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORKFLOW="$REPO_ROOT/.github/workflows/cli_binaries.yml"
HELPER="$REPO_ROOT/tool/release/verify_cli_published_sdk.sh"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

BUILD_JOB="$FIXTURE_DIR/build-job.yml"
ASSET_JOB="$FIXTURE_DIR/asset-job.yml"
sed -n '/^  build:/,/^  release-assets:/p' "$WORKFLOW" >"$BUILD_JOB"
sed -n '/^  release-assets:/,$p' "$WORKFLOW" >"$ASSET_JOB"

fail() {
  echo "$1" >&2
  exit 1
}

grep -A1 '^permissions:$' "$WORKFLOW" | grep -q '^  contents: read$' ||
  fail "CLI binary workflow must default to read-only repository access."
if grep -q 'contents: write' "$BUILD_JOB"; then
  fail "CLI binary build jobs unexpectedly have repository write access."
fi
grep -q '^      contents: write$' "$ASSET_JOB" ||
  fail "CLI binary asset attachment is missing repository write access."
grep -q '^      statuses: read$' "$ASSET_JOB" ||
  fail "CLI binary asset attachment cannot read release authorization status."
if [[ $(grep -c 'persist-credentials: false' "$WORKFLOW") -ne 2 ]]; then
  fail "Both CLI binary workflow checkouts must disable persisted credentials."
fi

AUTHORIZATION_LINE=$(grep -n 'Verify authorized existing release' "$ASSET_JOB" |
  cut -d: -f1)
UPLOAD_LINE=$(grep -n '^[[:space:]]*gh release upload ' "$ASSET_JOB" |
  cut -d: -f1)
[[ -n "$AUTHORIZATION_LINE" && -n "$UPLOAD_LINE" ]] ||
  fail "CLI binary assets must verify authorization before uploading."
if ((AUTHORIZATION_LINE >= UPLOAD_LINE)); then
  fail "CLI binary release authorization must precede asset upload."
fi
grep -Fq 'mcp_dart/release/mcp_dart_cli' "$ASSET_JOB" ||
  fail "CLI binary assets must require the CLI exact-commit release context."
grep -Fq "/commits/\$TAG_COMMIT/status" "$ASSET_JOB" ||
  fail "CLI binary assets must inspect authorization on the exact tag commit."
grep -Fq "/releases/tags/\$RELEASE_TAG" "$ASSET_JOB" ||
  fail "CLI binary assets must require an existing GitHub release."
grep -q 'RELEASE_LOOKUP_ATTEMPTS' "$ASSET_JOB" ||
  fail "CLI binary assets must tolerate the release-creation ordering window."
grep -Fq ".prerelease == \$prerelease" "$ASSET_JOB" ||
  fail "CLI binary assets must verify stable/prerelease classification."
if grep -q 'softprops/action-gh-release' "$ASSET_JOB"; then
  fail "CLI binary assets must not use an action that can create a release."
fi

REMOVE_OVERRIDE_LINE=$(grep -n 'rm -f pubspec_overrides.yaml' "$BUILD_JOB" |
  cut -d: -f1)
VERIFY_HOSTED_LINE=$(grep -n 'verify_cli_published_sdk.sh' "$BUILD_JOB" |
  cut -d: -f1)
[[ -n "$REMOVE_OVERRIDE_LINE" && -n "$VERIFY_HOSTED_LINE" ]] ||
  fail "CLI binary builds must remove the override and invoke the hosted SDK verifier."
if ((REMOVE_OVERRIDE_LINE >= VERIFY_HOSTED_LINE)); then
  fail "CLI binary builds must remove the override before hosted SDK verification."
fi
grep -q -- '--resolution-only' "$BUILD_JOB" ||
  fail "CLI binary builds must use the dependency-only hosted SDK verifier."
if grep -q 'dart pub get' "$BUILD_JOB"; then
  fail "CLI binary builds must not bypass hosted SDK verification with dart pub get."
fi

CLI_FIXTURE="$FIXTURE_DIR/cli"
mkdir -p "$CLI_FIXTURE/bin" "$FIXTURE_DIR/bin"
touch "$CLI_FIXTURE/bin/mcp_dart.dart"
cat >"$CLI_FIXTURE/pubspec.yaml" <<'YAML'
name: cli_fixture
version: 0.0.0
environment:
  sdk: ^3.12.0
dependencies:
  mcp_dart: ^2.3.0
YAML
cat >"$FIXTURE_DIR/bin/dart" <<'DART'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "pub downgrade" ]]; then
  exit 0
fi
if [[ "$*" == "pub deps --json" ]]; then
  cat "$DART_DEPS_FIXTURE"
  exit 0
fi
echo "Unexpected dart fixture command: $*" >&2
exit 2
DART
chmod +x "$FIXTURE_DIR/bin/dart"

cat >"$FIXTURE_DIR/hosted.json" <<'JSON'
{"packages":[{"name":"mcp_dart","version":"2.3.0","source":"hosted"}]}
JSON
cat >"$FIXTURE_DIR/path.json" <<'JSON'
{"packages":[{"name":"mcp_dart","version":"2.3.0","source":"path"}]}
JSON
cat >"$FIXTURE_DIR/newer.json" <<'JSON'
{"packages":[{"name":"mcp_dart","version":"2.3.1","source":"hosted"}]}
JSON

run_helper() {
  local dependency_fixture=$1
  (
    cd "$CLI_FIXTURE"
    PATH="$FIXTURE_DIR/bin:$PATH" \
      DART_DEPS_FIXTURE="$dependency_fixture" \
      bash "$HELPER" --resolution-only
  )
}

run_helper "$FIXTURE_DIR/hosted.json" >/dev/null ||
  fail "The hosted minimum SDK fixture should pass."
if run_helper "$FIXTURE_DIR/path.json" >"$FIXTURE_DIR/path.out" 2>&1; then
  fail "A workspace/path SDK unexpectedly passed hosted dependency verification."
fi
grep -q 'Expected hosted mcp_dart 2.3.0' "$FIXTURE_DIR/path.out" ||
  fail "The path SDK fixture did not fail for hosted-source mismatch."
if run_helper "$FIXTURE_DIR/newer.json" >"$FIXTURE_DIR/newer.out" 2>&1; then
  fail "A newer caret-compatible SDK unexpectedly passed minimum verification."
fi
grep -q 'Expected hosted mcp_dart 2.3.0' "$FIXTURE_DIR/newer.out" ||
  fail "The newer SDK fixture did not fail for exact-version mismatch."

touch "$CLI_FIXTURE/pubspec_overrides.yaml"
if run_helper "$FIXTURE_DIR/hosted.json" >"$FIXTURE_DIR/override.out" 2>&1; then
  fail "A CLI candidate containing pubspec_overrides.yaml unexpectedly passed."
fi
grep -q 'still contains pubspec_overrides.yaml' "$FIXTURE_DIR/override.out" ||
  fail "The override fixture did not fail before dependency resolution."

echo "CLI binary workflow dependency-isolation checks passed."
