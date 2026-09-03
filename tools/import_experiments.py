#!/usr/bin/env python3
"""One-time migration from the v1 JSON/CSV records to experiments.sqlite."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).parents[1]
INVENTORY = ROOT / "inventory"
CONTROL = ROOT / "control-plane"
DB_PATH = INVENTORY / "experiments.sqlite"
SCHEMA_PATH = INVENTORY / "experiment-schema.sql"
PLAN_PATH = CONTROL / "deferred-runtime-plan.v1.json"
CONFIG_PATH = INVENTORY / "config-snapshots.v1.csv"
TRIAL_PATH = INVENTORY / "trials.v1.csv"
METADATA_PATH = INVENTORY / "trial-metadata.v1.csv"
CONTROLLER_PATH = Path.home() / "AppData/Local/ultra-minimal-wsl/approval-state/minimal-v6-k-overlay-pidns-runtime-013/Run-ControlledTrial.ps1"
TEMPLATES = {
    "controlled-runtime-v1": ROOT / "control-plane/contract-templates/controlled-runtime.v1.json",
    "debug-console-diagnostic-v1": ROOT / "control-plane/contract-templates/debug-console-diagnostic.v1.json",
    "legacy-migrated-runtime-v1": ROOT / "control-plane/contract-templates/legacy-migrated-runtime.v1.json",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        return [{key: value or "" for key, value in row.items()} for row in csv.DictReader(stream)]


def add_artifact(db: sqlite3.Connection, kind: str, location: str, path: str, digest: str,
                 size: int | None = None, product_code: str | None = None,
                 signature_state: str | None = None) -> int:
    cursor = db.execute(
        """INSERT INTO artifacts(kind,location,path,sha256,bytes,product_code,signature_state)
           VALUES (?,?,?,?,?,?,?)""",
        (kind, location, path, digest, size, product_code, signature_state),
    )
    return int(cursor.lastrowid)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--replace-canonical", action="store_true")
    args = parser.parse_args()
    output = Path(args.output).resolve()
    if output == DB_PATH.resolve() and not args.replace_canonical:
        raise SystemExit("Refusing to replace the canonical database without --replace-canonical")
    if output.exists():
        output.unlink()
    db = sqlite3.connect(output)
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    contract = plan["candidate_trial_contract"]["minimal_v6_k_overlay_pidns_001"]
    config_rows = csv_rows(CONFIG_PATH)
    trial_rows = csv_rows(TRIAL_PATH)
    metadata_rows = {row["trial_id"]: row for row in csv_rows(METADATA_PATH)}

    with db:
        for key, value in {
            "schema": "4",
            "migrated_from_plan": "control-plane/deferred-runtime-plan.v1.json",
            "migrated_plan_sha256": sha256(PLAN_PATH),
            "migrated_configs_sha256": sha256(CONFIG_PATH),
            "migrated_trials_sha256": sha256(TRIAL_PATH),
            "migrated_trial_metadata_sha256": sha256(METADATA_PATH),
        }.items():
            db.execute("INSERT INTO metadata VALUES (?,?)", (key, value))

        for template_id, path in TEMPLATES.items():
            db.execute(
                "INSERT INTO operation_templates VALUES (?,?,?)",
                (template_id, path.relative_to(ROOT).as_posix(), sha256(path)),
            )

        for row in config_rows:
            db.execute(
                "INSERT INTO configs VALUES (?,?,?,?,?)",
                (row["name"], row["path"], row["parent"] or None, row["sha256"], row["trial_id"] or None),
            )

        source_candidates = plan["source_candidates"]
        for candidate_id, value in source_candidates.items():
            db.execute(
                "INSERT INTO candidates VALUES (?,?,?,?,?)",
                (candidate_id, "control-plane-source", None, value.get("status", "historical"), value.get("rationale", "")),
            )
        for candidate_id, parent in (("K-PIDNS-001", None), ("K-OVERLAY-PIDNS-001", None)):
            db.execute("INSERT INTO candidates VALUES (?,?,?,?,?)", (candidate_id, "kernel", parent, "finalized", ""))
        for candidate_id, kernel in (
            ("minimal-v6-k-pidns-001", "K-PIDNS-001"),
            ("minimal-v6-k-overlay-pidns-001", "K-OVERLAY-PIDNS-001"),
        ):
            db.execute(
                "INSERT INTO candidates VALUES (?,?,?,?,?)",
                (candidate_id, "controlled-package-plus-external-kernel", "minimal-v6-excluded-initialize",
                 "finalized" if candidate_id.endswith("k-pidns-001") else "prepared",
                 f"Uses {kernel} with minimal-v6-excluded-initialize"),
            )

        artifact_ids: dict[str, int] = {}
        broker = contract["secure_broker"]
        artifact_specs = {
            "controller": ("controller", "host", str(CONTROLLER_PATH), sha256(CONTROLLER_PATH), CONTROLLER_PATH.stat().st_size, None, None),
            "runner": ("runner", "repository", contract["runner_path"], contract["runner_sha256"], None, None, None),
            "manifest": ("manifest", "repository", contract["candidate_manifest_path"], contract["candidate_manifest_sha256"], None, None, None),
            "kernel": ("kernel", "repository", contract["kernel_path"], contract["kernel_sha256"], contract["kernel_bytes"], None, None),
            "kernel_config": ("kernel-config", "repository", contract["kernel_config_path"], contract["kernel_config_sha256"], None, None, None),
            "package": ("package", "host", r"%LOCALAPPDATA%\ultra-minimal-wsl\controlled-outputs\minimal-v6-excluded-initialize\wsl.msi", contract["package_sha256"], contract["package_bytes"], contract["candidate_product_code"], "NotSigned"),
            "probe": ("probe", "repository", "tools/Invoke-WslCandidateProbe.ps1", contract["probe_sha256"], None, None, None),
            "rootfs": ("rootfs", "fixture", r"C:\controlled-inputs\ultra-minimal-wsl\toybox-minimal-wsl-rootfs.tar.gz", contract["rootfs_sha256"], None, None, None),
            "wpr": ("wpr-profile", "fixture", r"C:\controlled-inputs\ultra-minimal-wsl\diagnostics\wsl.wprp", contract["wpr_profile_sha256"], None, None, None),
            "broker": ("broker", "repository", broker["broker_path"], broker["broker_sha256"], None, None, None),
            "broker_policy": ("broker-policy", "repository", broker["policy_path"], broker["policy_sha256"], None, None, None),
            "broker_installer": ("broker-installer", "repository", broker["installer_path"], broker["installer_sha256"], None, None, None),
            "broker_creator": ("broker-run-creator", "repository", broker["run_creator_path"], broker["run_creator_sha256"], None, None, None),
            "broker_launcher": ("broker-run-launcher", "repository", broker["run_launcher_path"], broker["run_launcher_sha256"], None, None, None),
            "broker_client": ("broker-job-client", "repository", broker["job_client_path"], broker["job_client_sha256"], None, None, None),
        }
        for role, spec in artifact_specs.items():
            artifact_ids[role] = add_artifact(db, *spec)

        for role in ("runner", "manifest", "kernel", "kernel_config", "package"):
            db.execute(
                "INSERT INTO candidate_artifacts VALUES (?,?,?)",
                ("minimal-v6-k-overlay-pidns-001", artifact_ids[role], role),
            )

        operations = (
            ("minimal-v6-k-pidns-runtime-008", "minimal-v6-k-pidns-001", "CP-MINIMAL-V6-K-PIDNS-001", None, "infrastructure-failure", 0),
            ("minimal-v6-k-pidns-runtime-009", "minimal-v6-k-pidns-001", "CP-MINIMAL-V6-K-PIDNS-001", "minimal-v6-k-pidns-runtime-008", "infrastructure-failure", 0),
            ("minimal-v6-k-pidns-runtime-010", "minimal-v6-k-pidns-001", "CP-MINIMAL-V6-K-PIDNS-001", "minimal-v6-k-pidns-runtime-009", "superseded", 0),
            ("minimal-v6-k-pidns-runtime-011", "minimal-v6-k-pidns-001", "CP-MINIMAL-V6-K-PIDNS-001", "minimal-v6-k-pidns-runtime-010", "infrastructure-failure", 0),
            ("minimal-v6-k-pidns-runtime-012", "minimal-v6-k-pidns-001", "CP-MINIMAL-V6-K-PIDNS-001", "minimal-v6-k-pidns-runtime-011", "candidate-finalized", 0),
            ("minimal-v6-k-overlay-pidns-runtime-013", "minimal-v6-k-overlay-pidns-001", "CP-MINIMAL-V6-K-OVERLAY-PIDNS-001", "minimal-v6-k-pidns-runtime-012", "runtime-planned", 1),
        )
        for operation_id, candidate_id, trial_id, parent, status, executable in operations:
            active = operation_id.endswith("013")
            db.execute(
                """INSERT INTO operations(operation_id,kind,candidate_id,trial_id,parent_operation_id,status,
                   executable,controller_artifact_id,rationale,fixed_contract,runtime_boundary)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                (operation_id, "runtime", candidate_id, trial_id, parent, status, executable,
                 artifact_ids["controller"] if active else None,
                 contract["rationale"] if active else "",
                 contract["fixed_contract"] if active else "",
                 contract["runtime_boundary"] if active else ""),
            )
            db.execute(
                "INSERT INTO operation_template_bindings VALUES (?,?)",
                (operation_id, "controlled-runtime-v1" if active else "legacy-migrated-runtime-v1"),
            )
        dispositions = (
            ("minimal-v6-k-pidns-runtime-008", "infrastructure-failure", "UAC ended before worker start; fixture untouched."),
            ("minimal-v6-k-pidns-runtime-009", "infrastructure-failure", "UAC ended before worker start; fixture untouched."),
            ("minimal-v6-k-pidns-runtime-010", "superseded", "User-writable privileged controller and output boundary rejected before launch."),
            ("minimal-v6-k-pidns-runtime-011", "infrastructure-failure", "Protected child path was not preserved as one argument; no candidate probe began."),
            ("minimal-v6-k-pidns-runtime-012", "candidate-finalized", "Candidate finalized at B3; stock B6-T recovery passed and fixture returned Off."),
        )
        for operation_id, disposition, reason in dispositions:
            db.execute(
                "INSERT INTO operation_dispositions(operation_id,disposition,reason,recorded_utc) VALUES (?,?,?,?)",
                (operation_id, disposition, reason, "2026-09-01T03:24:00Z"),
            )
        for role, artifact_id in artifact_ids.items():
            db.execute("INSERT INTO operation_artifacts VALUES (?,?,?)", (operations[-1][0], artifact_id, role))

        ledger_fields = [
            "trial_id", "status", "started_utc", "finished_utc", "source_commit", "toolchain",
            "kernel_config_path", "kernel_config_sha256", "parent_trial", "change_group",
            "explicit_symbols", "autoselected_symbols", "kernel_image_path", "kernel_image_sha256",
            "boot_level", "toybox_result", "alpine_result", "arch_result", "debian_result", "failure_signature", "windows_error",
            "kernel_log_path", "crash_log_path", "classification", "stock_restore_verified", "notes",
        ]
        for row in trial_rows:
            meta = metadata_rows[row["trial_id"]]
            values = [
                row["trial_id"], row["status"], row["started_utc"], row["finished_utc"],
                row["source_commit"], row["toolchain"], row["kernel_config_path"], row["kernel_config_sha256"],
                meta["parent_trial"] or None, meta["config_name"] or None, meta["change_group"],
                meta["explicit_symbols"], meta["autoselected_symbols"], row["kernel_image_path"],
                row["kernel_image_sha256"], meta["boot_level"], row["toybox_result"], row["alpine_result"],
                row.get("arch_result", ""), row.get("debian_result", ""), row["failure_signature"], row["windows_error"],
                row["kernel_log_path"], row["crash_log_path"],
                row["classification"], row["stock_restore_verified"], meta["analysis_path"],
                meta["notes"], row["notes"],
            ]
            columns = [field for field in ledger_fields if field != "notes"]
            columns[columns.index("parent_trial"):columns.index("parent_trial") + 1] = ["parent_trial", "config_name"]
            columns.extend(["analysis_path", "metadata_notes", "ledger_notes"])
            db.execute(
                f"INSERT INTO trials ({','.join(columns)}) VALUES ({','.join('?' for _ in values)})",
                values,
            )

        if db.execute("SELECT 1 FROM trials WHERE trial_id='CP-MINIMAL-V6-K-PIDNS-001'").fetchone():
            db.execute(
                "INSERT INTO trial_operation_results VALUES (?,?)",
                ("CP-MINIMAL-V6-K-PIDNS-001", "minimal-v6-k-pidns-runtime-012"),
            )

    integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok":
        raise SystemExit(f"Integrity check failed: {integrity}")
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.execute("VACUUM")
    db.close()
    print(json.dumps({"database": str(output), "sha256": sha256(output), "integrity": integrity}, sort_keys=True))


if __name__ == "__main__":
    main()
