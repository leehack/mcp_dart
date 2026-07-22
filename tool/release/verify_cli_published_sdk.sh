#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-full}"
if [[ "$MODE" != "full" && "$MODE" != "--resolution-only" ]]; then
  echo "Usage: $0 [--resolution-only]" >&2
  exit 64
fi

if [[ ! -f pubspec.yaml || ! -f bin/mcp_dart.dart ]]; then
  echo "Run this check from the mcp_dart_cli package directory." >&2
  exit 64
fi
if [[ -e pubspec_overrides.yaml ]]; then
  echo "Release candidate still contains pubspec_overrides.yaml." >&2
  exit 65
fi

SDK_CONSTRAINT=$(awk '$1 == "mcp_dart:" { print $2; exit }' pubspec.yaml)
case "$SDK_CONSTRAINT" in
  ^*) EXPECTED_SDK_VERSION="${SDK_CONSTRAINT#^}" ;;
  *)
    echo "Expected the mcp_dart dependency to use a caret constraint." >&2
    exit 65
    ;;
esac
if [[ -z "$EXPECTED_SDK_VERSION" ]]; then
  echo "Could not determine the minimum mcp_dart version." >&2
  exit 65
fi
if [[ ! "$EXPECTED_SDK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
  echo "Invalid minimum mcp_dart version: $EXPECTED_SDK_VERSION." >&2
  exit 65
fi

# Exercise only the lower bound of the declared hosted SDK constraint. A
# package-wide `pub downgrade` can select transitive versions that predate the
# CLI's Dart SDK and fail for reasons unrelated to mcp_dart compatibility.
cleanup() {
  rm -f pubspec_overrides.yaml
}
trap cleanup EXIT
printf 'dependency_overrides:\n  mcp_dart: %s\n' \
  "$EXPECTED_SDK_VERSION" >pubspec_overrides.yaml
dart pub get
DEPENDENCIES=$(dart pub deps --json)
RESOLVED_SDK_VERSION=$(jq -r '
  [.packages[] | select(.name == "mcp_dart")][0].version // empty
' <<<"$DEPENDENCIES")
RESOLVED_SDK_SOURCE=$(jq -r '
  [.packages[] | select(.name == "mcp_dart")][0].source // empty
' <<<"$DEPENDENCIES")
if [[ "$RESOLVED_SDK_VERSION" != "$EXPECTED_SDK_VERSION" ||
      "$RESOLVED_SDK_SOURCE" != "hosted" ]]; then
  echo "Expected hosted mcp_dart $EXPECTED_SDK_VERSION, resolved" \
    "$RESOLVED_SDK_SOURCE mcp_dart $RESOLVED_SDK_VERSION." >&2
  exit 65
fi
echo "Resolved minimum hosted mcp_dart $RESOLVED_SDK_VERSION."

if [[ "$MODE" == "--resolution-only" ]]; then
  exit 0
fi

dart analyze
dart test --exclude-tags e2e
mkdir -p .dart_tool/release-check
dart compile exe bin/mcp_dart.dart -o .dart_tool/release-check/mcp_dart
.dart_tool/release-check/mcp_dart --version
