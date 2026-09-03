#!/usr/bin/env python3
"""Synchronize config snapshots and immutable trial evidence into the inventory DB."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sqlite3
import tempfile
from pathlib import Path

CONFIG_FIELDS = ("name", "path", "parent", "sha256", "trial_id")
TRIAL_METADATA_FIELDS = (
    "trial_id", "parent_trial", "config_name", "change_group",
    "explicit_symbols", "autoselected_symbols", "boot_level",
    "analysis_path", "notes",
)
CONFIG_SET = re.compile(r"^CONFIG_([A-Za-z0-9_]+)=(.*)$")
CONFIG_UNSET = re.compile(r"^# CONFIG_([A-Za-z0-9_]+) is not set$")


def read_rows(path: Path, required: tuple[str, ...]) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        missing = set(required) - set(reader.fieldnames or ())
        if missing:
            raise SystemExit(f"{path} is missing columns: {sorted(missing)}")
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_config(path: Path, symbol_types: dict[str, str]) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = CONFIG_SET.match(line)
        if match:
            symbol, value = match.groups()
        else:
            match = CONFIG_UNSET.match(line)
            if not match:
                continue
            symbol, value = match.group(1), "n"
        if symbol in symbol_types:
            if symbol_types[symbol] == "string" and value.startswith('"'):
                value = json.loads(value)
            values[symbol] = value
    return values


def sync_configs(db: sqlite3.Connection, manifest: Path, root: Path) -> None:
    rows = read_rows(manifest, CONFIG_FIELDS)
    names = [row["name"] for row in rows]
    if len(names) != len(set(names)):
        raise SystemExit(f"{manifest} contains duplicate config names")

    db.execute("DROP TABLE IF EXISTS config_snapshot_metadata")
    db.execute(
        """CREATE TABLE config_snapshot_metadata(
               name TEXT PRIMARY KEY REFERENCES configs(name),
               path TEXT NOT NULL, parent TEXT NOT NULL, sha256 TEXT NOT NULL,
               trial_id TEXT NOT NULL)"""
    )
    symbol_types = dict(db.execute("SELECT name,type FROM symbols"))
    known = set(symbol_types)

    for row in rows:
        path = (root / row["path"]).resolve()
        if not path.is_file():
            raise SystemExit(f"Missing config snapshot: {row['path']}")
        actual_hash = sha256(path)
        if actual_hash != row["sha256"].lower():
            raise SystemExit(
                f"Config hash mismatch for {row['name']}: {actual_hash} != {row['sha256']}"
            )

        exists = db.execute("SELECT 1 FROM configs WHERE name=?", (row["name"],)).fetchone()
        parent = row["parent"]
        if exists:
            db.execute("UPDATE configs SET path=? WHERE name=?", (row["path"], row["name"]))
        else:
            if not parent:
                raise SystemExit(
                    f"Base config {row['name']} is absent; run the full Kconfig rebuild"
                )
            db.execute("INSERT INTO configs(name,path) VALUES (?,?)", (row["name"], row["path"]))

        if parent:
            if not db.execute("SELECT 1 FROM configs WHERE name=?", (parent,)).fetchone():
                raise SystemExit(f"Config {row['name']} needs existing parent {parent}")
            db.execute("DELETE FROM config_values WHERE config_name=?", (row["name"],))
            db.execute(
                """INSERT INTO config_values(config_name,symbol,value)
                   SELECT ?,symbol,value FROM config_values WHERE config_name=?""",
                (row["name"], parent),
            )
        for symbol, value in parse_config(path, symbol_types).items():
            db.execute(
                "UPDATE config_values SET value=? WHERE config_name=? AND symbol=?",
                (value, row["name"], symbol),
            )

        value_count = db.execute(
            "SELECT count(*) FROM config_values WHERE config_name=?", (row["name"],)
        ).fetchone()[0]
        if value_count != len(known):
            raise SystemExit(
                f"Config {row['name']} has {value_count} values; expected {len(known)}"
            )
        db.execute(
            "INSERT INTO config_snapshot_metadata VALUES (?,?,?,?,?)",
            (row["name"], row["path"], row["parent"], actual_hash, row["trial_id"]),
        )


def sync_trials(
    db: sqlite3.Connection, ledger: Path, metadata: Path, root: Path
) -> None:
    with ledger.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        ledger_fields = tuple(reader.fieldnames or ())
        ledger_rows = list(reader)
    if "trial_id" not in ledger_fields:
        raise SystemExit(f"{ledger} has no trial_id column")
    ids = [row["trial_id"] for row in ledger_rows]
    if len(ids) != len(set(ids)):
        raise SystemExit(f"{ledger} contains duplicate trial IDs")

    metadata_rows = read_rows(metadata, TRIAL_METADATA_FIELDS)
    metadata_ids = [row["trial_id"] for row in metadata_rows]
    if set(metadata_ids) != set(ids) or len(metadata_ids) != len(set(metadata_ids)):
        raise SystemExit("Trial metadata must contain exactly one row for every ledger trial")
    parents = {row["trial_id"]: row["parent_trial"] for row in metadata_rows}
    for trial_id, parent in parents.items():
        if parent and (parent not in parents or parent == trial_id):
            raise SystemExit(f"Invalid parent {parent!r} for trial {trial_id}")
        seen = {trial_id}
        while parent:
            if parent in seen:
                raise SystemExit(f"Trial parent cycle includes {trial_id}")
            seen.add(parent)
            parent = parents[parent]

    db.execute("DROP VIEW IF EXISTS trial_inventory")
    db.execute("DROP TABLE IF EXISTS trial_metadata")
    db.execute("DROP TABLE IF EXISTS trial_ledger")
    quoted = ",".join(f'"{field}" TEXT NOT NULL' for field in ledger_fields)
    db.execute(f"CREATE TABLE trial_ledger({quoted}, PRIMARY KEY(trial_id))")
    placeholders = ",".join("?" for _ in ledger_fields)
    db.executemany(
        f"INSERT INTO trial_ledger VALUES ({placeholders})",
        ([row.get(field, "") for field in ledger_fields] for row in ledger_rows),
    )
    db.execute(
        """CREATE TABLE trial_metadata(
               trial_id TEXT PRIMARY KEY REFERENCES trial_ledger(trial_id),
               parent_trial TEXT NOT NULL, config_name TEXT NOT NULL,
               change_group TEXT NOT NULL, explicit_symbols TEXT NOT NULL,
               autoselected_symbols TEXT NOT NULL, boot_level TEXT NOT NULL,
               analysis_path TEXT NOT NULL, notes TEXT NOT NULL)"""
    )
    for row in metadata_rows:
        analysis_path = row["analysis_path"]
        if analysis_path:
            analysis = (root / analysis_path).resolve()
            if not analysis.is_file():
                raise SystemExit(f"Missing analysis for {row['trial_id']}: {analysis_path}")
            content = json.loads(analysis.read_text(encoding="utf-8-sig"))
            if content.get("trialId") != row["trial_id"]:
                raise SystemExit(f"Analysis trialId mismatch: {analysis_path}")
        if row["config_name"] and not db.execute(
            "SELECT 1 FROM configs WHERE name=?", (row["config_name"],)
        ).fetchone():
            raise SystemExit(
                f"Unknown config {row['config_name']} for trial {row['trial_id']}"
            )
        db.execute(
            "INSERT INTO trial_metadata VALUES (?,?,?,?,?,?,?,?,?)",
            tuple(row[field] for field in TRIAL_METADATA_FIELDS),
        )

    db.execute(
        """CREATE VIEW trial_inventory AS
           SELECT l.trial_id,l.status,l.started_utc,l.finished_utc,
                  l.source_commit,l.toolchain,
                  coalesce(nullif(m.config_name,''),'') AS config_name,
                  l.kernel_config_path,l.kernel_config_sha256,
                  m.parent_trial,m.change_group,m.explicit_symbols,
                  m.autoselected_symbols,l.kernel_image_path,l.kernel_image_sha256,
                  m.boot_level,
                  l.toybox_result,l.alpine_result,l.arch_result,l.failure_signature,l.windows_error,
                  l.kernel_log_path,l.crash_log_path,l.classification,
                  l.stock_restore_verified,m.analysis_path,m.notes AS metadata_notes,
                  l.notes AS ledger_notes
             FROM trial_ledger l JOIN trial_metadata m USING(trial_id)"""
    )


def export_experiment_records(experiments: Path, directory: Path) -> tuple[Path, Path, Path]:
    """Materialize legacy-shaped inputs from the committed canonical database."""
    source = sqlite3.connect(f"file:{experiments.resolve().as_posix()}?mode=ro", uri=True)
    source.row_factory = sqlite3.Row
    try:
        configs = directory / "configs.csv"
        trials = directory / "trials.csv"
        metadata = directory / "trial-metadata.csv"
        with configs.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=CONFIG_FIELDS)
            writer.writeheader()
            for row in source.execute("SELECT name,path,coalesce(parent,'') parent,sha256,coalesce(trial_id,'') trial_id FROM configs ORDER BY name"):
                writer.writerow(dict(row))
        ledger_fields = [
            "trial_id", "status", "started_utc", "finished_utc", "source_commit", "toolchain",
            "kernel_config_path", "kernel_config_sha256", "parent_trial", "change_group",
            "explicit_symbols", "autoselected_symbols", "kernel_image_path", "kernel_image_sha256",
            "boot_level", "toybox_result", "alpine_result", "arch_result", "failure_signature", "windows_error",
            "kernel_log_path", "crash_log_path", "classification", "stock_restore_verified", "notes",
        ]
        with trials.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=ledger_fields)
            writer.writeheader()
            for row in source.execute("SELECT * FROM trials ORDER BY started_utc,trial_id"):
                value = dict(row)
                value["parent_trial"] = value["parent_trial"] or ""
                value["notes"] = value.pop("ledger_notes")
                for key in ("config_name", "analysis_path", "metadata_notes"):
                    value.pop(key)
                writer.writerow({key: value[key] for key in ledger_fields})
        with metadata.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=TRIAL_METADATA_FIELDS)
            writer.writeheader()
            for row in source.execute("SELECT * FROM trials ORDER BY started_utc,trial_id"):
                value = dict(row)
                writer.writerow({
                    "trial_id": value["trial_id"], "parent_trial": value["parent_trial"] or "",
                    "config_name": value["config_name"] or "", "change_group": value["change_group"],
                    "explicit_symbols": value["explicit_symbols"],
                    "autoselected_symbols": value["autoselected_symbols"],
                    "boot_level": value["boot_level"], "analysis_path": value["analysis_path"],
                    "notes": value["metadata_notes"],
                })
        return configs, trials, metadata
    finally:
        source.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="inventory/kconfig-dependencies.sqlite")
    parser.add_argument("--experiments", default="inventory/experiments.sqlite")
    parser.add_argument("--summary", default="inventory/summary.json")
    parser.add_argument("--project-root", default=".")
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    db = sqlite3.connect(Path(args.db))
    try:
        db.execute("PRAGMA foreign_keys=ON")
        with tempfile.TemporaryDirectory() as directory:
            configs, trials, metadata = export_experiment_records(Path(args.experiments), Path(directory))
            with db:
                sync_configs(db, configs, root)
                sync_trials(db, trials, metadata, root)
        integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise SystemExit(f"SQLite integrity check failed: {integrity}")
        config_names = [row[0] for row in db.execute("SELECT name FROM configs ORDER BY rowid")]
        result = {
            "database": str(Path(args.db).as_posix()),
            "symbols": db.execute("SELECT count(*) FROM symbols").fetchone()[0],
            "edges": db.execute("SELECT count(*) FROM edges").fetchone()[0],
            "configs": config_names,
            "trials": db.execute("SELECT count(*) FROM trial_inventory").fetchone()[0],
            "reviewed_annotations": db.execute(
                "SELECT count(*) FROM annotations WHERE checked=1"
            ).fetchone()[0],
            "integrity": integrity,
        }
        Path(args.summary).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, sort_keys=True))
    finally:
        db.close()


if __name__ == "__main__":
    main()
