# flawless-dotfiles

**Flawless Reproducible Agent Environment** — public, non-secret desired state for rebuilding the Flawless developer and AI-agent workstation across machines.

> Git · terminal · toolchains · dotfiles · platform profiles · bootstrap · agent-environment adapters · diagnostics

## Status

**v0.1 migration baseline.** The declarative path is being introduced alongside the existing `scripts/setup.sh`. The legacy script remains available until the new path passes a disposable clean-host proof, idempotency check and rollback validation.

This repository is a **machine/user-environment composition root**, not a monorepo for every Flawless AI artifact.

## What this repository owns

- shell, terminal, Git and editor configuration;
- versioned tool/runtime requirements;
- cross-platform environment profiles;
- bootstrap, plan/apply and diagnostics entrypoints;
- non-secret adapter/projection contracts for AI harnesses;
- secret requirement metadata and references — never secret values.

Canonical agent definitions, Agent Skills, MCP assets and AI governance/protocols remain in their dedicated domain SSOTs and are consumed by reference or projection rather than copied here.

## Architecture

```text
                     public Git desired state
                              |
             +----------------+----------------+
             |                |                |
         toolchain         dotfiles        manifests
             |                |                |
             +----------------+----------------+
                              |
                         mise plan/diff
                              |
                        explicit apply
                              |
              +---------------+---------------+
              |               |               |
           Windows         Unix/macOS      remote host
              |               |               |
              +---------------+---------------+
                              |
                            doctor
                              |
                       verified host state

secret values  ------------------> external login/secret manager/keyring
runtime state  ------------------> harness-owned local state
AI domain SSOTs -----------------> referenced/projected selectively
```

See [`docs/architecture.md`](docs/architecture.md) and [`docs/security.md`](docs/security.md).

## MVP lock

v0.1 contains exactly five core capabilities:

1. **Declarative desired state** — `mise.toml` + platform profiles.
2. **Selective dotfile projection** — owned files plus marker-delimited edits; no whole-directory takeover.
3. **External secret references** — no plaintext credentials in Git.
4. **Agent-environment adapter contract** — Codex, Claude Code and Hermes surfaces documented; automatic projection remains gated.
5. **Bootstrap / apply / doctor** — plan first, mutate only explicitly, then verify.

Nix/Home Manager, SOPS/age, Dev Containers, automatic snapshots, fleet management and autonomous drift remediation are backlog, not MVP requirements.

## Toolchain baseline

| Tool | Baseline |
|---|---:|
| Node.js | `24.20.0` LTS |
| Python | `3.13.15` |
| uv | `0.12.10` |
| pnpm | `11.25.0` |

The versions live in `mise.toml`; the table is descriptive. Update the manifest first.

## Safe quick start — Linux/macOS/WSL

```bash
git clone https://github.com/flawlessstudio/flawless-dotfiles.git
cd flawless-dotfiles
git switch feat/reproducible-agent-environment-v0.1   # remove after merge

# Read-only plan first
bash scripts/bootstrap.sh --plan

# Explicit convergence
bash scripts/bootstrap.sh --apply

# Subsequent operations
bash scripts/apply.sh --dry-run
bash scripts/apply.sh --yes
bash scripts/doctor.sh
bash scripts/validate.sh
```

If `mise` is absent, `--plan` does not install it. `--apply` may bootstrap it from mise's official installer endpoint.

## Safe quick start — native Windows

```powershell
git clone https://github.com/flawlessstudio/flawless-dotfiles.git
Set-Location flawless-dotfiles
git switch feat/reproducible-agent-environment-v0.1   # remove after merge

# Read-only plan first
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap.ps1 -Plan

# Explicit convergence
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap.ps1 -Apply

mise run doctor
mise run validate
```

When mise is absent, the Windows apply path prefers the official WinGet package (`jdx.mise`) and falls back to Scoop if available.

## Selective ownership

Repository-owned files live under:

```text
~/.config/flawless/
```

Existing user files such as `.gitconfig`, `.zshrc` and `.tmux.conf` are **not replaced wholesale**. The declarative layer composes Flawless-managed blocks/references into those files while preserving unrelated content.

This implements the invariant:

> Never claim ownership over a runtime or user configuration surface that this repository does not completely own.

## State classes

| Class | Tracked here? | Examples |
|---|---:|---|
| `canonical` | yes | managed source config, manifests |
| `projected` | applied/generated | target blocks/files |
| `machine-local` | no | host identity, local overrides |
| `secret-reference` | reference only | required credential names |
| `runtime` | no | sessions, histories, caches, OAuth state, logs |

## AI harnesses

The initial adapter registry covers:

- **Codex** — user/project instructions and user config surfaces;
- **Claude Code** — project instructions and skill surfaces;
- **Hermes Agent** — user config/root/skill surfaces.

Automatic projection is intentionally **disabled in v0.1**. The next gate is to prove read-only discovery and then project one canonical, non-secret asset per harness without replacing its runtime directory or copying credentials.

See [`manifests/harnesses.json`](manifests/harnesses.json).

## Secrets

Never commit:

```text
API keys
bearer/session/OAuth tokens
private SSH/signing keys
populated .env files
credential databases
secret-bearing logs
```

The repository may record only the logical requirement/reference. Secret values belong in provider login flows, the OS credential store/keyring, an external secret manager, or an ignored local overlay.

See [`manifests/secrets.example.json`](manifests/secrets.example.json).

## Repository structure

```text
flawless-dotfiles/
├── AGENTS.md                    # repository contract for coding agents
├── mise.toml                    # common desired state
├── mise.unix.toml               # Unix/macOS composition
├── mise.windows.toml            # native Windows task adapters
├── .miserc.toml                 # profile loading policy
├── manifests/                   # state, harness and secret-reference schemas
├── dotfiles/                    # canonical config fragments/files
├── scripts/
│   ├── bootstrap.sh             # plan/apply bootstrap — Unix
│   ├── bootstrap.ps1            # plan/apply bootstrap — Windows
│   ├── apply.sh                 # explicit convergence helper
│   ├── doctor.sh                # read-only Unix diagnostics
│   ├── doctor.ps1               # read-only Windows diagnostics
│   ├── validate.sh              # static/runtime validation — Unix
│   ├── validate.ps1             # static/runtime validation — Windows
│   └── setup.sh                 # legacy bootstrap; retained during migration
├── docs/
│   ├── architecture.md
│   ├── security.md
│   └── migration.md
└── blink/
    └── themes/
```

## Migration gates

The legacy bootstrap can be retired only after this sequence succeeds on a disposable clean host:

```text
clone
→ bootstrap
→ plan
→ apply
→ doctor
→ second apply
→ zero unexplained drift
→ rollback/unapply proof
```

See [`docs/migration.md`](docs/migration.md).

## Blink Shell

The existing iPhone-first remote workflow remains supported. The **Flawless Graphite v1** Blink theme is kept under:

```text
blink/themes/flawless-graphite-v1.js
```

This remains a presentation/configuration asset and is independent from the declarative environment lifecycle.

## Security principle

> Git stores desired state and provenance; secret systems store secrets; agent harnesses own runtime state.

A passing install is not enough. The environment is considered reproducible only when the declared state can be applied safely, verified, reapplied idempotently and recovered without destroying unmanaged state.
