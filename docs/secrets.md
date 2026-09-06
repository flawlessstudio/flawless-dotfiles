# Secret management architecture

## Status

Canonical security baseline for secret handling in `flawless-dotfiles`.

## Invariant

**Secret values do not belong in this public repository.**

The repository may declare:

- logical secret names;
- whether a capability requires a secret;
- non-secret descriptions;
- provider-independent usage contracts;
- machine/profile policy.

It must not contain:

- API keys or tokens;
- passwords;
- private SSH keys;
- session cookies;
- OAuth refresh/access tokens;
- encrypted secret blobs merely for convenience;
- private provider locators that disclose sensitive inventory.

## Canonical model

```text
public desired state
  fnox.toml
  manifests/secrets.example.json
          |
          v
local/provider binding
  ignored fnox.local.toml or global fnox config
          |
          v
external secret provider
          |
          v
fnox exec -- <process>
          |
          v
one explicitly launched process receives the requested environment
```

`fnox.toml` uses `env = "exec"`. The intended default is therefore not ambient shell injection. A process receives secrets only when launched explicitly through `fnox exec`.

## Provider policy

Provider selection is machine/profile specific and is not frozen into the public repository. Supported choices may include a password/secrets manager, cloud secret manager, OS keychain, Vault, or another reviewed fnox provider.

Preferred order:

1. provider-native machine/service identity where available;
2. external secrets manager with least-privilege access;
3. OS keychain for local human-operated machines;
4. local-only development binding when no stronger provider is justified.

A provider must not be added merely because it exists. The selected provider must match the identity, threat model and recovery requirements of the host profile.

## Identity separation

Human and agent/service identities should be separate whenever the upstream system supports it.

```text
human credential != autonomous agent credential
workstation credential != VPS service credential
development credential != production credential
```

Grant only the permissions needed by the selected profile/capability.

## Public contract

The public root currently declares optional logical names such as:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- `HCLOUD_TOKEN`

These are identifiers, not values. Their presence does not require every host to configure every provider.

## Local binding

Use either:

- the global fnox configuration under the user's configuration directory; or
- an ignored local fnox overlay such as `fnox.local.toml`.

Never commit the local binding file when it contains private provider metadata or values.

## Safe execution

Prefer:

```sh
fnox exec -- <command>
```

over exporting all credentials into an interactive shell.

For unattended execution, use the provider's non-interactive/machine identity and invoke fnox non-interactively. Do not automate browser login or credential enrollment inside the public bootstrap.

## Validation

The environment doctor verifies only that:

- `fnox` is installed through the locked toolchain;
- the public configuration contract can be parsed/discovered;
- tracked files do not match common credential filenames/signatures.

It does **not** retrieve or print secret values.

Provider authentication and secret-resolution tests belong to the corresponding private host/profile gate. Any such gate must redact output and must not upload credentials as artifacts.

## Rotation and revocation

Rotation is owned by the upstream provider, not Git. A rotated value should require no public repository commit unless the logical secret name or capability contract changes.

On suspected compromise:

1. revoke/rotate at the provider;
2. invalidate affected sessions/tokens;
3. inspect Git history and CI logs for exposure;
4. run repository secret scanning;
5. update the trust decision only if the architecture or provider binding changed.

## Recovery

A new machine should require two independent things:

1. the public reproducible environment repository;
2. authorization to the chosen external secret provider.

Possessing the Git repository alone must not be sufficient to recover secret values.

## Prohibited patterns

- plaintext `.env` committed to Git;
- private keys in Git, even in a private repository by default;
- credentials hard-coded in MCP/plugin/harness JSON;
- tokens embedded in clone URLs;
- printing secret values in doctor/CI output;
- one universal credential shared across unrelated agents or hosts;
- silent generation of passwordless SSH private keys;
- treating encryption-at-rest in Git as the default secret architecture when an external provider is available.
