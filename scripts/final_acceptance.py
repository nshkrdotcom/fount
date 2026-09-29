#!/usr/bin/env python3
"""Source-level Phase 16 acceptance audit.

This script is intentionally runtime-neutral. It checks the final repository shape,
closed dependency ownership, scenario/workflow evidence inventory, package allowlists,
and current documentation claims. It does not claim compilation, database, provider,
PDF, speech, Hex, or human-validation success.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("fount", "fount_observe", "fount_intelligence", "fount_workshop", "fount_run")
OLD_PACKAGES = (
    "fount_probe",
    "fount_analysis",
    "fount_semantics",
    "fount_temporal",
    "fount_reader",
    "fount_diagnose",
    "fount_playbooks",
)

WORKFLOW_EVIDENCE = {
    "W01": "packages/fount_workshop/test/writer_workflows/phase_twelve_a01_demo_test.exs",
    "W02": "packages/fount_workshop/test/writer_workflows/phase_twelve_discovery_test.exs",
    "W03": "packages/fount_workshop/test/writer_workflows/phase_twelve_scene_exploration_test.exs",
    "W04": "packages/fount_workshop/test/writer_workflows/phase_thirteen_pass_profiles_test.exs",
    "W05": "packages/fount_workshop/test/writer_workflows/phase_thirteen_rehearsal_test.exs",
    "W06": "packages/fount_workshop/test/writer_workflows/phase_thirteen_voice_test.exs",
    "W07": "packages/fount_workshop/test/writer_workflows/phase_fourteen_research_test.exs",
    "W08": "packages/fount_workshop/test/writer_workflows/phase_fourteen_notes_test.exs",
    "W09": "packages/fount_workshop/test/writer_workflows/phase_fourteen_consequence_test.exs",
    "W10": "packages/fount_workshop/test/writer_workflows/phase_fifteen_read_share_resume_test.exs",
    "W11": "packages/fount_workshop/test/writer_workflows/phase_fifteen_read_share_resume_test.exs",
    "W12": "packages/fount_workshop/test/writer_workflows/phase_fifteen_usefulness_test.exs",
}

SCENARIO_EVIDENCE = {
    "A01": "packages/fount_workshop/test/writer_workflows/phase_twelve_a01_demo_test.exs",
    "A02": "packages/fount_workshop/test/writer_workflows/phase_thirteen_pass_profiles_test.exs",
    "A03": "packages/fount_workshop/test/writer_workflows/phase_twelve_scene_exploration_test.exs",
    "A04": "packages/fount_workshop/test/writer_workflows/phase_thirteen_voice_test.exs",
    "A05": "packages/fount_workshop/test/writer_workflows/phase_thirteen_rehearsal_test.exs",
    "A06": "packages/fount_workshop/test/writer_workflows/phase_fourteen_notes_test.exs",
    "A07": "packages/fount_workshop/test/writer_workflows/phase_fourteen_consequence_test.exs",
    "A08": "packages/fount_workshop/test/writer_workflows/phase_fourteen_research_test.exs",
    "A09": "packages/fount_workshop/test/writer_workflows/phase_fifteen_read_share_resume_test.exs",
    "A10": "packages/fount_workshop/test/writer_workflows/phase_fifteen_read_share_resume_test.exs",
    "A11": "packages/fount_workshop/test/writer_workflows/phase_fifteen_read_share_resume_test.exs",
    "A12": "packages/fount_workshop/test/writer_workflows/phase_fifteen_usefulness_test.exs",
}


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def production_sources(package: str) -> list[Path]:
    return sorted((ROOT / "packages" / package / "lib").rglob("*.ex"))


def audit() -> dict:
    checks: list[dict] = []

    def check(name: str, ok: bool, detail: object) -> None:
        checks.append({"check": name, "status": "pass" if ok else "fail", "detail": detail})

    actual_packages = sorted(p.name for p in (ROOT / "packages").iterdir() if p.is_dir())
    check("exact_five_library_set", actual_packages == sorted(PACKAGES), actual_packages)

    present_old = [name for name in OLD_PACKAGES if (ROOT / "packages" / name).exists()]
    check("no_superseded_package_directories", not present_old, present_old)

    production = {name: production_sources(name) for name in PACKAGES}
    probe_hits = []
    old_name_hits = []
    for package, paths in production.items():
        for path in paths:
            text = path.read_text(encoding="utf-8")
            rel = path.relative_to(ROOT).as_posix()
            if "FountProbe" in text or "fount_probe" in text:
                probe_hits.append(rel)
            for old in OLD_PACKAGES[1:]:
                if old in text:
                    old_name_hits.append({"path": rel, "name": old})
    check("no_probe_production_references", not probe_hits, probe_hits)
    check("no_old_package_production_references", not old_name_hits, old_name_hits)

    sdk_hits = []
    inference_hits = []
    asm_hits = []
    for package, paths in production.items():
        for path in paths:
            text = path.read_text(encoding="utf-8")
            rel = path.relative_to(ROOT).as_posix()
            if "SystemOneSDK" in text and rel != "packages/fount_intelligence/lib/fount/intelligence/runner/architecture.ex":
                sdk_hits.append(rel)
            if "Inference." in text or "alias Inference" in text:
                inference_hits.append(rel)
            if "ASM." in text or "alias ASM" in text:
                asm_hits.append(rel)
    expected_sdk = ["packages/fount_observe/lib/fount/observe/providers/system_one.ex"]
    check("system_one_native_boundary", sdk_hits == expected_sdk, sdk_hits)
    check(
        "inference_native_boundary",
        all(path.startswith("packages/fount_workshop/lib/") for path in inference_hits),
        inference_hits,
    )
    check(
        "asm_not_used_as_analysis_boundary",
        all(path.startswith("packages/fount_workshop/lib/") for path in asm_hits),
        asm_hits,
    )

    mix_expectations = {
        "packages/fount/mix.exs": {":fount_observe": False, ":fount_intelligence": False, ":fount_workshop": False, ":fount_run": False, ":system_one_sdk": False, ":inference": False},
        "packages/fount_observe/mix.exs": {"system_one_dependency()": True, "workspace_dep(:fount": True, ":inference": False, ":fount_intelligence": False, ":fount_workshop": False},
        "packages/fount_intelligence/mix.exs": {"workspace_dep(:fount": True, "workspace_dep(:fount_observe": True, ":inference": False, ":fount_workshop": False},
        "packages/fount_workshop/mix.exs": {"workspace_dep(:fount": True, "workspace_dep(:fount_intelligence": True, '{:inference, "~> 0.5.0"}': True, '{:agent_session_manager, "~> 0.17.1"}': True, ":system_one_sdk": False, ":fount_observe": False, ":fount_run": False},
        "packages/fount_run/mix.exs": {"workspace_dep(:fount": True, "workspace_dep(:fount_workshop": True, ":system_one_sdk": False, ":inference": False, ":agent_session_manager": False},
    }
    mix_failures = []
    for path, expectations in mix_expectations.items():
        text = read(path)
        for token, expected in expectations.items():
            if (token in text) != expected:
                mix_failures.append({"path": path, "token": token, "expected_present": expected})
    check("declared_dependency_graph", not mix_failures, mix_failures)

    evidence_missing = [path for path in sorted(set(WORKFLOW_EVIDENCE.values()) | set(SCENARIO_EVIDENCE.values())) if not (ROOT / path).is_file()]
    check("w01_w12_and_a01_a12_evidence_paths", not evidence_missing, evidence_missing)

    matrix_path = ROOT / "packages/fount_workshop/examples/phase_sixteen/acceptance_matrix.json"
    matrix_failures = []
    try:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
        workflow_ids = {item.get("id") for item in matrix.get("workflows", [])}
        scenario_ids = {item.get("id") for item in matrix.get("scenarios", [])}
        expected_workflows = {f"W{i:02d}" for i in range(1, 13)}
        expected_scenarios = {f"A{i:02d}" for i in range(1, 13)}
        if workflow_ids != expected_workflows:
            matrix_failures.append({"workflow_ids": sorted(workflow_ids)})
        if scenario_ids != expected_scenarios:
            matrix_failures.append({"scenario_ids": sorted(scenario_ids)})
        allowed_statuses = {"NOT_RUN", "PASS", "PARTIAL", "FAIL"}
        if matrix.get("phase16_execution_status") not in allowed_statuses:
            matrix_failures.append({"phase16_execution_status": matrix.get("phase16_execution_status")})
        for item in matrix.get("workflows", []) + matrix.get("scenarios", []):
            for path in item.get("evidence_paths", []):
                if not (ROOT / path).is_file():
                    matrix_failures.append({"missing_evidence": path})
        for item in matrix.get("scenarios", []):
            if item.get("phase16_execution_status") not in allowed_statuses:
                matrix_failures.append({"scenario_status": item.get("id")})
            if not isinstance(item.get("source_revision"), str) or not item.get("source_revision"):
                matrix_failures.append({"source_revision": item.get("id")})
    except (OSError, json.JSONDecodeError) as exc:
        matrix_failures.append({"matrix_error": str(exc)})
    check("phase16_acceptance_matrix", not matrix_failures, matrix_failures)

    domain_assets = list((ROOT / "packages" / "fount_observe" / "priv" / "lenses").glob("*.json"))
    domain_assets += list((ROOT / "packages" / "fount_intelligence" / "priv").rglob("*.json"))
    numeric_asset_ids = []
    for path in domain_assets:
        text = path.read_text(encoding="utf-8")
        if '"id"' in text and (".v1\"" in text or ".v2\"" in text):
            numeric_asset_ids.append(path.relative_to(ROOT).as_posix())
    check("no_numeric_domain_asset_generations", not numeric_asset_ids, numeric_asset_ids)

    package_files_failures = []
    required_allowlist_tokens = {
        "packages/fount/mix.exs": ["lib", "priv", "guides", "assets", "examples"],
        "packages/fount_observe/mix.exs": ["lib", "priv", "guides", "assets", "examples"],
        "packages/fount_intelligence/mix.exs": ["lib", "priv", "guides", "assets", "examples"],
        "packages/fount_workshop/mix.exs": ["lib", "priv", "guides", "assets", "examples"],
        "packages/fount_run/mix.exs": ["lib", "priv", "guides"],
    }
    for path, tokens in required_allowlist_tokens.items():
        text = read(path)
        for token in tokens:
            if token not in text:
                package_files_failures.append({"path": path, "missing": token})
    check("hex_package_runtime_allowlists", not package_files_failures, package_files_failures)

    workshop_readme = read("packages/fount_workshop/README.md")
    root_readme = read("README.md")
    status_failures = []
    for stale in (
        "Phases 1–14 as applied/runtime-complete",
        "Phase 15 in this overlay is an offline source implementation pending Codex runtime repair/QC",
    ):
        if stale in workshop_readme:
            status_failures.append(stale)
    check("current_docs_not_stale_at_phase_15", not status_failures, status_failures)

    current_doc_paths = [ROOT / "README.md"]
    for package in PACKAGES:
        current_doc_paths.append(ROOT / "packages" / package / "README.md")
        current_doc_paths.extend((ROOT / "packages" / package / "guides").glob("*.md"))
        current_doc_paths.extend((ROOT / "packages" / package / "examples").rglob("*.md"))
    old_doc_hits = []
    for path in current_doc_paths:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for old in OLD_PACKAGES:
            if old in text or (old == "fount_probe" and "FountProbe" in text):
                old_doc_hits.append({"path": path.relative_to(ROOT).as_posix(), "name": old})
    check("current_docs_no_superseded_package_names", not old_doc_hits, old_doc_hits)

    check(
        "root_readme_declares_five_library_product",
        "five-library" in root_readme.lower() and all(name in root_readme for name in PACKAGES),
        "README five-library composition",
    )

    missing_phase16 = [
        path
        for path in (
            "packages/fount_workshop/guides/final-acceptance.md",
            "packages/fount_workshop/examples/phase_sixteen/README.md",
            "packages/fount_intelligence/test/phase_sixteen_final_architecture_test.exs",
        )
        if not (ROOT / path).is_file()
    ]
    check("phase16_final_acceptance_surfaces", not missing_phase16, missing_phase16)

    failures = [item for item in checks if item["status"] == "fail"]
    return {
        "status": "pass" if not failures else "fail",
        "mode": "source_only",
        "phase": 16,
        "checks": checks,
        "limitations": [
            "No Elixir/Mix/BEAM compilation or runtime behavior is executed by this script.",
            "No PostgreSQL, PDF, speech, provider, live-model, Hex build, or human study result is established.",
            "Scenario evidence paths are inventory/ownership checks; runtime QC must execute the actual ExUnit/integration demonstrations.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = audit()
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())