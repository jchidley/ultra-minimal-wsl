from __future__ import annotations

import hashlib
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.experiment import (
    connect,
    derive_operation,
    logical_diff,
    logical_state,
    retry_operation,
    transition_operation,
    validate,
)

ROOT = Path(__file__).parents[1]
DB = ROOT / "inventory/experiments.sqlite"
CONTROLLER = Path.home() / "AppData/Local/ultra-minimal-wsl/approval-state/minimal-v6-k-overlay-pidns-runtime-013/Run-ControlledTrial.ps1"
DIAGNOSTIC_CONTROLLER = Path.home() / "AppData/Local/ultra-minimal-wsl/approval-state/minimal-v6-k-overlay-pidns-diagnostic-runtime-014/Run-ControlledTrial.ps1"


class ExperimentInventoryTests(unittest.TestCase):
    def temporary_database(self, directory: str) -> sqlite3.Connection:
        copy = Path(directory) / "experiments.sqlite"
        shutil.copy2(DB, copy)
        return connect(copy, writable=True)

    def test_canonical_database_invariants_do_not_depend_on_current_operation(self) -> None:
        db = connect(DB)
        try:
            result = validate(db)
            self.assertEqual(result["integrity"], "ok")
            self.assertEqual(result["schemaVersion"], 2)
            self.assertGreaterEqual(result["trials"], 20)
            self.assertLessEqual(len(list(db.execute("SELECT * FROM active_operation"))), 1)
        finally:
            db.close()

    def test_versioned_templates_are_hash_bound_and_every_operation_uses_one(self) -> None:
        db = connect(DB)
        try:
            for row in db.execute("SELECT * FROM operation_templates"):
                path = ROOT / row["path"]
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])
            self.assertEqual(
                db.execute("SELECT count(*) FROM operation_template_bindings").fetchone()[0],
                db.execute("SELECT count(*) FROM operations").fetchone()[0],
            )
        finally:
            db.close()

    def test_finalized_diagnostic_controller_is_hash_bound(self) -> None:
        db = connect(DB)
        try:
            row = db.execute(
                "SELECT a.path AS controller_path,a.sha256 AS controller_sha256 "
                "FROM operations o JOIN artifacts a ON a.artifact_id=o.controller_artifact_id "
                "WHERE o.operation_id='minimal-v6-k-overlay-pidns-diagnostic-runtime-015'"
            ).fetchone()
            self.assertEqual(Path(row["controller_path"]), DIAGNOSTIC_CONTROLLER)
            self.assertEqual(hashlib.sha256(DIAGNOSTIC_CONTROLLER.read_bytes()).hexdigest(), row["controller_sha256"])
            text = DIAGNOSTIC_CONTROLLER.read_text(encoding="utf-8")
            self.assertIn("diagnosticDebugConsole", text)
            self.assertIn("diagnosticRelayCount", text)
            self.assertNotIn("deferred-runtime-plan", text)
        finally:
            db.close()

    def test_finalized_controller_does_not_read_mutable_planning_state(self) -> None:
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
        finally:
            db.close()

    def test_derived_operation_inherits_artifacts_and_accepts_only_explicit_replacements(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            try:
                derive_operation(db, {
                    "operation_id": "derived-test",
                    "parent_operation_id": "minimal-v6-k-overlay-pidns-runtime-013",
                    "candidate_id": "minimal-v6-k-overlay-pidns-001",
                    "trial_id": "DERIVED-TEST",
                    "rationale": "test derived contract",
                    "prepared_utc": "2026-09-01T00:00:00Z",
                    "replace_artifacts": {},
                })
                self.assertEqual(validate(db)["activeOperation"], "derived-test")
                parent = list(db.execute(
                    "SELECT role,artifact_id FROM operation_artifacts WHERE operation_id=? ORDER BY role",
                    ("minimal-v6-k-overlay-pidns-runtime-013",),
                ))
                derived = list(db.execute(
                    "SELECT role,artifact_id FROM operation_artifacts WHERE operation_id=? ORDER BY role",
                    ("derived-test",),
                ))
                self.assertEqual([tuple(row) for row in parent], [tuple(row) for row in derived])
            finally:
                db.close()

    def test_derived_operation_rejects_reconstructed_artifact_lists(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            try:
                with self.assertRaises(SystemExit):
                    derive_operation(db, {
                        "operation_id": "bad-derived-test",
                        "parent_operation_id": "minimal-v6-k-overlay-pidns-runtime-013",
                        "candidate_id": "minimal-v6-k-overlay-pidns-001",
                        "trial_id": "BAD-DERIVED-TEST",
                        "rationale": "bad",
                        "prepared_utc": "2026-09-01T00:00:00Z",
                        "artifacts": [],
                    })
            finally:
                db.close()

    def test_retry_references_the_unchanged_template_and_artifact_set(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            try:
                retry_operation(db, {
                    "operation_id": "retry-test",
                    "after_operation_id": "minimal-v6-k-overlay-pidns-diagnostic-runtime-014",
                    "reason": "fresh launch",
                    "prepared_utc": "2026-09-01T00:00:00Z",
                })
                self.assertEqual(validate(db)["activeOperation"], "retry-test")
                source_template = db.execute(
                    "SELECT template_id FROM operation_template_bindings WHERE operation_id=?",
                    ("minimal-v6-k-overlay-pidns-diagnostic-runtime-014",),
                ).fetchone()[0]
                retry_template = db.execute(
                    "SELECT template_id FROM operation_template_bindings WHERE operation_id='retry-test'"
                ).fetchone()[0]
                self.assertEqual(retry_template, source_template)
                source = list(db.execute(
                    "SELECT role,artifact_id FROM operation_artifacts WHERE operation_id=? ORDER BY role",
                    ("minimal-v6-k-overlay-pidns-diagnostic-runtime-014",),
                ))
                retry = list(db.execute(
                    "SELECT role,artifact_id FROM operation_artifacts WHERE operation_id='retry-test' ORDER BY role"
                ))
                self.assertEqual([tuple(row) for row in source], [tuple(row) for row in retry])
            finally:
                db.close()

    def test_operation_lifecycle_cannot_skip_durable_worker_start(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
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

    def test_logical_diff_includes_relationships_and_field_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            try:
                before = logical_state(db)
                db.execute("INSERT INTO metadata VALUES ('diff-test','before')")
                middle = logical_state(db)
                first = logical_diff(before, middle)
                self.assertIn("diff-test", first["metadata"]["added"])
                db.execute("UPDATE metadata SET value='after' WHERE key='diff-test'")
                after = logical_diff(middle, logical_state(db))
                self.assertEqual(
                    after["metadata"]["changed"]["diff-test"]["value"],
                    {"before": "before", "after": "after"},
                )
                self.assertIn("operation_artifacts", after)
                self.assertIn("operation_template_bindings", after)
            finally:
                db.close()

    def test_terminal_trials_dispositions_and_templates_are_immutable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            try:
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute("UPDATE trials SET status='PASS' WHERE trial_id='CP-MINIMAL-V6-K-PIDNS-001'")
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute("DELETE FROM operation_dispositions")
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute("UPDATE operation_templates SET path='x'")
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
                    ("metadata", "key"),
                    ("candidates", "candidate_id"), ("artifacts", "artifact_id"),
                    ("configs", "name"), ("trials", "trial_id"),
                    ("operation_dispositions", "disposition_id"),
                    ("operation_templates", "template_id"),
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
                    self.assertIsNotNone(actual)
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
                for table, columns in (
                    ("candidate_artifacts", ("candidate_id", "role")),
                    ("operation_artifacts", ("operation_id", "role")),
                    ("operation_template_bindings", ("operation_id",)),
                    ("trial_operation_results", ("trial_id",)),
                ):
                    for row in migrated.execute(f"SELECT * FROM {table}"):
                        where = " AND ".join(f"{column}=?" for column in columns)
                        actual = canonical.execute(
                            f"SELECT * FROM {table} WHERE {where}", tuple(row[column] for column in columns)
                        ).fetchone()
                        self.assertIsNotNone(actual)
                        self.assertEqual(dict(actual), dict(row))
            finally:
                migrated.close()
                canonical.close()


if __name__ == "__main__":
    unittest.main()
