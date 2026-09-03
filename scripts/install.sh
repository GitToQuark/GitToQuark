#!/usr/bin/env bash
# GitToQuark environment check — verifies Node.js and the bundled Quark CLI wrapper.
# This script NEVER downloads files and NEVER modifies SKILL.md / references/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ENTRY="$SCRIPT_DIR/quark-drive.cjs"
REQUIRED_NODE_MAJOR=16

info()  { printf "[info]  %s\n" "$*"; }
warn()  { printf "[warn]  %s\n" "$*"; }
error() { printf "[error] %s\n" "$*"; }

echo "=== GitToQuark environment check ==="
echo ""

# 1. Node.js
if ! command -v node &>/dev/null; then
  error "Node.js not found. Please install Node.js v${REQUIRED_NODE_MAJOR}+: https://nodejs.org/"
  exit 1
fi
node_version="$(node --version)"
major_version="$(echo "$node_version" | sed 's/v//' | cut -d. -f1)"
info "Node.js: $node_version"
if [ "$major_version" -lt "$REQUIRED_NODE_MAJOR" ]; then
  error "Node.js $node_version is below v${REQUIRED_NODE_MAJOR}. Please upgrade."
  exit 1
fi

# On Windows (MSYS/Git Bash) node needs a Windows-style path, not /c/...
if command -v cygpath >/dev/null 2>&1; then
  CLI_ENTRY="$(cygpath -w "$CLI_ENTRY")"
fi

# 2. Bundled wrapper
if [ ! -f "$CLI_ENTRY" ]; then
  error "CLI entry missing: $CLI_ENTRY"
  error "The Quark CLI wrapper (scripts/quark-drive.cjs) must ship with this skill."
  error "Reinstall the GitToQuark skill if it is missing."
  exit 1
fi
info "Wrapper present: $CLI_ENTRY"

# 3. CLI self-check
if version_output="$(node "$CLI_ENTRY" --version 2>&1)"; then
  info "CLI OK, version: $version_output"
else
  error "node scripts/quark-drive.cjs --version failed: $version_output"
  exit 1
fi

echo ""
printf "✅ Environment ready. Run: node scripts/quark-drive.cjs --help\n"
