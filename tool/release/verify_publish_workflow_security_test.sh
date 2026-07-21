#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORKFLOW="$REPO_ROOT/.github/workflows/publish.yml"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

VALIDATION_JOB="$FIXTURE_DIR/validation-job.yml"
PUBLISH_JOB="$FIXTURE_DIR/publish-job.yml"
AUTHORIZATION_STEP="$FIXTURE_DIR/authorization-step.yml"
AUTHORIZATION_SCRIPT="$FIXTURE_DIR/authorize.sh"

sed -n '/^  validate_candidate:/,/^  publish:/p' "$WORKFLOW" >"$VALIDATION_JOB"
sed -n '/^  publish:/,$p' "$WORKFLOW" >"$PUBLISH_JOB"
sed -n \
  '/^      - name: Verify exact release source authorization$/,/^      - /p' \
  "$WORKFLOW" >"$AUTHORIZATION_STEP"
awk '
  /^      - name: Verify exact release source authorization$/ {
    in_step = 1
    next
  }
  in_step && /^        run: \|$/ {
    in_run = 1
    next
  }
  in_run && /^      - / {
    exit
  }
  in_run {
    sub(/^          /, "")
    print
  }
' "$WORKFLOW" >"$AUTHORIZATION_SCRIPT"

fail() {
  echo "$1" >&2
  exit 1
}

grep -q '^  validate_candidate:$' "$VALIDATION_JOB" ||
  fail "The no-OIDC publish validation job is missing."
grep -q '^  publish:$' "$PUBLISH_JOB" ||
  fail "The minimal OIDC publish job is missing."
grep -q '      statuses: read$' "$VALIDATION_JOB" ||
  fail "Publish validation cannot read exact-commit authorization statuses."
if grep -q 'id-token: write' "$VALIDATION_JOB"; then
  fail "Repository validation unexpectedly has an OIDC credential."
fi

grep -q '      actions: read$' "$PUBLISH_JOB" ||
  fail "The OIDC job cannot download the validated candidate."
grep -q '      id-token: write' "$PUBLISH_JOB" ||
  fail "The final publish job is missing its pub.dev OIDC permission."
if grep -qE 'contents:|statuses:|actions/checkout@|github\.token|GH_TOKEN' \
  "$PUBLISH_JOB"; then
  fail "The OIDC job unexpectedly has repository access."
fi
if grep -qE 'dart (run|test|analyze|compile)|dart pub get|bash |tool/' \
  "$PUBLISH_JOB"; then
  fail "The OIDC job unexpectedly executes repository or dependency scripts."
fi
if [[ $(grep -c 'run: dart pub publish --force$' "$PUBLISH_JOB") -ne 1 ]]; then
  fail "The OIDC job must perform exactly one final pub publish invocation."
fi

AUTHORIZATION_LINE=$(grep -n \
  -- '- name: Verify exact release source authorization' "$VALIDATION_JOB" |
  cut -d: -f1)
CHECKOUT_LINE=$(grep -n -- 'uses: actions/checkout@' "$VALIDATION_JOB" |
  cut -d: -f1)
[[ -n "$AUTHORIZATION_LINE" && -n "$CHECKOUT_LINE" ]] ||
  fail "The authorization or checkout step is missing."
if ((AUTHORIZATION_LINE >= CHECKOUT_LINE)); then
  fail "Exact-source authorization must run before repository checkout."
fi
if sed -n "1,${AUTHORIZATION_LINE}p" "$VALIDATION_JOB" |
  grep -qE '^      - uses:|^        uses:'; then
  fail "A third-party action runs before exact-source authorization."
fi
if grep -q '^        if:' "$AUTHORIZATION_STEP"; then
  fail "Prereleases must not bypass exact-source authorization."
fi
grep -q 'persist-credentials: false' "$VALIDATION_JOB" ||
  fail "Publish validation checkout must not persist credentials."

