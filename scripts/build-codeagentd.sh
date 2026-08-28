#!/bin/bash
#
# build-codeagentd.sh — compile codeagentd as a macOS universal binary (arm64 + x86_64)
#
# Usage (standalone, when you need to build/update the daemon binary):
#   ./scripts/build-codeagentd.sh [version]
#
# This script is NOT called during Xcode builds. The Xcode Build Phase
# in project.pbxproj simply copies a pre-built binary from build/codeagentd
# into the app bundle. Run this script separately whenever codeagentd
# needs to be updated.
#
# Output: build/codeagentd (Mach-O universal binary: arm64 + x86_64)
#
# Works on both Apple Silicon and Intel Macs. The non-native slice is
# cross-compiled with CGO_ENABLED=1 and "clang -arch <target>"; this is
# required because -linkmode=external needs cgo, and Go disables cgo by
# default when cross-compiling.

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

echo "==> Building codeagentd for macOS universal (arm64 + x86_64) (version: ${VERSION})"

LDFLAGS_COMMON="-s -w -X code-agent/internal/buildinfo.Version=${VERSION} -linkmode=external"
LDFLAGS_ARM64="${LDFLAGS_COMMON} -extldflags '-Wl,-no_fixup_chains,-image_base,0x100000000'"
LDFLAGS_AMD64="${LDFLAGS_COMMON} -extldflags '-Wl,-image_base,0x100000000'"

CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 CC="clang -arch arm64" go build \
    -ldflags="${LDFLAGS_ARM64}" \
    -o "${OUTPUT}.arm64" \
    ./cmd/codeagentd

CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 CC="clang -arch x86_64" go build \
    -ldflags="${LDFLAGS_AMD64}" \
    -o "${OUTPUT}.x86_64" \
    ./cmd/codeagentd

lipo -create -output "${OUTPUT}" "${OUTPUT}.arm64" "${OUTPUT}.x86_64"
rm -f "${OUTPUT}.arm64" "${OUTPUT}.x86_64"

echo "==> Built: ${OUTPUT}"
file "${OUTPUT}"
ls -lh "${OUTPUT}"
echo ""
echo "Done. The Xcode Build Phase will copy this binary into the app bundle."
