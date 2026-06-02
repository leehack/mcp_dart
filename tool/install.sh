#!/usr/bin/env sh
set -eu

repo="${MCP_DART_REPO:-leehack/mcp_dart}"
version="${MCP_DART_VERSION:-latest}"
install_dir="${MCP_DART_INSTALL_DIR:-"$HOME/.local/bin"}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "mcp_dart installer requires $1" >&2
    exit 1
  fi
}

detect_platform() {
  case "$(uname -s)" in
    Linux) echo "linux" ;;
    Darwin) echo "macos" ;;
    *)
      echo "Unsupported OS: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo "x64" ;;
    arm64 | aarch64) echo "arm64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

latest_cli_tag() {
  curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=50" |
    awk '
      function reset_release() {
        tag = ""
        prerelease = ""
        seen_tag = 0
        seen_prerelease = 0
      }
      function maybe_print() {
        if (seen_tag && seen_prerelease && tag ~ /^mcp_dart_cli-v/ && prerelease == "false") {
          print tag
          exit
        }
      }
      /^[[:space:]]*\{[[:space:]]*$/ && depth == 0 {
        reset_release()
      }
      /"tag_name":/ {
        tag = $0
        sub(/.*"tag_name": *"/, "", tag)
        sub(/".*/, "", tag)
        seen_tag = 1
        maybe_print()
      }
      /"prerelease":/ {
        prerelease = $0
        sub(/.*"prerelease": */, "", prerelease)
        sub(/[ ,].*/, "", prerelease)
        seen_prerelease = 1
        maybe_print()
      }
      {
        line = $0
        opens = gsub(/\{/, "{", line)
        line = $0
        closes = gsub(/\}/, "}", line)
        depth += opens - closes
      }
    '
}

require curl
require uname
require awk

platform="$(detect_platform)"
arch="$(detect_arch)"

case "$platform-$arch" in
  linux-x64 | macos-x64 | macos-arm64) ;;
  *)
    echo "No standalone mcp_dart binary is published for $platform-$arch." >&2
    exit 1
    ;;
esac

if [ "$version" = "latest" ]; then
  tag="$(latest_cli_tag)"
else
  case "$version" in
    mcp_dart_cli-v*) tag="$version" ;;
    *) tag="mcp_dart_cli-v$version" ;;
  esac
fi

if [ -z "${tag:-}" ]; then
  echo "Could not find a mcp_dart_cli GitHub release." >&2
  exit 1
fi

asset="mcp_dart-$platform-$arch"
url="https://github.com/$repo/releases/download/$tag/$asset"
skill_asset="mcp-developer.SKILL.md"
skill_url="https://github.com/$repo/releases/download/$tag/$skill_asset"
tmp="${TMPDIR:-/tmp}/mcp_dart.$$"
trap 'rm -f "$tmp"' EXIT INT TERM

echo "Downloading $url"
curl -fL "$url" -o "$tmp"
chmod 755 "$tmp"
mkdir -p "$install_dir"
mv "$tmp" "$install_dir/mcp_dart"

share_dir="$(dirname "$install_dir")/share/mcp_dart/skills/mcp-developer"
mkdir -p "$share_dir"
echo "Downloading $skill_url"
curl -fL "$skill_url" -o "$share_dir/SKILL.md"

echo "Installed $install_dir/mcp_dart"
echo "Run: $install_dir/mcp_dart --version"
