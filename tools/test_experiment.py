from __future__ import annotations

import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.generate_candidate_scripts import generate, render_text
from tools.inventory_records import export_experiment_records, sync_trials
from tools.migrate_experiments import migrate
from tools.experiment import (
    add_trial_correction,
    close_operation,
    connect,
    derive_operation,
    logical_diff,
    logical_state,
    prepare_candidates,
    request_uac,
    retry_operation,
    transition_operation,
    validate,
)

ROOT = Path(__file__).parents[1]
DB = Path(os.environ.get("EXPERIMENT_TEST_DB", ROOT / "inventory/experiments.sqlite"))
CONTROLLER = Path.home() / "AppData/Local/ultra-minimal-wsl/approval-state/minimal-v6-k-overlay-pidns-runtime-013/Run-ControlledTrial.ps1"
DIAGNOSTIC_CONTROLLER = Path.home() / "AppData/Local/ultra-minimal-wsl/approval-state/minimal-v6-k-overlay-pidns-diagnostic-runtime-014/Run-ControlledTrial.ps1"


class ExperimentInventoryTests(unittest.TestCase):
    def temporary_database(self, directory: str) -> sqlite3.Connection:
        copy = Path(directory) / "experiments.sqlite"
        shutil.copy2(DB, copy)
        db = connect(copy, writable=True)
        # Mutation tests create their own executable operation. Terminalize only the
        # copied operation through the lifecycle API so canonical state cannot affect them.
        active = db.execute("SELECT operation_id FROM operations WHERE executable=1").fetchone()
        if active:
            close_operation(db, {
                "operation_id": active[0], "status": "cancelled", "disposition": "cancelled",
                "reason": "test-local lifecycle isolation", "recorded_utc": "2026-09-01T00:00:00Z",
            })
            db.commit()
        return db

    def test_canonical_database_invariants_do_not_depend_on_current_operation(self) -> None:
        db = connect(DB)
        try:
            result = validate(db)
            self.assertEqual(result["integrity"], "ok")
            self.assertEqual(result["schemaVersion"], 5)
            self.assertGreaterEqual(result["trials"], 20)
            self.assertLessEqual(len(list(db.execute("SELECT * FROM active_operation"))), 1)
        finally:
            db.close()

    @unittest.skipIf(os.environ.get("EXPERIMENT_PREFLIGHT_CHILD") == "1", "avoid recursive suite launch")
    def test_complete_suite_is_independent_of_an_active_canonical_equivalent_operation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory) / "active.sqlite"
            shutil.copy2(DB, copy)
            db = connect(copy, writable=True)
            try:
                active = db.execute("SELECT operation_id FROM operations WHERE executable=1").fetchone()
                if active:
                    operation_id = active[0]
                else:
                    operation_id = "active-suite-regression"
                    derive_operation(db, {
                        "operation_id": operation_id,
                        "parent_operation_id": "minimal-v7-k-overlay-pidns-runtime-016",
                        "candidate_id": "minimal-v7-k-overlay-pidns-001",
                        "trial_id": "ACTIVE-SUITE-REGRESSION",
                        "rationale": "canonical-equivalent active lifecycle regression",
                        "prepared_utc": "2026-09-01T00:00:00Z",
                        "replace_artifacts": {},
                    })
                    db.commit()
                self.assertEqual(validate(db)["activeOperation"], operation_id)
            finally:
                db.close()
            environment = dict(os.environ)
            environment["EXPERIMENT_TEST_DB"] = str(copy)
            environment["EXPERIMENT_PREFLIGHT_CHILD"] = "1"
            result = subprocess.run(
                ["uv", "run", "python", "-m", "unittest", "tools.test_experiment"],
                cwd=ROOT, env=environment, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_broker_command_uses_the_operation_bound_launcher(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            copy = Path(directory) / "experiments.sqlite"
            try:
                launcher_id = db.execute(
                    "SELECT artifact_id FROM artifacts WHERE path=?",
                    ("tools/fixture-broker/Start-FixtureBrokerRunV2.ps1",),
                ).fetchone()[0]
                derive_operation(db, {
                    "operation_id": "bound-launcher-regression",
                    "parent_operation_id": "minimal-v8-k-pidns-runtime-018",
                    "candidate_id": "minimal-v8-k-pidns-001",
                    "trial_id": "BOUND-LAUNCHER-REGRESSION",
                    "rationale": "verify broker command uses the operation artifact binding",
                    "prepared_utc": "2026-09-02T00:00:00Z",
                    "replace_artifacts": {"broker_launcher": launcher_id},
                })
                db.commit()
            finally:
                db.close()
            result = subprocess.run(
                ["uv", "run", "python", "tools/experiment.py", "--db", str(copy),
                 "broker-command", "bound-launcher-regression"],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Start-FixtureBrokerRunV2.ps1", result.stdout)
            self.assertNotIn("Start-FixtureBrokerRun.ps1", result.stdout)

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

    def test_derived_operation_can_explicitly_narrow_artifacts_for_new_kind(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            try:
                template_path = ROOT / "control-plane/contract-templates/debian2-article-preparation.v1.json"
                db.execute(
                    "INSERT OR IGNORE INTO operation_templates VALUES (?,?,?)",
                    ("debian2-article-preparation-v1", str(template_path.relative_to(ROOT)).replace("\\", "/"), hashlib.sha256(template_path.read_bytes()).hexdigest()),
                )
                parent_roles = dict(db.execute(
                    "SELECT role,artifact_id FROM operation_artifacts WHERE operation_id=?",
                    ("minimal-v6-k-overlay-pidns-runtime-013",),
                ))
                required = json.loads(template_path.read_text(encoding="utf-8"))["requiredArtifactRoles"]
                fallback_id = next(iter(parent_roles.values()))
                replacements = {role: parent_roles.get(role, fallback_id) for role in required}
                derive_operation(db, {
                    "operation_id": "narrow-derived-test",
                    "parent_operation_id": "minimal-v6-k-overlay-pidns-runtime-013",
                    "candidate_id": "minimal-v6-k-overlay-pidns-001",
                    "trial_id": "NARROW-DERIVED-TEST",
                    "rationale": "test explicit narrowing",
                    "prepared_utc": "2026-09-01T00:00:00Z",
                    "template_id": "debian2-article-preparation-v1",
                    "remove_artifacts": sorted(parent_roles),
                    "replace_artifacts": replacements,
                })
                actual = {row[0] for row in db.execute(
                    "SELECT role FROM operation_artifacts WHERE operation_id='narrow-derived-test'"
                )}
                self.assertEqual(actual, set(required))
                self.assertEqual(validate(db)["activeOperation"], "narrow-derived-test")
            finally:
                db.close()

    def test_derived_operation_rejects_duplicate_or_uninherited_removals(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            for removals in (["wpr", "wpr"], ["not-a-role"]):
                db = self.temporary_database(directory)
                try:
                    with self.assertRaises(SystemExit):
                        derive_operation(db, {
                            "operation_id": "bad-removal-test",
                            "parent_operation_id": "minimal-v6-k-overlay-pidns-runtime-013",
                            "candidate_id": "minimal-v6-k-overlay-pidns-001",
                            "trial_id": "BAD-REMOVAL-TEST",
                            "rationale": "bad removal",
                            "prepared_utc": "2026-09-01T00:00:00Z",
                            "remove_artifacts": removals,
                            "replace_artifacts": {},
                        })
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
                derive_operation(db, {
                    "operation_id": "lifecycle-test",
                    "parent_operation_id": "minimal-v7-k-overlay-pidns-runtime-016",
                    "candidate_id": "minimal-v7-k-overlay-pidns-001",
                    "trial_id": "LIFECYCLE-TEST",
                    "rationale": "lifecycle test",
                    "prepared_utc": "2026-09-01T00:00:00Z",
                    "replace_artifacts": {},
                })
                with self.assertRaises(SystemExit):
                    transition_operation(db, {
                        "operation_id": "lifecycle-test",
                        "status": "probe-started", "first_probe_utc": "2026-09-01T00:00:00Z",
                    })
                uac = {
                    "operation_id": "lifecycle-test",
                    "status": "uac-requested", "uac_requested_utc": "2026-09-01T00:00:00Z",
                }
                with self.assertRaises(SystemExit):
                    transition_operation(db, uac)
                def red_suite(_path: Path) -> None:
                    raise SystemExit("red suite")

                with self.assertRaisesRegex(SystemExit, "red suite"):
                    request_uac(db, uac, suite_runner=red_suite)
                self.assertEqual(
                    db.execute("SELECT status FROM operations WHERE operation_id='lifecycle-test'").fetchone()[0],
                    "runtime-planned",
                )
                suites = []
                request_uac(db, uac, suite_runner=lambda path: suites.append(path))
                self.assertEqual(suites, [Path(db.execute("PRAGMA database_list").fetchone()[2])])
                self.assertEqual(
                    db.execute("SELECT status FROM operations WHERE operation_id='lifecycle-test'").fetchone()[0],
                    "uac-requested",
                )
            finally:
                db.close()

    def test_candidate_preparation_is_atomic_and_calculates_file_identity(self) -> None:
        artifact_path = "tools/generate_candidate_scripts.py"
        with tempfile.TemporaryDirectory() as directory:
            db = self.temporary_database(directory)
            try:
                before = db.execute("SELECT count(*) FROM candidates").fetchone()[0]
                record = {
                    "candidates": [{
                        "candidate_id": "atomic-preparation-test", "kind": "process-test",
                        "status": "prepared", "rationale": "atomic test",
                    }],
                    "new_artifacts": [{
                        "candidate_id": "atomic-preparation-test", "role": "generator",
                        "kind": "process-generator", "location": "repository", "path": artifact_path,
                    }],
                    "existing_artifacts": [],
                }
                with db:
                    prepare_candidates(db, record)
                artifact = db.execute(
                    "SELECT a.* FROM artifacts a JOIN candidate_artifacts ca USING(artifact_id) "
                    "WHERE ca.candidate_id='atomic-preparation-test'"
                ).fetchone()
                path = ROOT / artifact_path
                self.assertEqual(artifact["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
                self.assertEqual(artifact["bytes"], path.stat().st_size)
                self.assertEqual(db.execute("SELECT count(*) FROM candidates").fetchone()[0], before + 1)

                failing = json.loads(json.dumps(record))
                failing["candidates"][0]["candidate_id"] = "atomic-rollback-test"
                failing["new_artifacts"][0].update({
                    "candidate_id": "atomic-rollback-test", "path": "missing-candidate-artifact",
                })
                with self.assertRaises(SystemExit):
                    with db:
                        prepare_candidates(db, failing)
                self.assertIsNone(db.execute(
                    "SELECT 1 FROM candidates WHERE candidate_id='atomic-rollback-test'"
                ).fetchone())
            finally:
                db.close()

    def test_finalized_v7_scripts_are_exact_deterministic_generation_delta(self) -> None:
        delta = generate(
            ROOT / "control-plane/generation/minimal-v7-no-cross-distro-launch.v1.json",
            write=False,
        )
        self.assertIn("Build-MinimalV7NoCrossDistroLaunch.ps1", delta)
        self.assertIn("Invoke-MinimalV7KOverlayPidNsDiagnosticTrial.ps1", delta)
        self.assertIn("minimal-v7-k-overlay-pidns-runtime-016", delta)
        self.assertIn("0009-minimal-v7-no-cross-distro-launch.patch", delta)

    def test_candidate_generation_v2_has_fixed_build_and_runtime_phases(self) -> None:
        phases = {
            "build": ("build", "controller"),
            "runtime": ("runner", "controller"),
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for phase, names in phases.items():
                files = []
                for name in names:
                    source = root / f"{phase}-{name}.source.ps1"
                    output = root / f"{phase}-{name}.output.ps1"
                    source_text = f"{name}=old\n"
                    output_text = f"{name}=new\n"
                    source.write_text(source_text, encoding="utf-8", newline="")
                    files.append({
                        "name": name,
                        "source": str(source),
                        "output": str(output),
                        "source_sha256": hashlib.sha256(source_text.encode()).hexdigest(),
                        "output_sha256": hashlib.sha256(output_text.encode()).hexdigest(),
                        "substitutions": [{"old": "=old", "new": "=new"}],
                    })
                record = {
                    "schema": 2, "generator": "candidate-powershell-v2",
                    "phase": phase, "files": files,
                }
                delta_path = root / f"{phase}.json"
                delta_path.write_text(json.dumps(record), encoding="utf-8")
                delta = generate(delta_path, write=True)
                self.assertEqual({item["name"] for item in files}, set(names))
                self.assertNotIn("PreBuild-DoNotExecute", delta)
                for item in files:
                    self.assertEqual(Path(item["output"]).read_text(encoding="utf-8"), f"{item['name']}=new\n")

            invalid = json.loads((root / "build.json").read_text(encoding="utf-8"))
            invalid["files"].append(dict(invalid["files"][0], name="runner"))
            invalid_path = root / "invalid.json"
            invalid_path.write_text(json.dumps(invalid), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "outputs must be exactly"):
                generate(invalid_path, write=False)

    def test_candidate_generation_rejects_duplicate_overlap_and_unresolved_values(self) -> None:
        with self.assertRaisesRegex(ValueError, "occurs 2 times"):
            render_text("token token", [{"old": "token", "new": "value"}])
        with self.assertRaisesRegex(ValueError, "overlap"):
            render_text("abcdef", [
                {"old": "abcd", "new": "one"}, {"old": "cdef", "new": "two"},
            ])
        with self.assertRaisesRegex(ValueError, "unresolved"):
            render_text("candidate=old", [{"old": "old", "new": "{{CANDIDATE}}"}])

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


class TrialCorrectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "experiments.sqlite"
        shutil.copy2(DB, self.path)
        migrate(self.path)
        self.db = connect(self.path, writable=True)
        self.addCleanup(self.db.close)
        self.trial_id = "G-001"
        self.original = dict(self.db.execute("SELECT * FROM trials WHERE trial_id=?", (self.trial_id,)).fetchone())
        self.evidence = "recovery-harness/trials/CP-MINIMAL-V8-K-PIDNS-DEBIAN2-PRACTICAL-001/attempt-052/candidate/CP-MINIMAL-V8-K-PIDNS-DEBIAN2-PRACTICAL-001/04-tool-versions-result.json"

    def record(self, field: str = "metadata_notes", text: str = "Corrected interpretation") -> dict:
        effective = self.db.execute("SELECT * FROM trial_effective WHERE trial_id=?", (self.trial_id,)).fetchone()
        return dict(trial_id=self.trial_id, field=field, superseded_value=effective[field],
                    corrected_value=text, reason="test correction", evidence_path=self.evidence)

    def test_ordering_is_per_field_and_preserves_raw_trial(self) -> None:
        before = logical_state(self.db)
        # Deliberately equal/backdated clocks: only append IDs may choose precedence.
        with patch("tools.experiment.datetime") as clock:
            clock.now.return_value.isoformat.return_value = "2026-09-05T00:00:00+00:00"
            add_trial_correction(self.db, self.record(text="First interpretation"))
            add_trial_correction(self.db, self.record("failure_signature", "Independent field correction"))
            clock.now.return_value.isoformat.return_value = "2026-09-04T00:00:00+00:00"
            add_trial_correction(self.db, self.record(text="Second interpretation"))
        effective = self.db.execute("SELECT * FROM trial_effective WHERE trial_id=?", (self.trial_id,)).fetchone()
        self.assertEqual(effective["metadata_notes"], "Second interpretation")
        self.assertEqual(effective["failure_signature"], "Independent field correction")
        self.assertEqual(dict(self.db.execute("SELECT * FROM trials WHERE trial_id=?", (self.trial_id,)).fetchone()), self.original)
        delta = logical_diff(before, logical_state(self.db))
        self.assertEqual(len(delta["trial_corrections"]["added"]), 3)
        self.assertEqual(delta["trials"], {"added": [], "removed": [], "changed": {}})
        self.assertEqual(validate(self.db)["integrity"], "ok")

    def test_corrections_reject_update_delete_and_replace(self) -> None:
        add_trial_correction(self.db, self.record())
        self.db.commit()
        for statement in (
            "UPDATE trial_corrections SET corrected_value='rewritten'",
            "DELETE FROM trial_corrections",
            "INSERT OR REPLACE INTO trial_corrections SELECT * FROM trial_corrections",
        ):
            with self.subTest(statement=statement), self.assertRaisesRegex(sqlite3.IntegrityError, "append-only"):
                self.db.execute(statement)

    def test_rejects_stale_unknown_observational_and_invalid_evidence_records(self) -> None:
        stale = self.record()
        add_trial_correction(self.db, stale)
        invalid = [stale, self.record() | {"trial_id": "missing"},
                   self.record() | {"field": "status"},
                   self.record() | {"evidence_path": "../outside"},
                   self.record() | {"evidence_path": "missing.json"},
                   self.record() | {"recorded_utc": "caller-controlled"}]
        for record in invalid:
            with self.subTest(record=record), self.assertRaises(SystemExit):
                add_trial_correction(self.db, record)
        for record in (self.record(text=""), self.record() | {"reason": " "}):
            with self.assertRaises(sqlite3.IntegrityError):
                add_trial_correction(self.db, record)

    def test_validation_detects_broken_chain_and_evidence_hash(self) -> None:
        record = self.record()
        add_trial_correction(self.db, record)
        self.db.commit()
        columns = "trial_id,field,superseded_value,corrected_value,reason,evidence_path,evidence_sha256,recorded_utc"
        original = dict(self.db.execute("SELECT * FROM trial_corrections ORDER BY correction_id DESC LIMIT 1").fetchone())
        for change, expected in (({"superseded_value": "stale"}, "chain mismatch"),
                                 ({"evidence_sha256": "0" * 64}, "evidence hash mismatch")):
            bad = original | {"superseded_value": record["corrected_value"], "corrected_value": "Next interpretation"} | change
            self.db.execute(f"INSERT INTO trial_corrections ({columns}) VALUES ({','.join('?' for _ in columns.split(','))})",
                            tuple(bad[name] for name in columns.split(',')))
            with self.assertRaisesRegex(SystemExit, expected):
                validate(self.db)
            self.db.rollback()

    def test_normal_cli_summary_and_generated_exports_use_effective_values(self) -> None:
        add_trial_correction(self.db, self.record("failure_signature", "Corrected failure"))
        add_trial_correction(self.db, self.record("ledger_notes", "Corrected ledger"))
        self.db.commit()
        record_path = Path(self.temporary.name) / "correction.json"
        record_path.write_text(json.dumps(self.record(text="Corrected metadata")), encoding="utf-8")
        command = ["uv", "run", "python", "tools/experiment.py", "--db", str(self.path),
                   "trial-correction-add", "--record", str(record_path)]
        subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
        rejected = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("exact current effective value", rejected.stderr)
        summary = self.db.execute("SELECT * FROM trial_summary WHERE trial_id=?", (self.trial_id,)).fetchone()
        self.assertEqual(summary["failure_signature"], "Corrected failure")
        self.assertEqual(summary["correction_count"], 3)
        result = subprocess.run(
            ["uv", "run", "python", "tools/experiment.py", "--db", str(self.path), "show", "trial", self.trial_id],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        shown = json.loads(result.stdout)[0]
        self.assertEqual(shown["metadata_notes"], "Corrected metadata")
        self.assertEqual(len(shown["corrections"]), 3)
        _, trials, metadata = export_experiment_records(self.path, Path(self.temporary.name))
        generated = sqlite3.connect(":memory:")
        try:
            generated.execute("CREATE TABLE configs(name TEXT PRIMARY KEY)")
            generated.executemany("INSERT INTO configs VALUES (?)", self.db.execute("SELECT name FROM configs"))
            sync_trials(generated, trials, metadata, ROOT)
            row = generated.execute("SELECT failure_signature,metadata_notes,ledger_notes FROM trial_inventory WHERE trial_id=?", (self.trial_id,)).fetchone()
            self.assertEqual(row, ("Corrected failure", "Corrected metadata", "Corrected ledger"))
        finally:
            generated.close()

    def test_recorded_debian2_correction_matches_silent_p4_evidence(self) -> None:
        trial_id = "CP-MINIMAL-V8-K-PIDNS-DEBIAN2-PRACTICAL-001"
        raw = self.db.execute("SELECT * FROM trials WHERE trial_id=?", (trial_id,)).fetchone()
        effective = self.db.execute("SELECT * FROM trial_effective WHERE trial_id=?", (trial_id,)).fetchone()
        evidence = json.loads((ROOT / self.evidence).read_text(encoding="utf-8-sig"))
        self.assertEqual((evidence["exitCode"], evidence["stdout"], evidence["stderr"]), (1, "", ""))
        self.assertIn("after Node/npm/fnm/McFly checks", raw["failure_signature"])
        self.assertIn("no individual", effective["failure_signature"])
        self.assertNotEqual(raw["metadata_notes"], effective["metadata_notes"])
        for field in set(raw.keys()) - {"failure_signature", "metadata_notes"}:
            self.assertEqual(raw[field], effective[field])

    def test_v4_migration_preserves_rows_and_matches_fresh_schema(self) -> None:
        before = [tuple(row) for row in self.db.execute("SELECT * FROM trials ORDER BY trial_id")]
        self.db.executescript("""DROP VIEW trial_summary; DROP VIEW trial_effective;
            DROP TABLE trial_corrections;
            CREATE VIEW trial_summary AS SELECT trial_id FROM trials;
            UPDATE metadata SET value='4' WHERE key='schema'; PRAGMA user_version=4;""")
        migrate(self.path)
        self.assertEqual([tuple(row) for row in self.db.execute("SELECT * FROM trials ORDER BY trial_id")], before)
        self.assertEqual(self.db.execute("SELECT count(*) FROM trial_corrections").fetchone()[0], 0)
        fresh = sqlite3.connect(":memory:")
        try:
            fresh.executescript((ROOT / "inventory/experiment-schema.sql").read_text())
            for name in ("trial_corrections", "trial_effective", "trial_summary", "corrections_no_update", "corrections_no_delete", "corrections_no_replace"):
                expected = fresh.execute("SELECT sql FROM sqlite_master WHERE name=?", (name,)).fetchone()[0]
                actual = self.db.execute("SELECT sql FROM sqlite_master WHERE name=?", (name,)).fetchone()[0]
                self.assertEqual(actual, expected)
        finally:
            fresh.close()


if __name__ == "__main__":
    unittest.main()
