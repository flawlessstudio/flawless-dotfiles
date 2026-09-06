#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="plan"
for arg in "$@"; do
  case "$arg" in
    --plan) MODE="plan" ;;
    --apply) MODE="apply" ;;
    -h|--help)
      printf '%s\n' 'Usage: scripts/install-tools.sh [--plan|--apply]'
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
command -v mise >/dev/null 2>&1 || {
  echo "mise is required. Run: bash scripts/ensure-mise.sh --apply" >&2
  exit 3
}

export MISE_TRUSTED_CONFIG_PATHS="$ROOT"

if [[ "$MODE" == "plan" ]]; then
  mise install --dry-run
  exit $?
fi

mise --yes install
mise reshim
if mise install --dry-run-code >/dev/null 2>&1; then
  echo "PASS  configured toolchain converged"
  exit 0
fi
status=$?
if [[ "$status" -eq 1 ]]; then
  echo "mise still reports configured tools missing after install" >&2
  exit 1
fi
exit "$status"
