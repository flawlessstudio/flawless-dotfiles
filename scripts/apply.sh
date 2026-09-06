#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v mise >/dev/null 2>&1 || {
  echo "mise is required. Run: bash scripts/bootstrap.sh --apply" >&2
  exit 3
}

if [[ "${1:-}" == "--dry-run" ]]; then
  mise bootstrap --dry-run
  exit 0
fi

if [[ "${1:-}" != "--yes" ]]; then
  cat >&2 <<'EOF'
Refusing to mutate without explicit acknowledgement.

Plan:
  bash scripts/apply.sh --dry-run

Apply:
  bash scripts/apply.sh --yes
EOF
  exit 2
fi

mise bootstrap --yes
bash "$ROOT/scripts/doctor.sh"
