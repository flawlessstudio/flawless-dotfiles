#!/usr/bin/env python3
"""Safely materialize exact-pinned external SSOT repositories.

The public composition root intentionally does not contain the private source
inventory. Pass a manifest explicitly or set FLAWLESS_SOURCES_MANIFEST.

Properties:
- exact commit pins; never follows a moving branch at runtime;
- never pushes;
- refuses dirty repositories and origin mismatches;
- detached checkout at the declared commit;
- validates lifecycle/trust/update metadata when present;
- rejects embedded HTTP(S) credentials;
- clear authentication errors for private sources;
- plan/status are read-only;
- unapply is conservative and explicit.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any
from urllib.parse import urlsplit

SHA40 = re.compile(r"^[0-9a-f]{40}$")
ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
DATE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")

LIFECYCLES = {"active", "frozen", "reference", "deprecated", "archived"}
AUTHORITIES = {"internal", "official", "first-party", "trusted-upstream", "community-reviewed", "experimental"}
TRUST_TIERS = {"T0", "T1", "T2", "T3", "T4", "T5"}
UPDATE_POLICIES = {"frozen", "manual-review", "security-only", "scheduled-review"}
REQUIRED_FIELDS = {
    "id", "repository", "clone_url", "branch", "commit", "destination",
    "role", "lifecycle", "private", "required",
}
OPTIONAL_FIELDS = {
    "authority", "trust_tier", "license", "update_policy", "last_verified", "notes",
}
ALLOWED_FIELDS = REQUIRED_FIELDS | OPTIONAL_FIELDS


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    check: bool = True,
    capture: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def git(*args: str, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["git", *args], cwd=cwd, check=check)


def normalize_origin(value: str) -> str:
    value = value.strip().rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    if value.startswith("git@github.com:"):
        value = "https://github.com/" + value.removeprefix("git@github.com:")
    if value.startswith("ssh://git@github.com/"):
        value = "https://github.com/" + value.removeprefix("ssh://git@github.com/")
    return value.lower()


def validate_clone_url(source_id: str, value: str) -> None:
    if value.startswith("git@"):
        return
    if not value.startswith(("https://", "ssh://")):
        raise SystemExit(f"unsupported clone_url scheme for {source_id}")
    parsed = urlsplit(value)
    if parsed.username or parsed.password:
        raise SystemExit(f"embedded credentials are forbidden in clone_url for {source_id}")
    if parsed.query or parsed.fragment:
        raise SystemExit(f"query/fragment is forbidden in clone_url for {source_id}")


def resolve_manifest(cli_value: str | None) -> Path:
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    env = os.environ.get("FLAWLESS_SOURCES_MANIFEST")
    if env:
        return Path(env).expanduser().resolve()
    return Path.home() / ".config" / "flawless" / "sources.json"


def resolve_base(cli_value: str | None) -> Path:
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    env = os.environ.get("FLAWLESS_SOURCES_DIR")
    if env:
        return Path(env).expanduser().resolve()
    return Path.home() / ".local" / "share" / "flawless" / "sources"


def load_manifest(path: Path) -> list[dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(
            f"source manifest not found: {path}\n"
            "Set FLAWLESS_SOURCES_MANIFEST or pass --manifest. "
            "Private inventories must not be committed to the public dotfiles repository."
        )
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in source manifest {path}: {exc}")

    if not isinstance(data, dict) or set(data) != {"schema_version", "sources"}:
        raise SystemExit("source manifest root must contain only schema_version and sources")
    if data.get("schema_version") != 1 or not isinstance(data.get("sources"), list):
        raise SystemExit("source manifest must contain schema_version=1 and a sources array")

    seen_ids: set[str] = set()
    seen_destinations: set[str] = set()

    for index, source in enumerate(data["sources"]):
        if not isinstance(source, dict):
            raise SystemExit(f"sources[{index}] must be an object")
        missing = REQUIRED_FIELDS - source.keys()
        unknown = source.keys() - ALLOWED_FIELDS
        if missing:
            raise SystemExit(f"sources[{index}] missing fields: {', '.join(sorted(missing))}")
        if unknown:
            raise SystemExit(f"sources[{index}] unknown fields: {', '.join(sorted(unknown))}")

        source_id = str(source["id"])
        if not ID.fullmatch(source_id):
            raise SystemExit(f"invalid source id: {source_id!r}")
        if source_id in seen_ids:
            raise SystemExit(f"duplicate source id: {source_id}")

        for field in ("repository", "clone_url", "branch", "role"):
            if not isinstance(source[field], str) or not source[field].strip():
                raise SystemExit(f"{field} must be a non-empty string for {source_id}")

        validate_clone_url(source_id, source["clone_url"])

        if not SHA40.fullmatch(str(source["commit"])):
            raise SystemExit(f"invalid 40-character commit pin for {source_id}")

        destination_raw = source["destination"]
        if not isinstance(destination_raw, str) or not destination_raw:
            raise SystemExit(f"destination must be a non-empty string for {source_id}")
        destination = Path(destination_raw)
        if destination.is_absolute() or ".." in destination.parts or destination_raw in {".", "./"}:
            raise SystemExit(f"unsafe destination for {source_id}: {destination}")
        if str(destination) in seen_destinations:
            raise SystemExit(f"duplicate source destination: {destination}")

        if source["lifecycle"] not in LIFECYCLES:
            raise SystemExit(f"invalid lifecycle for {source_id}: {source['lifecycle']!r}")
        if type(source["private"]) is not bool or type(source["required"]) is not bool:
            raise SystemExit(f"private and required must be booleans for {source_id}")

        if "authority" in source and source["authority"] not in AUTHORITIES:
            raise SystemExit(f"invalid authority for {source_id}: {source['authority']!r}")
        if "trust_tier" in source and source["trust_tier"] not in TRUST_TIERS:
            raise SystemExit(f"invalid trust_tier for {source_id}: {source['trust_tier']!r}")
        if "update_policy" in source and source["update_policy"] not in UPDATE_POLICIES:
            raise SystemExit(f"invalid update_policy for {source_id}: {source['update_policy']!r}")
        if "license" in source and source["license"] is not None and not isinstance(source["license"], str):
            raise SystemExit(f"license must be a string or null for {source_id}")
        if "last_verified" in source and source["last_verified"] is not None:
            if not isinstance(source["last_verified"], str) or not DATE.fullmatch(source["last_verified"]):
                raise SystemExit(f"last_verified must be YYYY-MM-DD or null for {source_id}")
        if "notes" in source and not isinstance(source["notes"], str):
            raise SystemExit(f"notes must be a string for {source_id}")

        seen_ids.add(source_id)
        seen_destinations.add(str(destination))

    return data["sources"]


def repo_state(source: dict[str, Any], target: Path) -> tuple[str, str]:
    if not target.exists():
        return "missing", "repository is not materialized"
    if not (target / ".git").exists():
        return "invalid", "destination exists but is not a Git repository"

    origin = git("remote", "get-url", "origin", cwd=target, check=False)
    if origin.returncode != 0:
        return "invalid", "Git repository has no origin remote"
    if normalize_origin(origin.stdout) != normalize_origin(str(source["clone_url"])):
        return "conflict", f"origin mismatch: {origin.stdout.strip()}"

    dirty = git("status", "--porcelain=v1", "--untracked-files=all", cwd=target)
    if dirty.stdout.strip():
        return "dirty", "working tree contains local changes"

    head = git("rev-parse", "HEAD", cwd=target, check=False)
    if head.returncode != 0:
        return "invalid", "cannot resolve HEAD"
    current = head.stdout.strip()
    if current != source["commit"]:
        return "drift", f"HEAD {current} != pin {source['commit']}"
    return "converged", current


def apply_source(source: dict[str, Any], target: Path) -> None:
    expected_origin = str(source["clone_url"])
    pin = str(source["commit"])
    branch = str(source["branch"])

    if target.exists():
        state, detail = repo_state(source, target)
        if state in {"invalid", "conflict", "dirty"}:
            raise RuntimeError(f"refusing to mutate {target}: {detail}")
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        clone = git("clone", "--no-checkout", "--filter=blob:none", expected_origin, str(target), check=False)
        if clone.returncode != 0:
            hint = ""
            if source.get("private"):
                hint = " Authenticate Git for this private source and retry."
            raise RuntimeError(f"clone failed for {source['id']}: {clone.stderr.strip()}.{hint}")

    origin = git("remote", "get-url", "origin", cwd=target)
    if normalize_origin(origin.stdout) != normalize_origin(expected_origin):
        raise RuntimeError(f"origin mismatch at {target}; refusing checkout")

    fetch = git("fetch", "--prune", "--no-tags", "origin", branch, cwd=target, check=False)
    if fetch.returncode != 0:
        hint = ""
        if source.get("private"):
            hint = " Check Git authentication/authorization."
        raise RuntimeError(f"fetch failed for {source['id']}: {fetch.stderr.strip()}.{hint}")

    verify = git("cat-file", "-e", f"{pin}^{{commit}}", cwd=target, check=False)
    if verify.returncode != 0:
        raise RuntimeError(f"pinned commit {pin} is not available from {source['id']} branch {branch}")

    checkout = git("checkout", "--detach", pin, cwd=target, check=False)
    if checkout.returncode != 0:
        raise RuntimeError(f"checkout failed for {source['id']}: {checkout.stderr.strip()}")

    final_state, detail = repo_state(source, target)
    if final_state != "converged":
        raise RuntimeError(f"post-apply validation failed for {source['id']}: {final_state}: {detail}")


def remove_source(source: dict[str, Any], target: Path, yes: bool) -> None:
    state, detail = repo_state(source, target)
    if state == "missing":
        return
    if state != "converged":
        raise RuntimeError(f"refusing to remove {target}: {state}: {detail}")
    if not yes:
        raise RuntimeError("--unapply requires --yes; source clones are never deleted implicitly")
    shutil.rmtree(target)


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronize exact-pinned Flawless external SSOT sources")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--plan", action="store_true", help="read-only desired/current comparison")
    mode.add_argument("--apply", action="store_true", help="clone/fetch and checkout exact pins")
    mode.add_argument("--status", action="store_true", help="exit nonzero when required sources are not converged")
    mode.add_argument("--unapply", action="store_true", help="remove only clean exact-pin managed clones")
    parser.add_argument("--yes", action="store_true", help="required with --unapply")
    parser.add_argument("--manifest", help="path to private source manifest")
    parser.add_argument("--base", help="materialization root")
    args = parser.parse_args()

    if not any((args.plan, args.apply, args.status, args.unapply)):
        args.status = True

    if shutil.which("git") is None:
        raise SystemExit("git is required")

    manifest = resolve_manifest(args.manifest)
    base = resolve_base(args.base)
    sources = load_manifest(manifest)

    failures = 0
    print(f"manifest: {manifest}")
    print(f"base:     {base}")

    for source in sources:
        target = base / source["destination"]
        state, detail = repo_state(source, target)
        print(f"{state.upper():10} {source['id']}: {detail}")

        try:
            if args.apply and state != "converged":
                apply_source(source, target)
                print(f"APPLIED    {source['id']} -> {source['commit']}")
            elif args.unapply:
                remove_source(source, target, args.yes)
                print(f"UNAPPLIED  {source['id']}")
        except RuntimeError as exc:
            print(f"ERROR      {source['id']}: {exc}", file=sys.stderr)
            failures += 1
            continue

        if args.status:
            final_state, final_detail = repo_state(source, target)
            if source.get("required", True) and final_state != "converged":
                print(f"REQUIRED   {source['id']}: {final_state}: {final_detail}", file=sys.stderr)
                failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
