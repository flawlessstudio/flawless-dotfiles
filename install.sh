#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GitHub Codespaces recognizes a root-level install.sh in a configured dotfiles
# repository. Keep this entrypoint thin: converge the governed Unix environment,
# then install the exact Codex release declared in manifests/capabilities.json.
bash "$ROOT/scripts/bootstrap.sh" --apply
export PATH="$HOME/.local/bin:$PATH"
bash "$ROOT/scripts/install-codex.sh" --apply
