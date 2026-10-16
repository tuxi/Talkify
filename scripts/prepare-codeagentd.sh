#!/bin/bash
# Keep Xcode's bundled daemon in sync with the sibling Go repository.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT}/../code-agent"
if [[ ! -d "$SOURCE/.git" && ! -f "$SOURCE/.git" ]]; then
  exit 0 # Distribution checkouts can use the downloaded release binary.
fi
ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] || ARCH="amd64"
MODE="universal"
[[ "${CONFIGURATION:-Debug}" != Debug* ]] || MODE="native-${ARCH}"
FINGERPRINT="$(/usr/bin/python3 - "$SOURCE" "$MODE" <<'PY'
import hashlib,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]); h=hashlib.sha256(sys.argv[2].encode())
h.update(subprocess.check_output(['go','version']))
files=subprocess.check_output(['git','-C',str(root),'ls-files','--cached','--others','--exclude-standard','-z','--','*.go','go.mod','go.sum']).split(b'\0')
for name in sorted(set(files)):
    if not name or name.endswith(b'_test.go'): continue
    path=root/name.decode()
    if path.is_file(): h.update(name);h.update(path.read_bytes())
print(h.hexdigest())
PY
)"
STAMP="${ROOT}/build/codeagentd.source-fingerprint"
if [[ -x "${ROOT}/build/codeagentd" && -f "$STAMP" && "$(cat "$STAMP")" == "$FINGERPRINT" ]]; then
  echo "codeagentd source unchanged (${FINGERPRINT:0:12})"
  exit 0
fi
VERSION="dev-$(git -C "$SOURCE" rev-parse --short HEAD)-${FINGERPRINT:0:12}"
if [[ "$MODE" == native-* ]]; then
  "${ROOT}/scripts/build-codeagentd.sh" "$VERSION" --native
else
  "${ROOT}/scripts/build-codeagentd.sh" "$VERSION"
fi
printf '%s\n' "$FINGERPRINT" > "$STAMP"