grep -qE 'actions/upload-artifact@[0-9a-f]{40} ' "$VALIDATION_JOB" ||
  fail "The candidate upload action must be pinned to a commit SHA."
grep -qE 'actions/download-artifact@[0-9a-f]{40} ' "$PUBLISH_JOB" ||
  fail "The candidate download action must be pinned to a commit SHA."
grep -q 'sha256sum --check --strict' "$PUBLISH_JOB" ||
  fail "The OIDC job must verify the immutable candidate digest."
grep -q 'needs: validate_candidate' "$PUBLISH_JOB" ||
  fail "The OIDC job must depend on successful candidate validation."

CANDIDATE_LINE=$(grep -n -- '- name: Build immutable publish candidate' \
  "$VALIDATION_JOB" | cut -d: -f1)
UPLOAD_LINE=$(grep -n -- '- name: Upload immutable publish candidate' \
  "$VALIDATION_JOB" | cut -d: -f1)
SETUP_DART_LINE=$(grep -n -- 'uses: dart-lang/setup-dart@' \
  "$VALIDATION_JOB" | cut -d: -f1)
DEPENDENCIES_LINE=$(grep -n -- '- name: Install validation dependencies' \
  "$VALIDATION_JOB" | cut -d: -f1)
[[ -n "$CANDIDATE_LINE" && -n "$UPLOAD_LINE" &&
  -n "$SETUP_DART_LINE" && -n "$DEPENDENCIES_LINE" ]] ||
  fail "The candidate construction or validation sequence is incomplete."
if ((CANDIDATE_LINE >= UPLOAD_LINE ||
  UPLOAD_LINE >= SETUP_DART_LINE ||
  UPLOAD_LINE >= DEPENDENCIES_LINE)); then
  fail "The immutable candidate must be built and uploaded before dependency code."
fi
if grep -q -- '--exclude-from=' "$VALIDATION_JOB"; then
  fail "rsync must not reinterpret Dart .pubignore rules."
fi
grep -q -- '- name: Extract immutable candidate for validation' \
  "$VALIDATION_JOB" ||
  fail "Validation must use a fresh extraction of the immutable candidate."
# Match the literal GitHub expression.
# shellcheck disable=SC2016
grep -Fq 'working-directory: ${{ steps.validation-dir.outputs.working_directory }}' \
  "$VALIDATION_JOB" ||
  fail "Dependency and publish validation must run against the extracted candidate."

# Match the literal shell variable in workflow code.
# shellcheck disable=SC2016
grep -q 'mcp_dart/release/\$PACKAGE' "$AUTHORIZATION_SCRIPT" ||
  fail "The authorization script does not require the package release context."
grep -q 'GITHUB_REF_NAME' "$AUTHORIZATION_SCRIPT" ||
  fail "The authorization script does not resolve the pushed tag."

mkdir -p "$FIXTURE_DIR/bin"
cat >"$FIXTURE_DIR/bin/gh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail

