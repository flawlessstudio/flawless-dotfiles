# AGENTS.md

## Repository purpose

`flawless-dotfiles` is the machine/user-environment composition root for Flawless Studio. It declares and projects the non-secret desired state required to reconstruct a usable development and AI-agent workstation without duplicating domain content owned by other repositories.

## Ownership

This repository owns:

- shell, terminal, Git, editor and workstation configuration;
- cross-platform environment profiles;
- tool/runtime declarations and bootstrap entrypoints;
- projections/adapters that install or reference agent-facing assets;
- secret *references* and required-secret metadata, never secret values;
- read-only diagnostics, drift checks and environment validation.

This repository does **not** own canonical agent definitions, canonical Agent Skills, canonical MCP catalogs/servers, prompt/protocol governance, or runtime session/history/cache state. Those remain in their domain SSOTs and are consumed by reference or projection.

## Non-negotiable invariants

1. Never commit plaintext credentials, API keys, private keys, session tokens or OAuth material.
2. Prefer declarative desired state over imperative mutation.
3. Default mutation-capable entrypoints to dry-run or explicit `--apply` semantics.
4. Preserve unmanaged files and directories. Never replace an entire agent runtime directory merely to add one managed asset.
5. Distinguish `source`, `generated/projected`, `machine-local`, `secret`, and `runtime` state.
6. Keep bootstrap idempotent: a second apply must not create unexplained drift.
7. Pin or lock dependencies when reproducibility materially depends on the exact version; document unavoidable bootstrap trust roots.
8. Do not silently widen filesystem, network, credential or privilege access for an agent.
9. Keep platform-specific behavior behind explicit profiles/adapters rather than pretending all operating systems are identical.
10. Make rollback/unapply possible for repository-owned state.

## Change discipline

- Prefer small, reversible changes.
- Do not add a new manager, daemon, secret backend or orchestration layer unless it solves a demonstrated gap not already covered by the current stack.
- Keep the MVP bounded to: desired-state declaration, dotfile projection, external secret references, agent-environment adapters, and bootstrap/apply/doctor validation.
- Treat Nix/Home Manager, SOPS/age, Dev Containers, fleet management, automatic snapshotting and autonomous remediation as backlog unless a concrete requirement activates them.

## Required validation

For changes that affect executable configuration or bootstrap behavior, run as applicable:

```text
bash -n scripts/*.sh
python -m json.tool <json-manifest>
mise config
mise bootstrap --dry-run
mise bootstrap status --missing
./scripts/doctor.sh
```

If `mise` is unavailable, syntax/static checks still apply and the missing runtime validation must be reported explicitly.

## Security boundary

The repository is public. Publicly versioned files must therefore be safe to disclose. Private repository URLs, host inventories, account identifiers and environment-specific sensitive metadata belong in ignored local overlays or a separate private control plane.
