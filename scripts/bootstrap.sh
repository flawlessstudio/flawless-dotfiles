#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="plan"

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [--plan|--apply]

  --plan   Read-only preflight. Requires mise to be installed. (default)
  --apply  Install mise if needed, trust this repository, converge desired state,
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

have() { command -v "$1" >/dev/null 2>&1; }

install_mise() {
  if have mise; then
    return 0
  fi
  if [[ "$MODE" != "apply" ]]; then
    echo "PLAN: mise is not installed." >&2
    echo "Run with --apply to install mise using its official bootstrap endpoint." >&2
    return 3
  fi
  have curl || { echo "curl is required to bootstrap mise" >&2; return 4; }
  echo "Installing mise from https://mise.run ..."
  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
  have mise || { echo "mise installation completed but the binary is not on PATH" >&2; return 5; }
}

cd "$ROOT"

if [[ "$MODE" == "plan" ]]; then
  have mise || { install_mise; exit $?; }
  echo "== Flawless environment plan =="
  mise bootstrap --dry-run
  echo
  "$ROOT/scripts/doctor.sh" --allow-missing
  exit 0
fi

install_mise
echo "Trusting repository-local mise configuration..."
mise trust "$ROOT/mise.toml"

echo "== Applying Flawless desired state =="
mise bootstrap --yes

echo
"$ROOT/scripts/doctor.sh"
