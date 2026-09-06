# Architecture — Flawless Reproducible Agent Environment

## Purpose

`flawless-dotfiles` is the **machine/user-environment composition root**. Its job is to reconstruct the non-secret capabilities of a Flawless development workstation or remote development host from versioned desired state.

It is intentionally not a monorepo for every AI asset. Domain artifacts remain in their own canonical sources and are projected or referenced here only when a host needs them.

## State model

Every managed artifact belongs to exactly one primary state class:

| Class | Versioned here? | Meaning |
|---|---:|---|
| `canonical` | yes | source this repository owns |
| `projected` | generated/applied | material derived from a canonical source for a target |
| `machine-local` | no | host-specific override or identity |
| `secret-reference` | reference only | logical requirement; value comes from a secret/auth system |
| `runtime` | no | sessions, history, caches, logs, OAuth state, generated state |

The key invariant is `canonical != runtime`.

## Functional planes

```text
public Git desired state
        |
        +-- mise.toml + platform profiles
        +-- managed dotfile sources
        +-- manifests
        +-- adapter contracts
        |
        v
   plan / diff
        |
        v
 explicit apply
        |
        +--> workstation files/tools
        +--> optional agent projections
        |
        v
      doctor
        |
        v
 verified host state

secret values ----------> external secret/login/keyring plane
runtime sessions -------> harness-owned local state
canonical AI assets ----> external domain SSOTs
```

## Ownership boundaries

This repository owns machine composition and projection mechanics. It consumes four logical external domains without duplicating them:

1. **agent definitions** — identities, contracts and orchestration definitions;
2. **Agent Skills** — governed skill packages and provenance;
3. **MCP assets** — MCP registry, server/client definitions and security metadata;
4. **AI governance/protocols** — prompts, protocols, audit and validation standards.

An adapter may transform or link one of these assets into a harness-specific location. The canonical artifact remains upstream.

## Convergence engine

The MVP uses **mise** as the declarative convergence engine because it currently covers the minimum required surface in one tool:

- tool/runtime versions;
- platform/environment profiles;
- bootstrap tasks;
- dotfile projection;
- dry-run/status;
- lockable tool resolution;
- repository and host bootstrap primitives if later required.

A dedicated dotfile manager such as Chezmoi remains an escalation option only if mise's projection/template model proves insufficient. Nix/Home Manager is intentionally not part of MVP v0.1.

## Profiles

The baseline separates shared intent from platform implementation:

```text
mise.toml
  + mise.unix.toml
  + future mise.linux.toml
  + future mise.macos.toml
  + future mise.windows.toml
  + ignored *.local.toml overlays
```

Functional equivalence is the goal; byte-identical configuration across operating systems is not.

## Agent harness adapters

Initial consumers are Codex, Claude Code and Hermes Agent. In v0.1 their surfaces are documented but automatic projection is disabled.

Adapter rules:

1. manage the smallest possible target surface;
2. merge/project instead of replacing an entire harness directory;
3. preserve unknown and runtime-owned state;
4. never project credentials;
5. require a trust review before installing executable hooks/plugins/MCP servers;
6. provide an unapply/rollback path for repository-owned state.

## Lifecycle

```text
discover
  -> declare
  -> validate source
  -> resolve profile
  -> resolve non-secret dependencies
  -> plan/diff
  -> explicit apply
  -> doctor
  -> operate
  -> detect drift
  -> reconcile
```

Snapshotting is deliberately not authoritative: observed machine state may propose a source change, but it does not automatically become canonical state.

## MVP lock

v0.1 is limited to five capabilities:

1. declarative desired state;
2. selective dotfile projection;
3. external secret references;
4. agent-environment adapter contract;
5. bootstrap/apply/doctor.

Anything else requires a demonstrated gap and a separate decision.
