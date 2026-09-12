#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="plan"

usage() {
  cat <<'EOF'
Usage: scripts/install-codex.sh [--plan|--apply]

  --plan   Report the governed Codex target and current binary state. (default)
  --apply  Install the exact governed Codex release with OpenAI's standalone installer,
           then verify the resulting binary and version.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --plan) MODE="plan" ;;
    --apply) MODE="apply" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to read the governed Codex version from manifests/capabilities.json" >&2
  exit 3
}

TARGET_VERSION="$(python3 - "$ROOT/manifests/capabilities.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for capability in data.get("capabilities", []):
    if capability.get("id") == "codex":
        version = capability.get("version")
        policy = capability.get("install_policy")
        if not version:
            raise SystemExit("Codex capability has no governed version")
        if policy != "vendor-standalone-versioned-installer":
            raise SystemExit(f"Unsupported Codex install_policy: {policy!r}")
        print(version)
        break
else:
    raise SystemExit("Codex capability is missing from manifests/capabilities.json")
PY
)"

current_version() {
  command -v codex >/dev/null 2>&1 || return 1
  codex --version 2>/dev/null | awk '{print $NF; exit}'
}

CURRENT_VERSION="$(current_version || true)"

if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
  echo "PASS  Codex $TARGET_VERSION already satisfies the governed exact pin"
  exit 0
fi

if [[ "$MODE" == "plan" ]]; then
  printf 'Codex target:  %s\n' "$TARGET_VERSION"
  printf 'Codex current: %s\n' "${CURRENT_VERSION:-missing}"
  printf '%s\n' 'PLAN  install exact governed release via OpenAI standalone installer'
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  echo "curl is required to acquire OpenAI's standalone Codex installer" >&2
  exit 4
}

TMP_INSTALLER="$(mktemp)"
trap 'rm -f "$TMP_INSTALLER"' EXIT

curl -fsSL https://chatgpt.com/codex/install.sh -o "$TMP_INSTALLER"
CODEX_NON_INTERACTIVE=1 sh "$TMP_INSTALLER" --release "$TARGET_VERSION"

export PATH="$HOME/.local/bin:$PATH"
command -v codex >/dev/null 2>&1 || {
  echo "Codex installation completed without a resolvable codex binary" >&2
  exit 5
}

INSTALLED_VERSION="$(current_version || true)"
if [[ "$INSTALLED_VERSION" != "$TARGET_VERSION" ]]; then
  echo "Codex version mismatch: expected $TARGET_VERSION, got ${INSTALLED_VERSION:-unknown}" >&2
  exit 6
fi

printf 'PASS  codex=%s version=%s\n' "$(command -v codex)" "$INSTALLED_VERSION"
