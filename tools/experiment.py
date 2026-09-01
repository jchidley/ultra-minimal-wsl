#!/usr/bin/env python3
"""Transactional query and update interface for the experiment inventory."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).parents[1]
DEFAULT_DB = ROOT / "inventory/experiments.sqlite"
SCHEMA_VERSION = 1
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
    if len(active) > 1:
        problems.append(f"multiple active operations: {[item['operation_id'] for item in active]}")
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
    for operation in active:
        roles = {row[0] for row in db.execute("SELECT role FROM operation_artifacts WHERE operation_id=?", (operation["operation_id"],))}
        required_roles = {
            "controller", "runner", "manifest", "kernel", "kernel_config", "package", "probe", "rootfs", "wpr",
            "broker", "broker_policy", "broker_installer", "broker_creator", "broker_launcher", "broker_client",
        }
        if roles != required_roles:
            problems.append(f"active operation artifact roles differ: missing={sorted(required_roles-roles)}, extra={sorted(roles-required_roles)}")
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


def prepare_operation(db: sqlite3.Connection, record: dict) -> None:
    require(record, ("operation_id", "kind", "status", "executable"))
    if record["executable"] and db.execute("SELECT 1 FROM active_operation").fetchone():
        raise SystemExit("An executable active operation already exists")
    controller = record.get("controller_artifact_id")
    db.execute(
        """INSERT INTO operations(
             operation_id,kind,candidate_id,trial_id,parent_operation_id,status,executable,
             controller_artifact_id,rationale,fixed_contract,runtime_boundary,prepared_utc)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            record["operation_id"], record["kind"], record.get("candidate_id"),
            record.get("trial_id"), record.get("parent_operation_id"), record["status"],
            int(bool(record["executable"])), controller, record.get("rationale", ""),
            record.get("fixed_contract", ""), record.get("runtime_boundary", ""),
            record.get("prepared_utc"),
        ),
    )
    artifacts = record.get("artifacts", [])
    if not isinstance(artifacts, list):
        raise SystemExit("Operation artifacts must be a list")
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise SystemExit("Each operation artifact link must be an object")
        link_artifact(
            db,
            {**artifact, "operation_id": record["operation_id"]},
            target="operation",
        )


def transition_operation(db: sqlite3.Connection, record: dict) -> None:
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
    finalize_trial(db, record["trial"])
    close_operation(db, record["operation"])


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


def logical_state(db: sqlite3.Connection) -> dict[str, list[dict]]:
    result = {}
    for table, order in (
        ("candidates", "candidate_id"), ("artifacts", "artifact_id"),
        ("operations", "operation_id"), ("operation_dispositions", "disposition_id"),
        ("trials", "trial_id"), ("configs", "name"),
    ):
        result[table] = rows(db, f"SELECT * FROM {table} ORDER BY {order}")
    return result


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
        keys = {
            "candidates": "candidate_id", "artifacts": "artifact_id", "operations": "operation_id",
            "operation_dispositions": "disposition_id", "trials": "trial_id", "configs": "name",
        }
        return {
            table: {"added": [row[keys[table]] for row in values], "removed": [], "changed": []}
            for table, values in after.items()
        }
    with tempfile.TemporaryDirectory() as directory:
        previous_path = Path(directory) / "experiments.sqlite"
        previous_path.write_bytes(process.stdout)
        previous = connect(previous_path)
        try:
            before = logical_state(previous)
        finally:
            previous.close()
    keys = {
        "candidates": "candidate_id", "artifacts": "artifact_id", "operations": "operation_id",
        "operation_dispositions": "disposition_id", "trials": "trial_id", "configs": "name",
    }
    summary = {}
    for table, values in after.items():
        key = keys[table]
        old = {row[key]: row for row in before[table]}
        new = {row[key]: row for row in values}
        common = old.keys() & new.keys()
        summary[table] = {
            "added": sorted(new.keys() - old.keys()),
            "removed": sorted(old.keys() - new.keys()),
            "changed": sorted(identifier for identifier in common if old[identifier] != new[identifier]),
        }
    return summary


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
        "artifact-add", "candidate-add", "config-add", "candidate-artifact-link",
        "operation-artifact-link", "operation-prepare", "operation-transition",
        "operation-close", "trial-finalize", "runtime-finalize",
    ):
        item = commands.add_parser(name)
        item.add_argument("--record", required=True)
    args = parser.parse_args()
    path = Path(args.db).resolve()
    writable = args.command in {
        "artifact-add", "candidate-add", "config-add", "candidate-artifact-link",
        "operation-artifact-link", "operation-prepare", "operation-transition",
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
            workload_id = value["operation_id"].rsplit("-", 1)[0]
            print(
                "& tools/fixture-broker/Start-FixtureBrokerRun.ps1 `\n"
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
                    "config-add": add_config,
                    "candidate-artifact-link": lambda connection, value: link_artifact(connection, value, target="candidate"),
                    "operation-artifact-link": lambda connection, value: link_artifact(connection, value, target="operation"),
                    "operation-prepare": prepare_operation,
                    "operation-transition": transition_operation,
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
