#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="plan"

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [--plan|--apply]

  --plan   Read-only preflight. Reports missing mise/tool/config state. (default)
  --apply  Bootstrap mise if needed, converge toolchain and managed config,
           then run the read-only doctor.
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

cd "$ROOT"

if [[ "$MODE" == "plan" ]]; then
  echo "== Flawless Unix environment plan =="
  if bash "$ROOT/scripts/ensure-mise.sh" --plan; then
    bash "$ROOT/scripts/install-tools.sh" --plan
    mise bootstrap dotfiles apply --dry-run
  else
    status=$?
    [[ "$status" -eq 3 ]] || exit "$status"
  fi
  echo
  bash "$ROOT/scripts/doctor.sh" --allow-missing
  exit 0
fi

echo "== Phase 1/4: mise bootstrap =="
bash "$ROOT/scripts/ensure-mise.sh" --apply
export PATH="$HOME/.local/bin:$PATH"

echo
echo "== Phase 2/4: toolchain convergence =="
bash "$ROOT/scripts/install-tools.sh" --apply

echo
echo "== Phase 3/4: Unix configuration projection =="
export MISE_TRUSTED_CONFIG_PATHS="$ROOT"
mise bootstrap dotfiles apply --yes

echo
echo "== Phase 4/4: environment doctor =="
bash "$ROOT/scripts/doctor.sh"
