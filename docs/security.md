# Security model

## Baseline assumption

This repository is public. Treat every tracked byte as discloseable.

The repository may declare that a credential exists, but it must never contain the credential value itself.

## Secrets

Allowed:

- environment-variable names;
- secret-manager item references that reveal no sensitive value;
- example schemas with `null`/placeholder values;
- documentation describing authentication flows.

Forbidden:

- API keys and bearer tokens;
- private SSH/signing keys;
- OAuth/session tokens or cookies;
- exported credential databases;
- populated `.env` files;
- machine-account tokens;
- secret-bearing command output or logs.

Preferred resolution order:

1. provider/runtime login using the OS credential store or provider-supported auth;
2. external secret manager with least-privilege machine/service identity;
3. ignored machine-local environment file when no better integration exists;
4. encrypted Git material only after an explicit design decision — not by default.

## Agent trust boundary

AI harness configuration can execute code or confer ambient authority. Treat these as supply-chain executable inputs:

- hooks;
- plugins/extensions;
- MCP servers;
- skills containing scripts;
- bootstrap/install scripts;
- external repositories projected into an agent environment.

For each executable integration, resolve before admission:

```text
identity -> source -> authority -> version/ref -> permissions -> secrets ->
network -> filesystem -> overlap -> rollback -> validation -> decision
```

Do not grant every agent the human user's complete credentials. Prefer per-service or per-purpose credentials and separate high-risk deployment identities from ordinary coding/research identities.

## Harness-specific protections

- Never copy a complete `~/.codex`, `~/.claude` or `~/.hermes` directory into Git.
- Keep auth/session/history/cache state runtime-owned.
- Prefer OS keyrings or provider-supported credential stores where available.
- Project only selected instructions/skills/config fragments.
- Hooks require explicit review because they can execute with the user's permissions.
- MCP definitions and credentials are separate objects: version the definition, inject the credential.

## Bootstrap trust root

A fresh host has an unavoidable stage-zero trust problem: something must install the declarative manager itself. `scripts/bootstrap.sh --apply` currently uses mise's official `https://mise.run` installer if mise is absent.

This bootstrap is intentionally isolated and documented. Once mise is present, the desired state moves into versioned configuration. A future hardening step may pin and verify the installer artifact/signature if the operational threat model requires it.

## Safety gates

`doctor.sh` and `validate.sh` check for common credential-like filenames and common plaintext token signatures. They report filenames only, never matching secret values.

These checks are defense in depth, not a substitute for repository-host secret scanning or credential rotation after a leak.

## Incident rule

If a real secret is ever committed:

1. treat it as compromised;
2. revoke/rotate it at the provider;
3. remove it from current content and, when necessary, repository history;
4. identify the admission path that allowed the leak;
5. add a regression gate.

Deleting the line from the latest commit is not sufficient remediation by itself.
