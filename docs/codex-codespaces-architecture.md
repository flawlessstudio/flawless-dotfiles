# Codex + GitHub Codespaces architecture

## Decision

Codex CLI is a **user/host capability**, not repository-owned software.

For GitHub Codespaces, the canonical composition is:

```text
flawless-dotfiles
  -> provisions Codex CLI and non-secret user environment state

GitHub Codespace
  -> one repository-scoped execution environment

~/.codex/config.toml
$CODEX_HOME/AGENTS.md
  -> user/global Codex configuration and instructions

<repository>/.codex/config.toml
<repository>/AGENTS.md
  -> repository/project-specific overrides and instructions

Codex authentication, sessions, caches and generated runtime state
  -> provider/runtime-owned; never versioned or projected by flawless-dotfiles
```

## Ownership boundary

`flawless-dotfiles` owns:

- Codex installation policy and exact reviewed version pin;
- reproducible user/host bootstrap entrypoints;
- selected non-secret user configuration/instruction projections;
- diagnostics and drift detection.

Each project repository owns:

- its `AGENTS.md` hierarchy;
- its trusted `.codex/config.toml` overrides when needed;
- project-specific scripts, tests and development dependencies.

Neither layer owns Codex authentication material, sessions, caches or other provider-managed runtime state.

## Codespaces rule

Use **one Codespace per repository** as the default isolation boundary. Do not use a single repository's devcontainer as the canonical owner of the global Codex installation merely to make Codex available.

Repository-local `.devcontainer/` configuration remains valid when that repository has genuine environment requirements beyond the user-level toolchain.

## Mobile control plane

iOS remains a control surface. Heavy Codex execution occurs in the Codespace (or another real remote execution host). Mobile clients connect to the remote host rather than attempting to make iOS the canonical Codex execution environment.

## Installation source

The governed Codex version is declared once in `manifests/capabilities.json`. `scripts/install-codex.sh` reads that value and invokes OpenAI's standalone installer for exactly that release. The root `install.sh` is the GitHub Codespaces dotfiles entrypoint and composes the existing Unix bootstrap with Codex installation.

## Validation gates

Before baselining this architecture:

1. repository CI passes;
2. GitHub Codespaces is configured to use `flawlessstudio/flawless-dotfiles` as the user's dotfiles repository;
3. a fresh Codespace successfully executes the root dotfiles installer;
4. `command -v codex` resolves;
5. `codex --version` matches the governed pin;
6. Codex authentication succeeds without committing credentials;
7. a real Codex inference succeeds;
8. global and repository instruction/config layers are observed with the documented precedence;
9. mobile access to the Codespace is validated through the selected control-plane client.

## Reopening triggers

Reopen this decision only for a material change such as:

- OpenAI changes Codex installation/configuration semantics;
- GitHub changes Codespaces dotfiles behavior;
- the execution-host strategy changes (for example, VPS or local workstation becomes primary);
- a security or reproducibility requirement invalidates the current boundary;
- a project demonstrates a real need for repository-owned Codex installation rather than repository-local configuration.
