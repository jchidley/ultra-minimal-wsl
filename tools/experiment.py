#!/usr/bin/env python3
"""Transactional query and update interface for the experiment inventory."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parents[1]
DEFAULT_DB = ROOT / "inventory/experiments.sqlite"
SCHEMA_VERSION = 2
TERMINAL_OPERATION_STATES = {
    "completed", "candidate-finalized", "infrastructure-failure", "superseded", "cancelled"
}


def connect(path: Path, *, writable: bool = False) -> sqlite3.Connection:
    if not path.is_file():
        raise SystemExit(f"Experiment database is missing: {path}")
    uri = f"file:{path.as_posix()}?mode={'rw' if writable else 'ro'}"
    db = sqlite3.connect(uri, uri=True)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    if writable:
        db.execute("PRAGMA journal_mode=DELETE")
    return db


def rows(db: sqlite3.Connection, sql: str, values: tuple = ()) -> list[dict]:
    return [dict(row) for row in db.execute(sql, values)]


def print_json(value: object) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def resolve_path(value: str) -> Path:
    expanded = os.path.expandvars(value.replace("%LOCALAPPDATA%", os.environ.get("LOCALAPPDATA", "%LOCALAPPDATA%")))
    path = Path(expanded)
    return path if path.is_absolute() else ROOT / path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def merge_template(base: dict, delta: dict) -> dict:
    result = dict(base)
    for key, value in delta.items():
        if key in {"baseTemplate"}:
            continue
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge_template(result[key], value)
        else:
            result[key] = value
    return result


def load_templates(db: sqlite3.Connection) -> dict[str, dict]:
    raw: dict[str, dict] = {}
    for item in rows(db, "SELECT template_id,path,sha256 FROM operation_templates"):
        path = resolve_path(item["path"])
        if not path.is_file() or sha256(path) != item["sha256"]:
            raise SystemExit(f"Operation template identity mismatch: {path}")
        value = json.loads(path.read_text(encoding="utf-8"))
        if value.get("templateId") != item["template_id"]:
            raise SystemExit(f"Operation template ID mismatch: {path}")
        raw[item["template_id"]] = value

    resolved: dict[str, dict] = {}

    def resolve(template_id: str, stack: tuple[str, ...] = ()) -> dict:
        if template_id in resolved:
            return resolved[template_id]
        if template_id in stack or template_id not in raw:
            raise SystemExit(f"Invalid operation template ancestry: {template_id}")
        value = raw[template_id]
        parent = value.get("baseTemplate")
        result = merge_template(resolve(parent, stack + (template_id,)), value) if parent else dict(value)
        resolved[template_id] = result
        return result

    for template_id in raw:
        resolve(template_id)
    return resolved


def validate(db: sqlite3.Connection, *, verify_files: bool = True) -> dict:
    problems: list[str] = []
    version = db.execute("PRAGMA user_version").fetchone()[0]
    if version != SCHEMA_VERSION:
        problems.append(f"schema version is {version}, expected {SCHEMA_VERSION}")
    integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok":
        problems.append(f"integrity_check: {integrity}")
    foreign_keys = rows(db, "PRAGMA foreign_key_check")
    if foreign_keys:
        problems.append(f"foreign_key_check returned {len(foreign_keys)} row(s)")
    active = rows(db, "SELECT * FROM active_operation")
    executable = rows(db, "SELECT operation_id,status FROM operations WHERE executable=1")
    if len(executable) > 1:
        problems.append(f"multiple executable operations: {[item['operation_id'] for item in executable]}")
    if len(active) != len(executable):
        problems.append("an executable operation has a non-active lifecycle status")
    try:
        templates = load_templates(db)
    except SystemExit as error:
        problems.append(str(error))
        templates = {}
    unbound = rows(
        db,
        "SELECT operation_id FROM operations WHERE operation_id NOT IN "
        "(SELECT operation_id FROM operation_template_bindings)",
    )
    if unbound:
        problems.append(f"operations lack immutable templates: {[item['operation_id'] for item in unbound]}")
    parents = {row["candidate_id"]: row["parent_candidate_id"] for row in rows(db, "SELECT candidate_id,parent_candidate_id FROM candidates")}
    for candidate_id in parents:
        seen = {candidate_id}
        parent = parents[candidate_id]
        while parent:
            if parent in seen:
                problems.append(f"candidate lineage cycle includes {candidate_id}")
                break
            seen.add(parent)
            parent = parents.get(parent)
    allowed_statuses = {
        "prepared", "runtime-planned", "uac-requested", "worker-started", "probe-started",
        *TERMINAL_OPERATION_STATES,
    }
    for operation in rows(
        db,
        """SELECT o.operation_id,o.status,o.executable,count(d.disposition_id) disposition_count,
                  max(d.disposition) disposition
             FROM operations o LEFT JOIN operation_dispositions d USING(operation_id)
            GROUP BY o.operation_id""",
    ):
        if operation["status"] not in allowed_statuses:
            problems.append(f"unknown operation status: {operation['operation_id']}={operation['status']}")
        terminal = operation["status"] in TERMINAL_OPERATION_STATES
        if terminal and (operation["executable"] or operation["disposition_count"] != 1 or operation["disposition"] != operation["status"]):
            problems.append(f"terminal operation lifecycle mismatch: {operation['operation_id']}")
        if not terminal and operation["disposition_count"]:
            problems.append(f"nonterminal operation has disposition: {operation['operation_id']}")
    for result in rows(
        db,
        """SELECT r.trial_id,r.operation_id,o.status,o.trial_id intended_trial,o.first_probe_utc,b.template_id
             FROM trial_operation_results r JOIN operations o USING(operation_id)
             JOIN operation_template_bindings b USING(operation_id)""",
    ):
        missing_probe = not result["first_probe_utc"] and result["template_id"] != "legacy-migrated-runtime-v1"
        if result["status"] != "candidate-finalized" or result["intended_trial"] != result["trial_id"] or missing_probe:
            problems.append(f"trial-producing operation mismatch: {result['trial_id']}")
    missing_results = rows(
        db,
        """SELECT operation_id FROM operations
            WHERE status='candidate-finalized' AND operation_id NOT IN
                  (SELECT operation_id FROM trial_operation_results)""",
    )
    if missing_results:
        problems.append(f"finalized operations lack trial provenance: {[item['operation_id'] for item in missing_results]}")
    for operation in active:
        roles = {row[0] for row in db.execute("SELECT role FROM operation_artifacts WHERE operation_id=?", (operation["operation_id"],))}
        template = templates.get(operation["template_id"], {})
        required_roles = set(template.get("requiredArtifactRoles", []))
        if roles != required_roles:
            problems.append(f"active operation artifact roles differ: missing={sorted(required_roles-roles)}, extra={sorted(roles-required_roles)}")
        controller = db.execute(
            "SELECT artifact_id FROM operation_artifacts WHERE operation_id=? AND role='controller'",
            (operation["operation_id"],),
        ).fetchone()
        recorded = db.execute(
            "SELECT controller_artifact_id FROM operations WHERE operation_id=?",
            (operation["operation_id"],),
        ).fetchone()[0]
        if not controller or controller[0] != recorded:
            problems.append(f"active operation controller role differs: {operation['operation_id']}")
    frozen = {
        "migrated_plan_sha256": ROOT / "control-plane/deferred-runtime-plan.v1.json",
        "migrated_configs_sha256": ROOT / "inventory/config-snapshots.v1.csv",
        "migrated_trials_sha256": ROOT / "inventory/trials.v1.csv",
        "migrated_trial_metadata_sha256": ROOT / "inventory/trial-metadata.v1.csv",
    }
    metadata = dict(db.execute("SELECT key,value FROM metadata"))
    for key, path in frozen.items():
        if not path.is_file() or metadata.get(key) != sha256(path):
            problems.append(f"frozen migration identity mismatch: {path}")
    if verify_files:
        for artifact in rows(
            db,
            "SELECT artifact_id,location,path,sha256,bytes FROM artifacts WHERE location IN ('repository','host')",
        ):
            path = resolve_path(artifact["path"])
            if not path.is_file():
                problems.append(f"artifact {artifact['artifact_id']} is missing: {path}")
                continue
            if sha256(path) != artifact["sha256"]:
                problems.append(f"artifact {artifact['artifact_id']} hash mismatch: {path}")
            if artifact["bytes"] is not None and path.stat().st_size != artifact["bytes"]:
                problems.append(f"artifact {artifact['artifact_id']} size mismatch: {path}")
    database_path = Path(db.execute("PRAGMA database_list").fetchone()[2])
    for suffix in ("-wal", "-shm"):
        if Path(str(database_path) + suffix).exists():
            problems.append(f"uncheckpointed SQLite sidecar exists: {database_path.name}{suffix}")
    if problems:
        raise SystemExit("Experiment inventory validation failed:\n- " + "\n- ".join(problems))
    return {
        "integrity": integrity,
        "schemaVersion": version,
        "candidates": db.execute("SELECT count(*) FROM candidates").fetchone()[0],
        "artifacts": db.execute("SELECT count(*) FROM artifacts").fetchone()[0],
        "operations": db.execute("SELECT count(*) FROM operations").fetchone()[0],
        "trials": db.execute("SELECT count(*) FROM trials").fetchone()[0],
        "activeOperation": active[0]["operation_id"] if active else None,
    }


def read_record(path: str) -> dict:
    value = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise SystemExit("Record must be a JSON object")
    return value


def require(record: dict, names: tuple[str, ...]) -> None:
    missing = [name for name in names if name not in record]
    if missing:
        raise SystemExit(f"Record is missing fields: {missing}")


def add_artifact(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("kind", "location", "path", "sha256"))
    db.execute(
        """INSERT INTO artifacts(kind,location,path,sha256,bytes,product_code,signature_state)
           VALUES (?,?,?,?,?,?,?)""",
        (
            record["kind"], record["location"], record["path"], record["sha256"],
            record.get("bytes"), record.get("product_code"), record.get("signature_state"),
        ),
    )


def add_candidate(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("candidate_id", "kind", "status"))
    db.execute(
        "INSERT INTO candidates VALUES (?,?,?,?,?)",
        (
            record["candidate_id"], record["kind"], record.get("parent_candidate_id"),
            record["status"], record.get("rationale", ""),
        ),
    )


def add_operation_template(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("template_id", "path"))
    if set(record) != {"template_id", "path"}:
        raise SystemExit("Operation template records accept only template_id and path")
    supplied = Path(record["path"])
    if supplied.is_absolute() or ".." in supplied.parts:
        raise SystemExit("Operation template paths must be relative and remain under the repository root")
    path = resolve_path(record["path"])
    if not path.is_file():
        raise SystemExit(f"Operation template is missing: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("templateId") != record["template_id"]:
        raise SystemExit(f"Operation template ID mismatch: {path}")
    parent = value.get("baseTemplate")
    if parent and not db.execute("SELECT 1 FROM operation_templates WHERE template_id=?", (parent,)).fetchone():
        raise SystemExit(f"Operation template parent is not registered: {parent}")
    db.execute(
        "INSERT INTO operation_templates(template_id,path,sha256) VALUES (?,?,?)",
        (record["template_id"], record["path"], sha256(path)),
    )


def prepare_candidates(db: sqlite3.Connection, record: dict) -> None:
    """Record candidate lineage, new file identities, and all role links atomically."""
    require(record, ("candidates", "new_artifacts", "existing_artifacts"))
    if set(record) != {"candidates", "new_artifacts", "existing_artifacts"}:
        raise SystemExit("Candidate preparation accepts only candidates, new_artifacts, and existing_artifacts")
    if not all(isinstance(record[name], list) for name in ("candidates", "new_artifacts", "existing_artifacts")):
        raise SystemExit("Candidate preparation fields must be arrays")
    if not record["candidates"]:
        raise SystemExit("Candidate preparation requires at least one candidate")

    candidate_ids = [item.get("candidate_id") for item in record["candidates"]]
    if None in candidate_ids or len(candidate_ids) != len(set(candidate_ids)):
        raise SystemExit("Candidate preparation contains missing or duplicate candidate IDs")
    for candidate in record["candidates"]:
        allowed = {"candidate_id", "kind", "parent_candidate_id", "status", "rationale"}
        if set(candidate) - allowed:
            raise SystemExit(f"Unexpected candidate fields: {sorted(set(candidate)-allowed)}")
        add_candidate(db, candidate)

    links: set[tuple[str, str]] = set()
    for item in record["new_artifacts"]:
        require(item, ("candidate_id", "role", "kind", "location", "path"))
        if item["candidate_id"] not in candidate_ids:
            raise SystemExit(f"Artifact references an unprepared candidate: {item['candidate_id']}")
        allowed = {"candidate_id", "role", "kind", "location", "path", "product_code", "signature_state"}
        if unexpected := set(item) - allowed:
            raise SystemExit(f"Unexpected candidate artifact fields: {sorted(unexpected)}")
        if item["location"] not in {"repository", "host"}:
            raise SystemExit("New candidate artifacts must be accessible repository or host files")
        if item["location"] == "repository":
            supplied = Path(item["path"])
            if supplied.is_absolute() or ".." in supplied.parts:
                raise SystemExit("Repository artifact paths must be relative and remain under the repository root")
        key = (item["candidate_id"], item["role"])
        if key in links:
            raise SystemExit(f"Duplicate candidate artifact role: {key}")
        links.add(key)
        path = resolve_path(item["path"])
        if not path.is_file():
            raise SystemExit(f"Candidate artifact is missing: {path}")
        digest, size = sha256(path), path.stat().st_size
        duplicate = db.execute(
            "SELECT artifact_id,path FROM artifacts WHERE (location=? AND path=?) OR (sha256=? AND bytes=?)",
            (item["location"], item["path"], digest, size),
        ).fetchone()
        if duplicate:
            raise SystemExit(
                f"Artifact is not genuinely new; reuse artifact {duplicate['artifact_id']} ({duplicate['path']})"
            )
        artifact = dict(item)
        artifact.update({"sha256": digest, "bytes": size})
        artifact.pop("candidate_id")
        artifact.pop("role")
        add_artifact(db, artifact)
        artifact_id = db.execute("SELECT last_insert_rowid()").fetchone()[0]
        db.execute(
            "INSERT INTO candidate_artifacts VALUES (?,?,?)",
            (item["candidate_id"], artifact_id, item["role"]),
        )

    for item in record["existing_artifacts"]:
        require(item, ("candidate_id", "artifact_id", "role"))
        if set(item) != {"candidate_id", "artifact_id", "role"}:
            raise SystemExit("Existing candidate artifact links accept only candidate_id, artifact_id, and role")
        if item["candidate_id"] not in candidate_ids:
            raise SystemExit(f"Artifact references an unprepared candidate: {item['candidate_id']}")
        key = (item["candidate_id"], item["role"])
        if key in links:
            raise SystemExit(f"Duplicate candidate artifact role: {key}")
        links.add(key)
        db.execute(
            "INSERT INTO candidate_artifacts VALUES (?,?,?)",
            (item["candidate_id"], item["artifact_id"], item["role"]),
        )


def add_config(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("name", "path", "sha256"))
    path = resolve_path(record["path"])
    if not path.is_file() or sha256(path) != record["sha256"]:
        raise SystemExit(f"Configuration identity mismatch: {path}")
    db.execute(
        "INSERT INTO configs VALUES (?,?,?,?,?)",
        (record["name"], record["path"], record.get("parent"), record["sha256"], record.get("trial_id")),
    )


def link_artifact(db: sqlite3.Connection, record: dict, *, target: str) -> None:
    require(record, ("artifact_id", "role"))
    if target == "candidate":
        require(record, ("candidate_id",))
        db.execute("INSERT INTO candidate_artifacts VALUES (?,?,?)", (record["candidate_id"], record["artifact_id"], record["role"]))
    else:
        require(record, ("operation_id",))
        db.execute("INSERT INTO operation_artifacts VALUES (?,?,?)", (record["operation_id"], record["artifact_id"], record["role"]))


def ensure_no_active_operation(db: sqlite3.Connection) -> None:
    if db.execute("SELECT 1 FROM operations WHERE executable=1").fetchone():
        raise SystemExit("An executable active operation already exists")


def derive_operation(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("operation_id", "parent_operation_id", "candidate_id", "trial_id", "rationale", "prepared_utc"))
    ensure_no_active_operation(db)
    forbidden = {"artifacts", "fixed_contract", "runtime_boundary", "controller_artifact_id"} & record.keys()
    if forbidden:
        raise SystemExit(f"Derived operations must reference inherited state, not respecify it: {sorted(forbidden)}")
    parent = db.execute("SELECT * FROM operations WHERE operation_id=?", (record["parent_operation_id"],)).fetchone()
    if not parent or parent["status"] not in TERMINAL_OPERATION_STATES:
        raise SystemExit("A derived operation requires a terminal parent operation")
    parent_template = db.execute(
        "SELECT template_id FROM operation_template_bindings WHERE operation_id=?",
        (record["parent_operation_id"],),
    ).fetchone()
    template_id = record.get("template_id", parent_template[0] if parent_template else None)
    templates = load_templates(db)
    if template_id not in templates:
        raise SystemExit(f"Unknown operation template: {template_id}")
    artifact_map = dict(db.execute(
        "SELECT role,artifact_id FROM operation_artifacts WHERE operation_id=?",
        (record["parent_operation_id"],),
    ))
    replacements = record.get("replace_artifacts", {})
    if not isinstance(replacements, dict):
        raise SystemExit("replace_artifacts must be an object mapping roles to artifact IDs")
    artifact_map.update({role: int(artifact_id) for role, artifact_id in replacements.items()})
    required = set(templates[template_id].get("requiredArtifactRoles", []))
    if set(artifact_map) != required:
        raise SystemExit(
            f"Derived artifact roles differ from template: missing={sorted(required-set(artifact_map))}, "
            f"extra={sorted(set(artifact_map)-required)}"
        )
    controller = artifact_map.get("controller")
    fixed_contract = json.dumps(templates[template_id].get("invariants", {}), sort_keys=True, separators=(",", ":"))
    db.execute(
        """INSERT INTO operations(
             operation_id,kind,candidate_id,trial_id,parent_operation_id,status,executable,
             controller_artifact_id,rationale,fixed_contract,runtime_boundary,prepared_utc)
           VALUES (?,?,?,?,?,'runtime-planned',1,?,?,?,?,?)""",
        (
            record["operation_id"], templates[template_id]["kind"], record["candidate_id"],
            record["trial_id"], record["parent_operation_id"], controller, record["rationale"],
            fixed_contract, templates[template_id]["runtimeBoundary"], record["prepared_utc"],
        ),
    )
    db.execute("INSERT INTO operation_template_bindings VALUES (?,?)", (record["operation_id"], template_id))
    db.executemany(
        "INSERT INTO operation_artifacts VALUES (?,?,?)",
        ((record["operation_id"], artifact_id, role) for role, artifact_id in sorted(artifact_map.items())),
    )


def retry_operation(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("operation_id", "after_operation_id", "reason", "prepared_utc"))
    ensure_no_active_operation(db)
    forbidden = {"artifacts", "replace_artifacts", "template_id", "candidate_id", "trial_id", "fixed_contract"} & record.keys()
    if forbidden:
        raise SystemExit(f"Retries may not reconstruct contract state: {sorted(forbidden)}")
    source = db.execute("SELECT * FROM operations WHERE operation_id=?", (record["after_operation_id"],)).fetchone()
    if not source or source["status"] not in {"infrastructure-failure", "cancelled"}:
        raise SystemExit("A retry requires a failed or cancelled pre-result attempt")
    template_id = db.execute(
        "SELECT template_id FROM operation_template_bindings WHERE operation_id=?",
        (record["after_operation_id"],),
    ).fetchone()
    if not template_id:
        raise SystemExit("Retry source has no immutable operation template")
    db.execute(
        """INSERT INTO operations(
             operation_id,kind,candidate_id,trial_id,parent_operation_id,status,executable,
             controller_artifact_id,rationale,fixed_contract,runtime_boundary,prepared_utc)
           VALUES (?,?,?,?,?,'runtime-planned',1,?,?,?,?,?)""",
        (
            record["operation_id"], source["kind"], source["candidate_id"], source["trial_id"],
            source["operation_id"], source["controller_artifact_id"], record["reason"],
            source["fixed_contract"], source["runtime_boundary"], record["prepared_utc"],
        ),
    )
    db.execute("INSERT INTO operation_template_bindings VALUES (?,?)", (record["operation_id"], template_id[0]))
    db.execute(
        """INSERT INTO operation_artifacts(operation_id,artifact_id,role)
           SELECT ?,artifact_id,role FROM operation_artifacts WHERE operation_id=?""",
        (record["operation_id"], source["operation_id"]),
    )


INVARIANT_TEST_MODULES = (
    "tools.test_build_host_profile",
    "tools.test_experiment",
    "tools.test_inventory_records",
    "tools.test_extract_guest_logs",
    "tools.test_process_commit",
    "tools.test_control_plane_protocol",
    "tools.test_control_plane_records",
    "tools.test_fixture_broker",
)


def run_invariant_suite(database_path: Path) -> None:
    environment = dict(os.environ)
    environment["EXPERIMENT_TEST_DB"] = str(database_path)
    environment["EXPERIMENT_PREFLIGHT_CHILD"] = "1"
    result = subprocess.run(
        [sys.executable, "-m", "unittest", *INVARIANT_TEST_MODULES],
        cwd=ROOT,
        env=environment,
    )
    if result.returncode:
        raise SystemExit("Invariant test suite failed; refusing UAC transition")


def request_uac(
    db: sqlite3.Connection,
    record: dict,
    *,
    suite_runner=run_invariant_suite,
) -> None:
    database_path = Path(db.execute("PRAGMA database_list").fetchone()[2])
    suite_runner(database_path)
    validate(db)
    transition_operation(db, record, preflight_passed=True)


def transition_operation(db: sqlite3.Connection, record: dict, *, preflight_passed: bool = False) -> None:
    require(record, ("operation_id", "status"))
    transitions = {
        "runtime-planned": "uac-requested",
        "prepared": "uac-requested",
        "uac-requested": "worker-started",
        "worker-started": "probe-started",
    }
    current = db.execute("SELECT status FROM operations WHERE operation_id=?", (record["operation_id"],)).fetchone()
    if not current:
        raise SystemExit(f"Unknown operation: {record['operation_id']}")
    if transitions.get(current[0]) != record["status"]:
        raise SystemExit(f"Invalid operation transition: {current[0]} -> {record['status']}")
    if record["status"] == "uac-requested" and not preflight_passed:
        raise SystemExit("Use operation-request-uac so the invariant suite runs immediately before transition")
    field = {
        "uac-requested": "uac_requested_utc",
        "worker-started": "worker_started_utc",
        "probe-started": "first_probe_utc",
    }[record["status"]]
    require(record, (field,))
    db.execute(f"UPDATE operations SET status=?,{field}=? WHERE operation_id=?", (record["status"], record[field], record["operation_id"]))


def finalize_trial(db: sqlite3.Connection, record: dict) -> None:
    fields = (
        "trial_id", "status", "started_utc", "finished_utc", "source_commit", "toolchain",
        "kernel_config_path", "kernel_config_sha256", "parent_trial", "config_name", "change_group",
        "explicit_symbols", "autoselected_symbols", "kernel_image_path", "kernel_image_sha256",
        "boot_level", "toybox_result", "alpine_result", "failure_signature", "windows_error",
        "kernel_log_path", "crash_log_path", "classification", "stock_restore_verified",
        "analysis_path", "metadata_notes", "ledger_notes",
    )
    require(record, fields)
    analysis = record["analysis_path"]
    if analysis:
        path = resolve_path(analysis)
        if not path.is_file() or json.loads(path.read_text(encoding="utf-8-sig")).get("trialId") != record["trial_id"]:
            raise SystemExit(f"Trial analysis identity mismatch: {path}")
    db.execute(f"INSERT INTO trials VALUES ({','.join('?' for _ in fields)})", tuple(record[name] or None if name in {"parent_trial", "config_name"} else record[name] for name in fields))


def finalize_runtime(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("trial", "operation"))
    if not isinstance(record["trial"], dict) or not isinstance(record["operation"], dict):
        raise SystemExit("runtime-finalize requires trial and operation objects")
    if record["trial"].get("trial_id") != record["operation"].get("trial_id"):
        raise SystemExit("Runtime trial and operation trial IDs differ")
    operation = db.execute(
        "SELECT status,trial_id FROM operations WHERE operation_id=?",
        (record["operation"].get("operation_id"),),
    ).fetchone()
    if not operation or operation["status"] != "probe-started" or operation["trial_id"] != record["trial"]["trial_id"]:
        raise SystemExit("A runtime trial requires its producing operation at probe-started")
    finalize_trial(db, record["trial"])
    close_operation(db, record["operation"])
    db.execute(
        "INSERT INTO trial_operation_results VALUES (?,?)",
        (record["trial"]["trial_id"], record["operation"]["operation_id"]),
    )


def close_operation(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("operation_id", "status", "disposition", "reason", "recorded_utc"))
    if record["status"] not in TERMINAL_OPERATION_STATES:
        raise SystemExit(f"Not a terminal operation status: {record['status']}")
    current = db.execute("SELECT status FROM operations WHERE operation_id=?", (record["operation_id"],)).fetchone()
    if not current:
        raise SystemExit(f"Unknown operation: {record['operation_id']}")
    db.execute(
        "UPDATE operations SET status=?,executable=0,completed_utc=? WHERE operation_id=?",
        (record["status"], record.get("completed_utc", record["recorded_utc"]), record["operation_id"]),
    )
    db.execute(
        "INSERT INTO operation_dispositions(operation_id,disposition,reason,recorded_utc) VALUES (?,?,?,?)",
        (record["operation_id"], record["disposition"], record["reason"], record["recorded_utc"]),
    )


STATE_TABLES = (
    ("metadata", ("key",)),
    ("candidates", ("candidate_id",)),
    ("artifacts", ("artifact_id",)),
    ("candidate_artifacts", ("candidate_id", "role")),
    ("operations", ("operation_id",)),
    ("operation_artifacts", ("operation_id", "role")),
    ("operation_templates", ("template_id",)),
    ("operation_template_bindings", ("operation_id",)),
    ("operation_dispositions", ("disposition_id",)),
    ("trials", ("trial_id",)),
    ("trial_operation_results", ("trial_id",)),
    ("configs", ("name",)),
)


def logical_state(db: sqlite3.Connection) -> dict[str, list[dict]]:
    result = {}
    existing = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for table, keys in STATE_TABLES:
        result[table] = rows(db, f"SELECT * FROM {table} ORDER BY {','.join(keys)}") if table in existing else []
    return result


def row_id(row: dict, keys: tuple[str, ...]) -> str:
    return "|".join(str(row[key]) for key in keys)


def logical_diff(before: dict[str, list[dict]], after: dict[str, list[dict]]) -> dict:
    summary = {}
    key_map = dict(STATE_TABLES)
    for table, values in after.items():
        keys = key_map[table]
        old = {row_id(row, keys): row for row in before.get(table, [])}
        new = {row_id(row, keys): row for row in values}
        changed = {}
        for identifier in sorted(old.keys() & new.keys()):
            fields = {
                field: {"before": old[identifier].get(field), "after": new[identifier].get(field)}
                for field in sorted(old[identifier].keys() | new[identifier].keys())
                if old[identifier].get(field) != new[identifier].get(field)
            }
            if fields:
                changed[identifier] = fields
        summary[table] = {
            "added": sorted(new.keys() - old.keys()),
            "removed": sorted(old.keys() - new.keys()),
            "changed": changed,
        }
    return summary


def diff_head(path: Path) -> dict:
    current = connect(path)
    try:
        after = logical_state(current)
    finally:
        current.close()
    process = subprocess.run(
        ["git", "show", f"HEAD:{path.relative_to(ROOT).as_posix()}"],
        cwd=ROOT, capture_output=True,
    )
    if process.returncode != 0:
        return logical_diff({table: [] for table in after}, after)
    with tempfile.TemporaryDirectory() as directory:
        previous_path = Path(directory) / "experiments.sqlite"
        previous_path.write_bytes(process.stdout)
        previous = connect(previous_path)
        try:
            before = logical_state(previous)
        finally:
            previous.close()
    return logical_diff(before, after)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(DEFAULT_DB))
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("active")
    commands.add_parser("validate")
    commands.add_parser("diff-head")
    broker = commands.add_parser("broker-command")
    broker.add_argument("operation_id")
    show = commands.add_parser("show")
    show.add_argument("kind", choices=("candidate", "operation", "trial"))
    show.add_argument("identifier")
    contract = commands.add_parser("contract")
    contract.add_argument("operation_id")
    query = commands.add_parser("query")
    query.add_argument("sql")
    for name in (
        "artifact-add", "candidate-add", "candidate-prepare", "config-add", "candidate-artifact-link",
        "operation-template-add", "operation-derive", "operation-retry", "operation-transition", "operation-request-uac",
        "operation-close", "trial-finalize", "runtime-finalize",
    ):
        item = commands.add_parser(name)
        item.add_argument("--record", required=True)
    args = parser.parse_args()
    path = Path(args.db).resolve()
    writable = args.command in {
        "artifact-add", "candidate-add", "candidate-prepare", "config-add", "candidate-artifact-link",
        "operation-template-add", "operation-derive", "operation-retry", "operation-transition", "operation-request-uac",
        "operation-close", "trial-finalize", "runtime-finalize",
    }
    db = connect(path, writable=writable)
    try:
        if args.command == "active":
            print_json(rows(db, "SELECT * FROM active_operation"))
        elif args.command == "validate":
            print_json(validate(db))
        elif args.command == "diff-head":
            print_json(diff_head(path))
        elif args.command == "broker-command":
            operation = rows(db, "SELECT * FROM active_operation WHERE operation_id=?", (args.operation_id,))
            if len(operation) != 1:
                raise SystemExit(f"Operation is not active: {args.operation_id}")
            value = operation[0]
            launchers = rows(
                db,
                """SELECT a.path FROM operation_artifacts oa
                   JOIN artifacts a USING(artifact_id)
                   WHERE oa.operation_id=? AND oa.role='broker_launcher'""",
                (args.operation_id,),
            )
            if len(launchers) != 1:
                raise SystemExit(f"Operation must bind exactly one broker_launcher: {args.operation_id}")
            launcher_path = launchers[0]["path"].replace("'", "''")
            workload_id = value["operation_id"].rsplit("-", 1)[0]
            print(
                f"& '{launcher_path}' `\n"
                f"  -RunId {value['operation_id']} `\n"
                f"  -WorkloadId {workload_id} `\n"
                f"  -WorkloadPath '{value['controller_path']}' `\n"
                f"  -WorkloadSha256 {value['controller_sha256']} `\n"
                "  -Confirmed"
            )
        elif args.command == "show":
            table, key = {"candidate": ("candidates", "candidate_id"), "operation": ("operations", "operation_id"), "trial": ("trials", "trial_id")}[args.kind]
            print_json(rows(db, f"SELECT * FROM {table} WHERE {key}=?", (args.identifier,)))
        elif args.command == "query":
            statement = args.sql.strip()
            if not statement.lower().startswith(("select ", "with ", "pragma ")) or ";" in statement.rstrip(";"):
                raise SystemExit("query accepts exactly one read-only SELECT, WITH, or PRAGMA statement")
            print_json(rows(db, statement))
        elif args.command == "contract":
            operation = rows(db, "SELECT * FROM active_operation WHERE operation_id=?", (args.operation_id,))
            if len(operation) != 1:
                raise SystemExit(f"Operation is not active: {args.operation_id}")
            operation[0]["template"] = load_templates(db)[operation[0]["template_id"]]
            operation[0]["artifacts"] = rows(
                db,
                """SELECT oa.role,a.kind,a.location,a.path,a.sha256,a.bytes,a.product_code,a.signature_state
                   FROM operation_artifacts oa JOIN artifacts a USING(artifact_id)
                   WHERE oa.operation_id=? ORDER BY oa.role""",
                (args.operation_id,),
            )
            print_json(operation[0])
        else:
            record = read_record(args.record)
            with db:
                actions = {
                    "artifact-add": add_artifact,
                    "candidate-add": add_candidate,
                    "candidate-prepare": prepare_candidates,
                    "config-add": add_config,
                    "candidate-artifact-link": lambda connection, value: link_artifact(connection, value, target="candidate"),
                    "operation-template-add": add_operation_template,
                    "operation-derive": derive_operation,
                    "operation-retry": retry_operation,
                    "operation-transition": transition_operation,
                    "operation-request-uac": request_uac,
                    "operation-close": close_operation,
                    "trial-finalize": finalize_trial,
                    "runtime-finalize": finalize_runtime,
                }
                actions[args.command](db, record)
                validate(db)
            db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            print_json({"updated": args.command, "record": args.record})
    finally:
        db.close()


if __name__ == "__main__":
    main()
