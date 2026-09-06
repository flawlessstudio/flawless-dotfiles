#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOW_MISSING=0
[[ "${1:-}" == "--allow-missing" ]] && ALLOW_MISSING=1

PASS=0
WARN=0
FAIL=0

pass() { printf 'PASS  %s\n' "$*"; PASS=$((PASS+1)); }
warn() { printf 'WARN  %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }

check_required() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "command:$cmd"
  elif [[ "$ALLOW_MISSING" -eq 1 ]]; then
    warn "command:$cmd missing"
  else
    fail "command:$cmd missing"
  fi
}

check_optional() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "optional:$cmd available"
  else
    warn "optional:$cmd not installed"
  fi
}

cd "$ROOT"
echo "== Flawless environment doctor =="
echo "root: $ROOT"
echo

for cmd in git mise node python uv pnpm; do
  check_required "$cmd"
done

case "$(uname -s 2>/dev/null || true)" in
  Darwin|Linux)
    for cmd in zsh tmux starship; do check_optional "$cmd"; done
    ;;
esac

# Agent harnesses are intentionally optional in MVP v0.1. Their presence is
# observed, not required, and their auth/session state is never inspected.
for cmd in codex claude hermes; do
  check_optional "$cmd"
done

echo
echo "-- repository safety --"

forbidden_paths="$(
  git ls-files | grep -E '(^|/)(\.env(\..*)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(pem|key|p12|pfx|kdbx))$' || true
)"
if [[ -n "$forbidden_paths" ]]; then
  fail "tracked credential-like files detected: $(echo "$forbidden_paths" | tr '\n' ' ')"
else
  pass "no tracked credential-like filenames"
fi

# Report filenames only; never print a discovered credential value.
secret_files="$(
  git grep -IlE '(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' -- . 2>/dev/null || true
)"
if [[ -n "$secret_files" ]]; then
  fail "possible secret material detected in tracked files: $(echo "$secret_files" | tr '\n' ' ')"
else
  pass "no common plaintext-secret signatures in tracked content"
fi

for file in \
  manifests/environment.json \
  manifests/harnesses.json \
  manifests/secrets.example.json \
  dotfiles/gitconfig \
  dotfiles/starship.toml; do
  [[ -f "$file" ]] && pass "source:$file" || fail "source:$file missing"
done

echo
echo "-- declarative state --"
if command -v mise >/dev/null 2>&1; then
  if mise config >/dev/null 2>&1; then
    pass "mise configuration resolves"
  else
    fail "mise configuration does not resolve"
  fi

  if mise bootstrap status --missing >/dev/null 2>&1; then
    pass "mise desired state converged"
  elif [[ "$ALLOW_MISSING" -eq 1 ]]; then
    warn "mise reports missing/unapplied desired state"
  else
    fail "mise reports missing/unapplied desired state"
  fi
else
  warn "mise state checks skipped"
fi

echo
printf 'summary: pass=%d warn=%d fail=%d\n' "$PASS" "$WARN" "$FAIL"

if (( FAIL > 0 )); then
  exit 1
fi
