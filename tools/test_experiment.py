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
    def test_canonical_database_is_valid_and_has_one_active_operation(self) -> None:
        db = connect(DB)
        try:
            result = validate(db)
            self.assertEqual(result["integrity"], "ok")
            self.assertEqual(result["schemaVersion"], 1)
            self.assertEqual(result["trials"], 18)
            self.assertEqual(result["activeOperation"], "minimal-v6-k-overlay-pidns-runtime-013")
        finally:
            db.close()

    def test_active_controller_is_hash_bound_and_does_not_read_mutable_planning_state(self) -> None:
        db = connect(DB)
        try:
            row = db.execute("SELECT controller_path,controller_sha256 FROM active_operation").fetchone()
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
                with self.assertRaises(SystemExit):
                    transition_operation(db, {
                        "operation_id": "minimal-v6-k-overlay-pidns-runtime-013",
                        "status": "probe-started", "first_probe_utc": "2026-09-01T00:00:00Z",
                    })
                transition_operation(db, {
                    "operation_id": "minimal-v6-k-overlay-pidns-runtime-013",
                    "status": "uac-requested", "uac_requested_utc": "2026-09-01T00:00:00Z",
                })
                self.assertEqual(db.execute("SELECT status FROM operations WHERE operation_id='minimal-v6-k-overlay-pidns-runtime-013'").fetchone()[0], "uac-requested")
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

    def test_frozen_migration_reproduces_identical_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "experiments.sqlite"
            subprocess.run(
                ["uv", "run", "python", "tools/import_experiments.py", "--output", str(output)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(), hashlib.sha256(DB.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
