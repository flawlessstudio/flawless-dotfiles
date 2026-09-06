#!/usr/bin/env python3
"""Validate cross-registry integrity for the final Flawless environment baseline."""

from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFESTS = ROOT / "manifests"


def load(name: str) -> dict:
    path = MANIFESTS / name
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot load {name}: {exc}") from exc


def unique_index(items: list[dict], label: str) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for item in items:
        item_id = item.get("id")
        if not isinstance(item_id, str) or not item_id:
            raise ValueError(f"{label} contains an invalid id")
        if item_id in result:
            raise ValueError(f"duplicate {label} id: {item_id}")
        result[item_id] = item
    return result


def detect_profile_cycles(profiles: dict[str, dict]) -> None:
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(profile_id: str) -> None:
        if profile_id in visiting:
            raise ValueError(f"profile inheritance cycle detected at {profile_id}")
        if profile_id in visited:
            return
        visiting.add(profile_id)
        for parent in profiles[profile_id].get("inherits", []):
            if parent not in profiles:
                raise ValueError(f"profile {profile_id} inherits unknown profile {parent}")
            visit(parent)
        visiting.remove(profile_id)
        visited.add(profile_id)

    for profile_id in profiles:
        visit(profile_id)


def main() -> int:
    env = load("environment.json")
    capabilities_doc = load("capabilities.json")
    profiles_doc = load("profiles.json")
    harnesses_doc = load("harnesses.json")

    if env.get("schema_version") != 2:
        raise ValueError("environment.json must use schema_version 2")
    if env.get("baseline") != "final-production":
        raise ValueError("environment.json must declare final-production baseline")
    if env.get("closure", {}).get("mvp_or_80_20_stop") is not False:
        raise ValueError("MVP/80-20 stop must be explicitly disabled for this baseline")

    capabilities = unique_index(capabilities_doc.get("capabilities", []), "capability")
    profiles = unique_index(profiles_doc.get("profiles", []), "profile")
    contracts = unique_index(harnesses_doc.get("contracts", []), "harness contract")

    if not capabilities or not profiles or not contracts:
        raise ValueError("capability, profile and harness registries must be non-empty")

    detect_profile_cycles(profiles)

    for profile_id, profile in profiles.items():
        for capability_id in profile.get("capabilities", []):
            if capability_id not in capabilities:
                raise ValueError(f"profile {profile_id} references unknown capability {capability_id}")

    for capability_id, capability in capabilities.items():
        declared_profiles = capability.get("profiles", [])
        for profile_id in declared_profiles:
            if profile_id not in profiles:
                raise ValueError(f"capability {capability_id} references unknown profile {profile_id}")
            if capability_id not in profiles[profile_id].get("capabilities", []) and capability_id not in {
                cap
                for parent in profiles[profile_id].get("inherits", [])
                for cap in profiles[parent].get("capabilities", [])
            }:
                # Nested inheritance is resolved below; the direct declaration mismatch is
                # reported only if the capability is absent from the full closure.
                pass

        version_policy = capability.get("version_policy")
        reproducibility = capability.get("reproducibility")
        if version_policy in {"exact", "exact-reviewed-pin", "reviewed-release-pin"} and not capability.get("version"):
            raise ValueError(f"capability {capability_id} declares a pinned policy without a version")
        if not reproducibility:
            raise ValueError(f"capability {capability_id} must declare reproducibility semantics")

    def profile_capability_closure(profile_id: str) -> set[str]:
        result = set(profiles[profile_id].get("capabilities", []))
        for parent in profiles[profile_id].get("inherits", []):
            result.update(profile_capability_closure(parent))
        return result

    for capability_id, capability in capabilities.items():
        for profile_id in capability.get("profiles", []):
            if capability_id not in profile_capability_closure(profile_id):
                raise ValueError(
                    f"capability/profile mismatch: {capability_id} claims {profile_id}, "
                    "but the profile closure does not contain it"
                )

    harness_capabilities = set()
    for contract_id, contract in contracts.items():
        capability_id = contract.get("capability")
        if capability_id not in capabilities:
            raise ValueError(f"harness {contract_id} references unknown capability {capability_id}")
        if capability_id in harness_capabilities:
            raise ValueError(f"multiple harness contracts claim capability {capability_id}")
        harness_capabilities.add(capability_id)
        if contract.get("binary") != capabilities[capability_id].get("binary"):
            raise ValueError(f"binary mismatch between harness {contract_id} and capability {capability_id}")
        if not contract.get("adapter_policy") or not contract.get("credential_policy") or not contract.get("runtime_policy"):
            raise ValueError(f"harness {contract_id} is missing ownership policies")

    declared_harness_ids = set(contracts)
    expected_harness_ids = {
        capability_id
        for capability_id, capability in capabilities.items()
        if capability.get("category") in {
            "coding-agent",
            "coding-research-agent",
            "provider-independent-coding-agent",
            "autonomous-agent-runtime",
        }
    }
    if declared_harness_ids != expected_harness_ids:
        raise ValueError(
            f"harness registry mismatch: contracts={sorted(declared_harness_ids)} "
            f"expected={sorted(expected_harness_ids)}"
        )

    for registry_key, expected in {
        "profile_registry": "manifests/profiles.json",
        "capability_registry": "manifests/capabilities.json",
        "harness_contract_registry": "manifests/harnesses.json",
    }.items():
        if env.get(registry_key) != expected:
            raise ValueError(f"environment.json {registry_key} must reference {expected}")

    print(f"PASS  capabilities={len(capabilities)} profiles={len(profiles)} harnesses={len(contracts)}")
    print("PASS  profile inheritance is acyclic and fully resolved")
    print("PASS  capability/profile references are bidirectionally consistent")
    print("PASS  every governed agent capability has one harness ownership contract")
    print("PASS  final-production closure semantics are active")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"FAIL  {exc}", file=sys.stderr)
        raise SystemExit(1)