ENDPOINT=
JQ_FILTER=
while (($#)); do
  case "$1" in
    /repos/*)
      ENDPOINT=$1
      ;;
    --jq)
      shift
      JQ_FILTER=${1:-}
      ;;
  esac
  shift
done

case "$ENDPOINT" in
  */status)
    if [[ -n "${STATUS_FIXTURE_SECOND:-}" ]]; then
      CALLS=0
      if [[ -f "$STATUS_CALLS_FILE" ]]; then
        CALLS=$(<"$STATUS_CALLS_FILE")
      fi
      CALLS=$((CALLS + 1))
      echo "$CALLS" >"$STATUS_CALLS_FILE"
      if ((CALLS > 1)); then
        cat "$STATUS_FIXTURE_SECOND"
      else
        cat "$STATUS_FIXTURE"
      fi
    else
      cat "$STATUS_FIXTURE"
    fi
    ;;
  */commits/*)
    if [[ "$JQ_FILTER" != '.sha' ]]; then
      echo "Unexpected gh fixture jq filter: $JQ_FILTER" >&2
      exit 2
    fi
    echo "$FIXTURE_SHA"
    ;;
  *)
    echo "Unexpected gh fixture endpoint: $ENDPOINT" >&2
    exit 2
    ;;
esac
FIXTURE
chmod +x "$FIXTURE_DIR/bin/gh" "$AUTHORIZATION_SCRIPT"

RELEASE_SHA=1111111111111111111111111111111111111111
cat >"$FIXTURE_DIR/unauthorized.json" <<'JSON'
{
  "state": "failure",
  "statuses": [
    {
      "id": 10,
      "context": "mcp_dart/release/mcp_dart",
      "state": "success"
    },
    {
      "id": 11,
      "context": "mcp_dart/release/mcp_dart",
      "state": "failure"
    }
  ]
}
JSON

run_authorization_fixture() {
  local status_fixture=$1
  local status_fixture_second=${2:-}
  local attempts=${3:-1}
  PATH="$FIXTURE_DIR/bin:$PATH" \
    FIXTURE_SHA="$RELEASE_SHA" \
    STATUS_FIXTURE="$status_fixture" \
    STATUS_FIXTURE_SECOND="$status_fixture_second" \
    STATUS_CALLS_FILE="$FIXTURE_DIR/status-calls" \
    GITHUB_REPOSITORY=example/mcp_dart \
    GITHUB_REF_NAME=v2.3.0-dev.3 \
    GITHUB_OUTPUT="$FIXTURE_DIR/github-output" \
    PACKAGE=mcp_dart \
    PUBLISH_AUTHORIZATION_ATTEMPTS="$attempts" \
    PUBLISH_AUTHORIZATION_INTERVAL_SECONDS=0 \
    bash "$AUTHORIZATION_SCRIPT"
}

if run_authorization_fixture "$FIXTURE_DIR/unauthorized.json" \
  >"$FIXTURE_DIR/unauthorized.out" 2>&1; then
  fail "An unauthorized prerelease tag unexpectedly passed provenance validation."
fi
grep -q 'has mcp_dart/release/mcp_dart state failure' \
  "$FIXTURE_DIR/unauthorized.out" ||
  fail "The unauthorized prerelease fixture did not fail for provenance."

cat >"$FIXTURE_DIR/authorized.json" <<'JSON'
{
  "state": "success",
  "statuses": [
    {
      "id": 20,
      "context": "mcp_dart/release/mcp_dart",
      "state": "failure"
    },
    {
      "id": 21,
      "context": "mcp_dart/release/mcp_dart",
      "state": "success"
    }
  ]
}
JSON
rm -f "$FIXTURE_DIR/github-output"
run_authorization_fixture "$FIXTURE_DIR/authorized.json" >/dev/null
grep -q "^release_sha=$RELEASE_SHA$" "$FIXTURE_DIR/github-output" ||
  fail "An authorized prerelease did not preserve its exact commit SHA."

cat >"$FIXTURE_DIR/pending.json" <<'JSON'
{
  "state": "pending",
  "statuses": [
    {
      "id": 30,
      "context": "mcp_dart/release/mcp_dart",
      "state": "pending"
    }
  ]
}
JSON
rm -f "$FIXTURE_DIR/github-output" "$FIXTURE_DIR/status-calls"
run_authorization_fixture \
  "$FIXTURE_DIR/pending.json" "$FIXTURE_DIR/authorized.json" 3 >/dev/null
grep -q '^2$' "$FIXTURE_DIR/status-calls" ||
  fail "The authorization gate did not poll pending provenance to success."
grep -q "^release_sha=$RELEASE_SHA$" "$FIXTURE_DIR/github-output" ||
  fail "Pending-to-success authorization lost the exact commit SHA."

echo "Publish workflow permission and provenance fixtures passed."
