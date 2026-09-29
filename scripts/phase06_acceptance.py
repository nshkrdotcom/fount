#!/usr/bin/env python3
"""Offline Phase 06 source audit. Never reports runtime/browser/PDF success."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps" / "fount_web"
LIBRARIES = ("fount", "fount_observe", "fount_intelligence", "fount_workshop", "fount_run")
REQUIRED_APP = (
    "mix.exs",
    "config/config.exs",
    "config/runtime.exs",
    "lib/fount_web/application.ex",
    "lib/fount_web/owner_auth.ex",
    "lib/fount_web/live/project_live.ex",
    "lib/fount_web/live/run_live.ex",
    "lib/fount_web/controllers/artifact_controller.ex",
    "lib/fount_web/demo_adapter.ex",
    "lib/fount_web/worker_bootstrap.ex",
    "lib/mix/tasks/fount_web.migrate.ex",
    "priv/repo/migrations/20260929020000_create_fount_web_host_tables.exs",
    "browser/package.json",
    "browser/playwright.config.mjs",
    "browser/tests/phase06.spec.mjs",
)


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def audit() -> dict:
    checks: list[dict] = []

    def check(name: str, ok: bool, detail: object = None) -> None:
        checks.append({"check": name, "status": "pass" if ok else "fail", "detail": detail})

    missing = [rel for rel in REQUIRED_APP if not (APP / rel).is_file()]
    check("host_surface_complete", not missing, missing)

    root_mix = text(ROOT / "mix.exs")
    check("workspace_has_five_libraries_plus_host", all(f'"packages/{name}"' in root_mix for name in LIBRARIES) and '"apps/fount_web"' in root_mix)

    phoenix_hits = []
    for name in LIBRARIES:
        mix = text(ROOT / "packages" / name / "mix.exs")
        if "{:phoenix," in mix or "{:phoenix_live_view," in mix:
            phoenix_hits.append(name)
    check("library_packages_remain_phoenix_free", not phoenix_hits, phoenix_hits)

    router = text(APP / "lib/fount_web/router.ex")
    auth = text(APP / "lib/fount_web/owner_auth.ex")
    run_live = text(APP / "lib/fount_web/live/run_live.ex")
    artifact = text(APP / "lib/fount_web/controllers/artifact_controller.ex")
    launch = text(APP / "lib/fount_web/launch.ex")
    check("csrf_and_owner_pipeline", ":protect_from_forgery" in router and "require_owner" in router and "ensure_authenticated" in router)
    check("identity_from_signed_session_not_forms", "get_session(conn, :owner_id)" in auth and "ActorContext" not in run_live)
    check("exact_decision_binding_fields", all(token in run_live for token in ("context_fingerprint", "plan_version", "policy_version", "submit_decision")))
    check("durable_progress_not_socket_owned", "FountRun.progress" in run_live and "Process.send_after" in run_live and "Phoenix.PubSub.subscribe" in run_live)
    check("pause_resume_stop_surface", all(f'"{name}"' in run_live for name in ("pause", "resume", "stop")))
    project_live = text(APP / "lib/fount_web/live/project_live.ex")
    check("bounded_upload", "1_048_576" in project_live and "source_too_large" in launch)
    check("existing_accepted_base_can_start_successor_run", "create_from_project" in launch and "Persistence.load" in launch and "Use current accepted base" in project_live)
    check("setup_surfaces_plan_policy_and_unknown_estimate", all(token in run_live for token in ("Protected passages", "Effective limits and estimates", "Estimated cost: unknown")))
    check("decision_review_delivery_context_visible", all(token in run_live for token in ("Available choices and consequences", "Exact evidence binding", "Provenance and lineage", "Content identity")))
    check("artifact_path_and_checksum_revalidated", "Path.expand" in artifact and "outside_root" in artifact and "checksum" in artifact and "send_download" in artifact)

    migrate = text(APP / "lib/mix/tasks/fount_web.migrate.ex")
    positions = [migrate.find(token) for token in ("Fount.Persistence.migrations_path()", "FountRun.migrations_path()", "FountWeb.Migrations.path()")]
    check("migration_order_core_run_host", positions[0] >= 0 and positions == sorted(positions), positions)

    demo = text(APP / "lib/fount_web/demo_adapter.ex")
    journeys = text(APP / "lib/fount_web/journeys.ex")
    check("deterministic_demo_is_credential_free", "fount-phase06-demo-v1" in demo and '"credential" => "none"' in demo and 'cost: nil' in demo)
    check("three_demo_journeys", all(f'"{name}"' in journeys for name in ("opening", "reveal", "dialogue")) and "departure board" in journeys)

    package = json.loads(text(APP / "browser/package.json"))
    browser = text(APP / "browser/tests/phase06.spec.mjs")
    check("playwright_runner_pinned", package.get("devDependencies", {}).get("@playwright/test") == "1.63.0")
    check("browser_u01_u05_present", all(f"U{i:02d}" in browser for i in range(1, 6)))

    repomix = json.loads(text(ROOT / "repomix.config.json"))
    check("repomix_includes_apps", "apps/**" in repomix.get("include", []))

    ci = text(ROOT / ".github/workflows/ci.yml")
    check("ci_declares_host_runtime_gates", "mix fount_web.migrate" in ci and "playwright install" in ci and "run_phase06_browser.sh" in ci)

    failures = [item for item in checks if item["status"] == "fail"]
    return {
        "phase": 6,
        "mode": "offline_source_only",
        "status": "pass" if not failures else "fail",
        "checks": checks,
        "runtime": {
            "elixir": "NOT_RUN",
            "postgresql": "NOT_RUN",
            "application": "NOT_RUN",
            "pdf": "NOT_RUN",
            "browser": "NOT_RUN",
        },
    }


if __name__ == "__main__":
    report = audit()
    print(json.dumps(report, indent=2, sort_keys=True))
    raise SystemExit(0 if report["status"] == "pass" else 1)
