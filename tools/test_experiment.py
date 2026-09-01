from __future__ import annotations

import hashlib
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.experiment import connect, transition_operation, validate

ROOT = Path(__file__).parents[1]
DB = ROOT / "inventory/experiments.sqlite"
CONTROLLER = Path.home() / "AppData/Local/ultra-minimal-wsl/approval-state/minimal-v6-k-overlay-pidns-runtime-013/Run-ControlledTrial.ps1"


class ExperimentInventoryTests(unittest.TestCase):
    def test_canonical_database_is_valid_and_has_no_active_operation(self) -> None:
        db = connect(DB)
        try:
            result = validate(db)
            self.assertEqual(result["integrity"], "ok")
            self.assertEqual(result["schemaVersion"], 1)
            self.assertEqual(result["trials"], 19)
            self.assertIsNone(result["activeOperation"])
        finally:
            db.close()

    def test_finalized_controller_is_hash_bound_and_does_not_read_mutable_planning_state(self) -> None:
        db = connect(DB)
        try:
            row = db.execute(
                "SELECT a.path AS controller_path,a.sha256 AS controller_sha256 "
                "FROM operations o JOIN artifacts a ON a.artifact_id=o.controller_artifact_id "
                "WHERE o.operation_id='minimal-v6-k-overlay-pidns-runtime-013'"
            ).fetchone()
            self.assertEqual(Path(row["controller_path"]), CONTROLLER)
            self.assertEqual(hashlib.sha256(CONTROLLER.read_bytes()).hexdigest(), row["controller_sha256"])
            text = CONTROLLER.read_text(encoding="utf-8")
            self.assertNotIn("deferred-runtime-plan", text)
            self.assertNotRegex(text, r"(?i)(Get-Content|sqlite3|experiment\.py).*experiments\.sqlite")
            self.assertIn("FixtureBroker-SecureWorkload: 1", text)
        finally:
            db.close()

    def test_frozen_v1_inputs_match_migration_metadata(self) -> None:
        files = {
            "migrated_plan_sha256": ROOT / "control-plane/deferred-runtime-plan.v1.json",
            "migrated_configs_sha256": ROOT / "inventory/config-snapshots.v1.csv",
            "migrated_trials_sha256": ROOT / "inventory/trials.v1.csv",
            "migrated_trial_metadata_sha256": ROOT / "inventory/trial-metadata.v1.csv",
        }
        db = connect(DB)
        try:
            metadata = dict(db.execute("SELECT key,value FROM metadata"))
            for key, path in files.items():
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), metadata[key])
        finally:
            db.close()

    def test_operation_lifecycle_cannot_skip_durable_worker_start(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / "experiments.sqlite"
            shutil.copy2(DB, copy)
            db = connect(copy, writable=True)
            try:
                db.execute(
                    "INSERT INTO operations(operation_id,kind,status,executable,rationale,fixed_contract,runtime_boundary) "
                    "VALUES ('lifecycle-test','runtime','runtime-planned',1,'test','test','test')"
                )
                with self.assertRaises(SystemExit):
                    transition_operation(db, {
                        "operation_id": "lifecycle-test",
                        "status": "probe-started", "first_probe_utc": "2026-09-01T00:00:00Z",
                    })
                transition_operation(db, {
                    "operation_id": "lifecycle-test",
                    "status": "uac-requested", "uac_requested_utc": "2026-09-01T00:00:00Z",
                })
                self.assertEqual(
                    db.execute("SELECT status FROM operations WHERE operation_id='lifecycle-test'").fetchone()[0],
                    "uac-requested",
                )
            finally:
                db.close()

    def test_terminal_trials_and_dispositions_are_immutable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / "experiments.sqlite"
            shutil.copy2(DB, copy)
            db = connect(copy, writable=True)
            try:
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute("UPDATE trials SET status='PASS' WHERE trial_id='CP-MINIMAL-V6-K-PIDNS-001'")
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute("DELETE FROM operation_dispositions")
            finally:
                db.close()

    def test_database_has_no_commit_unsafe_sidecars(self) -> None:
        self.assertFalse(Path(str(DB) + "-wal").exists())
        self.assertFalse(Path(str(DB) + "-shm").exists())

    def test_frozen_migration_remains_an_unchanged_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "experiments.sqlite"
            subprocess.run(
                ["uv", "run", "python", "tools/import_experiments.py", "--output", str(output)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            migrated = connect(output)
            canonical = connect(DB)
            try:
                for table, key in (
                    ("candidates", "candidate_id"), ("artifacts", "artifact_id"),
                    ("configs", "name"), ("trials", "trial_id"),
                    ("operation_dispositions", "disposition_id"),
                ):
                    for row in migrated.execute(f"SELECT * FROM {table}"):
                        actual = canonical.execute(
                            f"SELECT * FROM {table} WHERE {key}=?", (row[key],)
                        ).fetchone()
                        self.assertIsNotNone(actual)
                        self.assertEqual(dict(actual), dict(row))
                for row in migrated.execute(
                    "SELECT * FROM operations WHERE operation_id<>'minimal-v6-k-overlay-pidns-runtime-013'"
                ):
                    actual = canonical.execute(
                        "SELECT * FROM operations WHERE operation_id=?", (row["operation_id"],)
                    ).fetchone()
                    self.assertEqual(dict(actual), dict(row))
                migrated_runtime = migrated.execute(
                    "SELECT * FROM operations WHERE operation_id='minimal-v6-k-overlay-pidns-runtime-013'"
                ).fetchone()
                canonical_runtime = canonical.execute(
                    "SELECT * FROM operations WHERE operation_id='minimal-v6-k-overlay-pidns-runtime-013'"
                ).fetchone()
                for field in (
                    "operation_id", "kind", "candidate_id", "trial_id", "parent_operation_id",
                    "controller_artifact_id", "rationale", "fixed_contract", "runtime_boundary",
                ):
                    self.assertEqual(canonical_runtime[field], migrated_runtime[field])
                self.assertEqual(canonical_runtime["status"], "candidate-finalized")
                self.assertFalse(canonical_runtime["executable"])
                self.assertIsNotNone(canonical_runtime["first_probe_utc"])
                self.assertIsNotNone(canonical_runtime["completed_utc"])
            finally:
                migrated.close()
                canonical.close()


if __name__ == "__main__":
    unittest.main()
