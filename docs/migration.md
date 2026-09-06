# Migration plan — imperative bootstrap to declarative environment

## Current state

The existing `scripts/setup.sh` is a useful bootstrap prototype. It already installs and configures a substantial Unix/macOS development environment, but it also embeds desired state inside imperative code and writes several home-directory files directly.

It remains intact during v0.1. This migration does not delete a working recovery path before the declarative replacement has passed a clean-host proof.

## Problems to remove

1. desired state embedded inside one large shell script;
2. downloads from `latest` or `curl | sh` throughout the normal convergence path;
3. full-file writes to user configuration without an ownership model;
4. mixed package installation, configuration, credentials and runtime concerns;
5. weak distinction between optional and required dependencies;
6. no canonical dry-run/status/doctor contract;
7. no fresh-machine completion gate.

## Migration stages

### M0 — Freeze and inventory

- Keep `scripts/setup.sh` unchanged as legacy evidence/recovery.
- Extract its owned configuration into explicit sources.
- Record the new repository contract and security invariants.

**Status:** implemented in v0.1 branch.

### M1 — Declarative core

- Adopt `mise.toml` as the desired-state entrypoint.
- Add platform profile resolution.
- Project only explicitly owned dotfiles.
- Add plan/apply/doctor/validate commands.

**Status:** implemented in v0.1 branch.

### M2 — Tool/package parity

Compare every package/runtime installed by legacy setup against the declarative model and classify each as:

```text
required | optional | platform-specific | obsolete | duplicate
```

Only required and high-value optional tools move into the canonical baseline. Do not copy the old list blindly.

**Exit criterion:** no required legacy capability exists only in `setup.sh`.

### M3 — Agent adapters

For Codex, Claude Code and Hermes Agent:

1. capture only verified current configuration surfaces;
2. add read-only discovery/status first;
3. add projection only for canonical, non-secret assets;
4. preserve auth, sessions, memories, logs, caches and unknown neighboring files;
5. validate discovery from the actual harness.

**Exit criterion:** one canonical asset can be projected and discovered by each selected harness without directory replacement or secret copying.

### M4 — Clean-host proof

Run on a disposable clean Linux/remote host:

```text
clone/bootstrap -> plan -> apply -> doctor -> second apply -> diff
```

Required evidence:

- bootstrap succeeds;
- doctor has zero failures;
- second apply is idempotent;
- no secret enters Git/log output;
- unmanaged host state survives;
- rollback/unapply works for repository-owned files.

### M5 — Legacy retirement

Only after M4 passes:

- mark `scripts/setup.sh` deprecated;
- retain it for one release window if useful for rollback/comparison;
- then archive or remove it through a dedicated, reviewable change.

## Explicit non-goals for this migration

- Nix/Home Manager adoption;
- encrypted secrets in Git;
- automatic machine snapshot commits;
- fleet management;
- autonomous drift remediation;
- automatic installation of every agent/plugin/MCP candidate;
- merging domain SSOT repositories into this repository.

These are separate decisions, not prerequisites for a reproducible MVP.
