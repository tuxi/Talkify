#!/bin/bash
#
# build-codeagentd.sh — compile codeagentd for macOS arm64
#
# Usage (standalone, when you need to build/update the daemon binary):
#   ./scripts/build-codeagentd.sh [version]
#
# This script is NOT called during Xcode builds. The Xcode Build Phase
# in project.pbxproj simply copies a pre-built binary from build/codeagentd
# into the app bundle. Run this script separately whenever codeagentd
# needs to be updated.
#
# Output: build/codeagentd (Mach-O 64-bit executable arm64)

set -euo pipefail

# Common Go installation paths
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"

VERSION="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CODE_AGENT_DIR="${ROOT}/../code-agent"
OUTPUT="${ROOT}/build/codeagentd"

if [ ! -d "${CODE_AGENT_DIR}" ]; then
    echo "error: code-agent repository not found at ${CODE_AGENT_DIR}" >&2
    echo "  expected ../code-agent relative to the chater workspace" >&2
    exit 1
fi

mkdir -p "${ROOT}/build"

if ! command -v go &>/dev/null; then
    echo "error: go not found on PATH" >&2
    echo "  install from https://go.dev/dl/ or via 'brew install go'" >&2
    exit 1
fi

cd "${CODE_AGENT_DIR}"

echo "==> Building codeagentd for macOS arm64 (version: ${VERSION})"
GOOS=darwin GOARCH=arm64 go build \
    -ldflags="-s -w -X code-agent/internal/buildinfo.Version=${VERSION} -extldflags '-Wl,-no_fixup_chains,-pagezero_size,0x1000,-image_base,0x100000000' -linkmode=external" \
    -o "${OUTPUT}" \
    ./cmd/codeagentd

echo "==> Built: ${OUTPUT}"
file "${OUTPUT}"
ls -lh "${OUTPUT}"
echo ""
echo "Done. The Xcode Build Phase will copy this binary into the app bundle."
