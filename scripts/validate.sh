#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== static shell validation =="
for script in scripts/*.sh install.sh; do
  bash -n "$script"
  printf 'PASS  %s\n' "$script"
done

echo
echo "== manifest and Python validation =="
if command -v python >/dev/null 2>&1; then
  for file in manifests/*.json; do
    python -m json.tool "$file" >/dev/null
    printf 'PASS  %s\n' "$file"
  done
  python -m py_compile scripts/sync-sources.py scripts/validate-registry.py
  echo "PASS  Python scripts compile"
  python scripts/validate-registry.py

  python - <<'PY'
import tomllib
for name in ("mise.toml", "mise.unix.toml", "mise.windows.toml", ".miserc.toml"):
    with open(name, "rb") as f:
        tomllib.load(f)
    print(f"PASS  {name}")
PY

  bash scripts/install-codex.sh --plan
  echo "PASS  Codex governed install plan"
else
  echo "FAIL  python unavailable; final registry validation cannot be skipped" >&2
  exit 1
fi

echo
echo "== secret-safety validation =="
forbidden="$(
  git ls-files | grep -E '(^|/)(\.env(\..*)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|key|p12|pfx|kdbx))$' || true
)"
if [[ -n "$forbidden" ]]; then
  echo "FAIL  tracked credential-like filenames: $(echo "$forbidden" | tr '\n' ' ')" >&2
  exit 1
fi
echo "PASS  no tracked credential-like filenames"

secret_files="$(
  git grep -IlE '(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' -- . 2>/dev/null || true
)"
if [[ -n "$secret_files" ]]; then
  echo "FAIL  possible secret material in: $(echo "$secret_files" | tr '\n' ' ')" >&2
  exit 1
fi
echo "PASS  no common plaintext-secret signatures"

echo
echo "== mise validation =="
if command -v mise >/dev/null 2>&1; then
  mise config >/dev/null
  echo "PASS  mise config"
  mise bootstrap --dry-run >/dev/null
  echo "PASS  mise bootstrap --dry-run"
else
  echo "WARN  mise unavailable; runtime plan validation skipped"
fi
