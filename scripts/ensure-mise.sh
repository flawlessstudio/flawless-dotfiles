#!/usr/bin/env bash
set -euo pipefail

MODE="plan"
for arg in "$@"; do
  case "$arg" in
    --plan) MODE="plan" ;;
    --apply) MODE="apply" ;;
    -h|--help)
      printf '%s\n' 'Usage: scripts/ensure-mise.sh [--plan|--apply]'
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if command -v mise >/dev/null 2>&1; then
  printf 'PASS  mise available: %s\n' "$(command -v mise)"
  exit 0
fi

if [[ "$MODE" != "apply" ]]; then
  echo "PLAN: mise is not installed. Apply would use the official https://mise.run bootstrap endpoint." >&2
  exit 3
fi

command -v curl >/dev/null 2>&1 || {
  echo "curl is required to bootstrap mise" >&2
  exit 4
}

curl -fsSL https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 || {
  echo "mise installation completed but the binary is not resolvable" >&2
  exit 5
}

printf 'PASS  mise installed: %s\n' "$(command -v mise)"
