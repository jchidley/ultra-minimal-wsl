import hashlib
import json
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).parents[1]
CONTROL = ROOT / "control-plane"
PLAN_PATH = CONTROL / "deferred-runtime-plan.json"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def key_values(path):
    return dict(
        line.rstrip("\n").split("=", 1)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line
    )


def sums(path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        digest, name = line.split(None, 1)
        result[name.strip()] = digest
    return result


def load_plan():
    return json.loads(PLAN_PATH.read_text(encoding="utf-8"))


class ControlPlaneRecordTests(unittest.TestCase):
    def test_fail_closed_policy_and_no_interop_layer_are_preserved(self):
        policy = (CONTROL / "policy/minimal-v2-policy.h").read_text(encoding="utf-8")
        fail_closed = (CONTROL / "patches/0002-minimal-v2-fail-closed.patch").read_text(encoding="utf-8")
        no_interop = (CONTROL / "patches/0004-minimal-v3-no-interop.patch").read_text(encoding="utf-8")

        for call in (
            "IsMiniInitRequestAllowed(Type)",
            "IsDistroControlRequestAllowed(Header->MessageType)",
            "IsSessionRequestAllowed(Message->Header.MessageType)",
            "AreDirectProcessFlagsAllowed(CreateProcess.Common.Flags)",
        ):
            self.assertIn(call, fail_closed)
        self.assertIn("LxMiniInitMessageLaunchInit", policy)
        self.assertEqual(no_interop.count("diff --git "), 1)
        self.assertIn("a/src/linux/init/main.cpp b/src/linux/init/main.cpp", no_interop)
        self.assertIn('-#include "binfmt.h"', no_interop)
        self.assertIn('-#define BINFMT_PATH PROCFS_PATH "/sys/fs/binfmt_misc"', no_interop)
        self.assertNotIn("a/src/linux/init/config.cpp b/src/linux/init/config.cpp", no_interop)

    def test_v4_sender_explicitly_zeros_excluded_initial_configuration(self):
        patch = (CONTROL / "patches/0006-minimal-v4-zero-initial-config.patch").read_text(encoding="utf-8")
        self.assertEqual(patch.count("diff --git "), 1)
        self.assertIn("a/src/windows/service/exe/WslCoreVm.cpp b/src/windows/service/exe/WslCoreVm.cpp", patch)
        for assignment in (
            "message->EnableGuiApps = false;",
            "message->MountGpuShares = false;",
            "message->EnableInboxGpuLibs = false;",
            "message->NetworkingConfiguration = {};",
        ):
            self.assertIn(assignment, patch)
        self.assertNotIn("a/src/linux/init/", patch)

    def test_namespace_variants_change_only_the_clone_bundle(self):
        for name in ("0003-minimal-v2-mount-ns.patch", "0005-minimal-v3-mount-ns.patch"):
            patch = (CONTROL / "patches" / name).read_text(encoding="utf-8")
            with self.subTest(patch=name):
                self.assertEqual(patch.count("diff --git "), 1)
                self.assertIn("(CLONE_NEWIPC | CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS | SIGCHLD));", patch)
                self.assertIn("(CLONE_NEWNS | SIGCHLD));", patch)

    def test_candidate_records_and_artifacts_are_synchronized(self):
        profile_digest = hashlib.sha256()
        for path in (
            ROOT / "build-host/lfs-builder-profile.env",
            ROOT / "build-host/debian-snapshot.list",
            ROOT / "build-host/packages.tsv",
        ):
            profile_digest.update(path.read_bytes())
        expected_profile = profile_digest.hexdigest()

        names = (
            "minimal-v2-fail-closed",
            "minimal-v2-stock-ns",
            "minimal-v2-mount-ns",
            "minimal-v3-fail-closed",
            "minimal-v3-stock-ns",
            "minimal-v3-mount-ns",
            "minimal-v4-fail-closed",
            "minimal-v4-stock-ns",
            "minimal-v4-mount-ns",
        )
        for name in names:
            directory = CONTROL / "candidates" / name
            candidate = key_values(directory / "candidate.txt")
            metadata = key_values(directory / "build-metadata.txt")
            reproducibility = key_values(directory / "reproducibility.txt")
            recorded_sums = sums(directory / "SHA256SUMS")
            with self.subTest(candidate=name):
                self.assertEqual(
                    candidate["complete_source_diff_sha256"],
                    (directory / "source-diff.sha256").read_text(encoding="utf-8").strip(),
                )
                self.assertEqual(metadata["source_patch_sha256"], candidate["complete_source_diff_sha256"])
                self.assertEqual(metadata["builder_profile_sha256"], expected_profile)
                self.assertEqual(reproducibility["builder_profile_sha256"], expected_profile)
                self.assertEqual(reproducibility["runs"], "2")
                self.assertEqual(reproducibility["result"], "byte-identical")
                self.assertEqual(recorded_sums["init"], reproducibility["init_sha256"])
                self.assertEqual(recorded_sums["init.debug"], reproducibility["init_debug_sha256"])
                self.assertEqual(recorded_sums["initrd.img"], reproducibility["initrd_sha256"])
                if candidate["layer_patch"] != "none":
                    self.assertEqual(sha256(ROOT / candidate["layer_patch"]), candidate["layer_patch_sha256"])

        self.assertEqual(
            sums(CONTROL / "candidates/minimal-v3-fail-closed/SHA256SUMS"),
            sums(CONTROL / "candidates/minimal-v3-stock-ns/SHA256SUMS"),
        )
        self.assertNotEqual(
            sums(CONTROL / "candidates/minimal-v3-stock-ns/SHA256SUMS")["init"],
            sums(CONTROL / "candidates/minimal-v3-mount-ns/SHA256SUMS")["init"],
        )
        self.assertEqual(
            sums(CONTROL / "candidates/minimal-v4-fail-closed/SHA256SUMS"),
            sums(CONTROL / "candidates/minimal-v4-stock-ns/SHA256SUMS"),
        )
        self.assertNotEqual(
            sums(CONTROL / "candidates/minimal-v4-stock-ns/SHA256SUMS")["init"],
            sums(CONTROL / "candidates/minimal-v4-mount-ns/SHA256SUMS")["init"],
        )
        for patch_name, digest in sums(CONTROL / "patches/SHA256SUMS").items():
            self.assertEqual(sha256(CONTROL / "patches" / patch_name), digest)

    def test_plan_is_candidate_focused_non_executable_and_hash_synchronized(self):
        plan = load_plan()
        self.assertEqual(plan["schema"], 4)
        self.assertEqual(plan["plan_id"], "CP-MINIMAL-V3-CANDIDATE-COMPARISON")
        self.assertFalse(plan["executable"])
        self.assertFalse(plan["approval_carried_forward"])
        self.assertIn("Standing-authorized", plan["authorization_policy"]["disposable_fixture"])
        self.assertIn("shared WSL", plan["authorization_policy"]["approval_required"])
        self.assertTrue(plan["status"].startswith("deferred-"))
        self.assertNotIn("recovery_install_contract", plan)

        patch = ROOT / plan["source"]["patch"]
        self.assertEqual(sha256(patch), plan["source"]["patch_sha256"])
        self.assertEqual(
            (CONTROL / "candidates/minimal-v1/source-diff.sha256").read_text(encoding="utf-8").strip(),
            plan["source"]["patch_sha256"],
        )
        self.assertEqual(set(plan["source_candidates"]), {
            "minimal-v3-fail-closed",
            "minimal-v3-stock-ns",
            "minimal-v3-mount-ns",
            "minimal-v4-fail-closed",
            "minimal-v4-stock-ns",
            "minimal-v4-mount-ns",
            "minimal-v5-mount-pid-ns",
        })
        for name, planned in plan["source_candidates"].items():
            candidate = key_values(CONTROL / "candidates" / name / "candidate.txt")
            artifacts = sums(CONTROL / "candidates" / name / "SHA256SUMS")
            with self.subTest(candidate=name):
                self.assertEqual(planned["runtime_evidence"], name in {"minimal-v3-stock-ns", "minimal-v4-stock-ns", "minimal-v4-mount-ns"})
                self.assertTrue(planned["reproducible"])
                self.assertEqual(planned["complete_source_diff_sha256"], candidate["complete_source_diff_sha256"])
                self.assertEqual(planned["init_sha256"], artifacts["init"])
                self.assertEqual(planned["initrd_sha256"], artifacts["initrd.img"])

    def test_pinned_inputs_and_controlled_build_remain_complete(self):
        plan = load_plan()
        inputs = plan["pinned_inputs"]
        self.assertTrue(inputs["windows_media"]["verified"])
        self.assertTrue(inputs["visual_studio"]["verified"])
        self.assertTrue(inputs["wsl_source"]["verified"])
        self.assertTrue(inputs["nuget"]["verified"])
        self.assertEqual(inputs["stock_wsl"]["tag"], "2.7.12")
        self.assertEqual(inputs["stock_wsl"]["version"], "2.7.12.0")
        self.assertEqual(inputs["stock_wsl"]["signature_status"], "Valid")
        self.assertRegex(inputs["wpr_profile"]["sha256"], r"^[0-9a-f]{64}$")
        rootfs = ROOT / inputs["toybox_rootfs"]["path"]
        self.assertEqual(rootfs.stat().st_size, inputs["toybox_rootfs"]["bytes"])
        self.assertEqual(sha256(rootfs), inputs["toybox_rootfs"]["sha256"])
        wpr_profile = ROOT / inputs["wpr_profile"]["path"]
        self.assertEqual(wpr_profile.stat().st_size, inputs["wpr_profile"]["bytes"])
        self.assertEqual(sha256(wpr_profile), inputs["wpr_profile"]["sha256"])

        build = plan["controlled_package_build"]
        self.assertTrue(build["executable"])
        self.assertFalse(build["approval_carried_forward"])
        self.assertEqual(build["source"]["commit"], plan["source"]["base_commit"])
        active = build["active_build"]
        build_script = ROOT / active["script"]
        self.assertEqual(sha256(build_script), active["script_sha256"])
        self.assertIn("Build-MinimalV3StockNs.ps1' -Execute", active["build_command"])
        self.assertTrue(active["completed"])
        self.assertRegex(active["package_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(active["output_manifest_sha256"], r"^[0-9a-f]{64}$")
        self.assertIn("separately recorded exact installation/restoration plan validation", build["execution_boundary"])
        build_source = build_script.read_text(encoding="utf-8")
        self.assertIn("if (-not $Execute) { exit 0 }", build_source)
        self.assertIn("FETCHCONTENT_FULLY_DISCONNECTED=ON", build_source)
        self.assertNotIn("Start-VM", build_source)
        self.assertNotIn("msiexec", build_source.lower())
        self.assertEqual(set(build["commands"]["candidate_commands"]), {
            "minimal-v3-stock-ns", "minimal-v3-mount-ns"
        })
        self.assertTrue(build["expected_outputs"]["closed_set"])
        self.assertIn("bin/x64/Release/wsl.msi", build["expected_outputs"]["msi"])
        overlay = ROOT / build["inputs"]["nuget"]["module_overlay"]
        self.assertEqual(sha256(overlay), build["inputs"]["nuget"]["module_overlay_sha256"])
        next_build = build["next_build"]
        next_script = ROOT / next_build["script"]
        self.assertEqual(next_build["candidate"], "minimal-v4-stock-ns")
        self.assertEqual(sha256(next_script), next_build["script_sha256"])
        self.assertEqual(next_build["complete_source_diff_sha256"], plan["source_candidates"]["minimal-v4-stock-ns"]["complete_source_diff_sha256"])
        self.assertTrue(next_build["completed"])
        self.assertEqual(next_build["package_sha256"], "50f17bd74d3b5aafb4f48507ad926b2f003255db55d463117a23bc2890206cda")
        self.assertEqual(next_build["fixture_final_state"], "Off")
        self.assertNotIn("msiexec", next_script.read_text(encoding="utf-8").lower())

    def test_fixed_probe_and_trial_contract_enforce_identical_comparison(self):
        plan = load_plan()
        contract = plan["candidate_trial_contract"]
        self.assertTrue(contract["executable"])
        self.assertFalse(contract["approval_carried_forward"])
        self.assertEqual(contract["comparison_order"], [
            "stock-wsl-2.7.12-calibration",
            "minimal-v3-stock-ns",
            "minimal-v4-stock-ns",
            "minimal-v4-mount-ns",
            "minimal-v5-mount-pid-ns",
        ])
        probe = ROOT / contract["fixed_probe"]["path"]
        self.assertEqual(sha256(probe), contract["fixed_probe"]["sha256"])
        source = probe.read_text(encoding="utf-8")
        self.assertIn("$SmokeCommand = 'test -r /proc/self/status", source)
        self.assertIn("Invoke-BoundedProcess 'toybox-smoke'", source)
        self.assertIn("wpr.exe -start", source)
        self.assertIn("Write-EvidenceManifest $EvidenceRoot", source)
        self.assertIn("expectedPackageSha256", source)
        self.assertIn("expectedProbeSha256", source)
        self.assertIn("candidateResult=$candidateResult", source)
        self.assertIn("'infrastructure-failure'", source)
        self.assertIn("'WslNotInstalled'", source)
        self.assertIn("Windows Subsystem for Linux is not installed", source)
        self.assertIn("'WslPrerequisitesDisabled'", source)
        self.assertIn("WSL2 is unable to start since virtualization is not enabled", source)
        for forbidden in ("Start-VM", "Stop-VM", "Restore-VMSnapshot", "Checkpoint-VM", "New-PSSession", "Invoke-Command", "msiexec"):
            self.assertNotIn(forbidden, source)
        evidence = " ".join(contract["evidence"]).lower()
        self.assertIn("stdout, stderr, exit code", evidence)
        self.assertIn("wpr/etw", evidence)
        self.assertIn("manifest", evidence)
        self.assertIn("recovery proof", evidence)
        self.assertIn("creates no candidate result", contract["infrastructure_boundary"])
        self.assertEqual(contract["ledger"]["trials"], "inventory/trials.csv")
        self.assertEqual(contract["ledger"]["metadata"], "inventory/trial-metadata.csv")
        stock_ns = contract["minimal_v3_stock_ns"]
        manifest_path = ROOT / stock_ns["candidate_manifest_path"]
        self.assertEqual(sha256(manifest_path), stock_ns["candidate_manifest_sha256"])
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(manifest["package_sha256"], stock_ns["package_sha256"])
        self.assertEqual(manifest["output_manifest_sha256"], stock_ns["output_manifest_sha256"])
        runner = ROOT / stock_ns["runner_path"]
        self.assertEqual(sha256(runner), stock_ns["runner_sha256"])
        runner_source = runner.read_text(encoding="utf-8")
        for required in (
            "MsiQueryProductState", "MsiGetProductInfo", "Invoke-Recovery $recoveryFailures",
            "Assert-ProductState $CandidateProductCode $false",
            "Assert-ProductState $StockProductCode $true $ExpectedVersion",
            "Invoke-FixedProbe $true", "TimeoutSeconds 45 -Execute",
        ):
            self.assertIn(required, runner_source)
        for forbidden in ("Start-VM", "Stop-VM", "Restore-VMSnapshot", "New-PSSession", "Invoke-Command"):
            self.assertNotIn(forbidden, runner_source)
        self.assertIn(stock_ns["candidate_product_code"], stock_ns["remove_candidate_command"])
        self.assertIn(stock_ns["stock_product_code"], stock_ns["remove_stock_command"])
        self.assertIn("stock-wsl-2.7.12-recovery", stock_ns["recovery_command"])
        attempt = contract["stock_calibration_attempt_001"]
        self.assertEqual(attempt["disposition"], "infrastructure-failure-no-candidate-result")
        self.assertFalse(attempt["candidate_ledger_row"])
        self.assertEqual(attempt["candidate_manifest_files_verified"], 17)
        self.assertEqual(attempt["fixture_final_state"], "Off")
        attempt2 = contract["stock_calibration_attempt_002"]
        self.assertEqual(attempt2["disposition"], "infrastructure-failure-no-candidate-result")
        self.assertTrue(attempt2["stock_msi_installed"])
        self.assertFalse(attempt2["candidate_ledger_row"])
        self.assertEqual(attempt2["fixture_final_state"], "Off")
        baseline = contract["fixture_baseline_preparation"]
        self.assertFalse(baseline["executable"])
        self.assertFalse(baseline["approval_carried_forward"])
        self.assertIn("Microsoft-Windows-Subsystem-Linux", baseline["enable_wsl_feature_command"])
        self.assertIn("VirtualMachinePlatform", baseline["enable_vmp_feature_command"])
        self.assertIn("--import Toybox-Minimal", baseline["toybox_import_command"])
        stock = contract["stock_calibration"]
        self.assertEqual(stock["trial_id"], "CP-STOCK-2.7.12-003")
        self.assertTrue(stock["executed"])
        self.assertEqual(stock["result"], "B6-T")
        self.assertEqual(stock["recovery_result"], "B6-T")
        self.assertTrue(stock["ledger_finalized"])
        self.assertEqual(stock["fixture_final_state"], "Off")
        stock_manifest = ROOT / stock["manifest_path"]
        self.assertEqual(sha256(stock_manifest), stock["manifest_sha256"])
        next_candidate = contract["minimal_v3_stock_ns"]
        self.assertFalse(next_candidate["executable"])
        self.assertFalse(next_candidate["approval_carried_forward"])
        self.assertEqual(next_candidate["reserved_trial_id"], "CP-MINIMAL-V3-STOCK-NS-001")
        self.assertEqual(next_candidate["status"], "runtime-finalized-fail-b2")
        self.assertEqual(next_candidate["runtime_result"]["highest_checkpoint"], "B2")
        self.assertEqual(next_candidate["runtime_result"]["recovery_result"], "B6-T")
        self.assertTrue(next_candidate["runtime_result"]["ledger_finalized"])
        self.assertEqual(next_candidate["runner_validation"]["status"], "complete")
        self.assertEqual(next_candidate["runner_validation"]["failure_paths_tested"], 13)
        self.assertFalse(next_candidate["runner_validation"]["candidate_install_performed"])
        self.assertEqual(next_candidate["runner_validation"]["fixture_final_state"], "Off")
        self.assertEqual(next_candidate["remaining_before_runtime"], [])
        self.assertIn("must not run again", next_candidate["runtime_boundary"])
        v4 = contract["minimal_v4_stock_ns"]
        self.assertFalse(v4["executable"])
        self.assertEqual(v4["status"], "runtime-finalized-pass-b6-t")
        self.assertEqual(v4["reserved_trial_id"], "CP-MINIMAL-V4-STOCK-NS-001")
        self.assertEqual(sha256(ROOT / v4["candidate_manifest_path"]), v4["candidate_manifest_sha256"])
        self.assertEqual(sha256(ROOT / v4["runner_path"]), v4["runner_sha256"])
        self.assertEqual(v4["runner_validation"]["failure_paths_tested"], 13)
        self.assertFalse(v4["runner_validation"]["candidate_install_performed"])
        self.assertEqual(v4["runner_validation"]["fixture_final_state"], "Off")
        self.assertEqual(v4["runtime_attempt_003"]["candidate_result"], "B6-T")
        self.assertEqual(v4["runtime_attempt_003"]["recovery_result"], "B6-T")
        self.assertTrue(v4["runtime_attempt_003"]["ledger_finalized"])
        self.assertEqual(v4["remaining_before_runtime"], [])
        mount_build = load_plan()["controlled_package_build"]["following_build"]
        self.assertTrue(mount_build["completed"])
        self.assertEqual(mount_build["candidate"], "minimal-v4-mount-ns")
        self.assertEqual(sha256(ROOT / mount_build["script"]), mount_build["script_sha256"])
        self.assertEqual(
            mount_build["complete_source_diff_sha256"],
            load_plan()["source_candidates"]["minimal-v4-mount-ns"]["complete_source_diff_sha256"],
        )
        self.assertEqual(mount_build["build_attempt_003"]["package_sha256"], mount_build["package_sha256"])
        self.assertEqual(mount_build["build_attempt_003"]["fixture_final_state"], "Off")
        mount = contract["minimal_v4_mount_ns"]
        self.assertFalse(mount["executable"])
        self.assertEqual(mount["status"], "runtime-finalized-fail-b3")
        self.assertEqual(mount["reserved_trial_id"], "CP-MINIMAL-V4-MOUNT-NS-001")
        self.assertEqual(sha256(ROOT / mount["candidate_manifest_path"]), mount["candidate_manifest_sha256"])
        self.assertEqual(sha256(ROOT / mount["runner_path"]), mount["runner_sha256"])
        self.assertEqual(mount["package_sha256"], mount_build["package_sha256"])
        self.assertEqual(mount["runner_local_validation"]["failure_paths_tested"], 13)
        self.assertEqual(mount["runner_validation_attempt_001"]["elevation_state"], "launching")
        self.assertEqual(mount["runner_validation_attempt_002"]["elevation_state"], "launching")
        self.assertEqual(mount["runner_validation_attempt_003"]["stock_product_state"], 5)
        self.assertEqual(mount["runner_validation_attempt_003"]["candidate_product_state"], -1)
        self.assertEqual(mount["runner_validation_attempt_003"]["fixture_final_state"], "Off")
        self.assertEqual(mount["runtime_attempt_001"]["elevation_state"], "launching")
        self.assertEqual(mount["runtime_attempt_002"]["elevation_state"], "launching")
        self.assertEqual(mount["runtime_attempt_003"]["elevation_state"], "launching")
        self.assertEqual(mount["runtime_attempt_004"]["candidate_result"], "B3")
        self.assertEqual(mount["runtime_attempt_004"]["recovery_result"], "B6-T")
        self.assertTrue(mount["runtime_attempt_004"]["ledger_finalized"])
        self.assertEqual(mount["remaining_before_runtime"], [])
        ablation = contract["next_minimality_ablation"]
        self.assertEqual(ablation["candidate_id"], "minimal-v5-mount-pid-ns")
        self.assertEqual(ablation["namespace_bundle"], ["mount", "pid"])
        self.assertEqual(sha256(ROOT / ablation["layer_patch"]), ablation["layer_patch_sha256"])
        self.assertTrue(ablation["linux_artifacts_byte_identical"])
        self.assertTrue(ablation["controlled_windows_package_built"])
        ablation_build = load_plan()["controlled_package_build"]["next_ablation_build"]
        self.assertTrue(ablation_build["completed"])
        self.assertEqual(ablation_build["candidate"], ablation["candidate_id"])
        self.assertEqual(sha256(ROOT / ablation_build["script"]), ablation_build["script_sha256"])
        self.assertEqual(sha256(ROOT / ablation_build["layer_patch"]), ablation_build["layer_patch_sha256"])
        self.assertEqual(ablation_build["complete_source_diff_sha256"], ablation["complete_source_diff_sha256"])
        v5 = contract["minimal_v5_mount_pid_ns"]
        self.assertFalse(v5["executable"])
        self.assertEqual(v5["status"], "runner-validation-elevation-blocked")
        self.assertEqual(sha256(ROOT / v5["candidate_manifest_path"]), v5["candidate_manifest_sha256"])
        self.assertEqual(sha256(ROOT / v5["runner_path"]), v5["runner_sha256"])
        self.assertEqual(v5["package_sha256"], ablation_build["package_sha256"])
        self.assertEqual(v5["runner_validation_attempt_001"]["elevation_state"], "launching")
        self.assertEqual(len(v5["remaining_before_runtime"]), 1)
        self.assertIn("-TimeoutSeconds 45 -Execute", stock["candidate_command"])
        self.assertIn(contract["fixed_probe"]["sha256"], stock["candidate_command"])
        self.assertIn(inputs := load_plan()["pinned_inputs"]["toybox_rootfs"]["sha256"], stock["candidate_command"])
        self.assertIn(inputs, stock["recovery_command"])
        self.assertIn("append nothing", contract["ledger"]["finalization"])

        result = subprocess.run([
            "pwsh", "-NoProfile", "-NonInteractive", "-File", str(probe),
            "-TrialId", "SELFTEST", "-CandidateId", "stock",
            "-CandidateManifestPath", "fixture",
            "-ExpectedCandidateManifestSha256", "0" * 64,
            "-PackagePath", "fixture", "-ExpectedPackageSha256", "0" * 64,
            "-ExpectedProbeSha256", "0" * 64,
            "-SelfTest",
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout)["passed"])

        runner_result = subprocess.run([
            "pwsh", "-NoProfile", "-NonInteractive", "-File", str(runner), "-SelfTest",
        ], capture_output=True, text=True)
        self.assertEqual(runner_result.returncode, 0, runner_result.stdout + runner_result.stderr)
        runner_self_test = json.loads(runner_result.stdout)
        self.assertTrue(runner_self_test["passed"])
        self.assertEqual(len(runner_self_test["failurePaths"]), 13)
        for path in runner_self_test["failurePaths"]:
            self.assertTrue(path["stockInstalled"])
            self.assertFalse(path["candidateInstalled"])

    def test_historical_vm_packet_tooling_is_not_in_the_active_tree(self):
        obsolete = (
            "Checkpoint-DisposableWslDevVm.ps1",
            "Diagnose-PowerShellDirect.ps1",
            "Install-StockWslBaseline.ps1",
            "Invoke-ZeroTouchRebuildR8.ps1",
            "New-DisposableWslDevVm.ps1",
            "Rebuild-DisposableWslDevVm.ps1",
            "Diagnose-StockWslCommands.ps1",
            "Diagnose-StockWslCommandsR2.ps1",
            "Invoke-StockWslBootCharacterization.ps1",
        )
        for name in obsolete:
            self.assertFalse((ROOT / "tools" / name).exists(), name)
        plan_text = PLAN_PATH.read_text(encoding="utf-8").lower()
        for historical_key in (
            "stock_baseline_approval_packet",
            "stock_wsl_command_diagnostic_packet",
            "powershell_direct_diagnostic_packet",
            "zero_touch_vm_rebuild_packet",
        ):
            self.assertNotIn(historical_key, plan_text)

    def test_protocol_and_source_share_the_same_base_commit(self):
        protocol = json.loads((CONTROL / "protocol/wsl-2.7.12.json").read_text(encoding="utf-8"))
        self.assertEqual(protocol["source"]["commit"], load_plan()["source"]["base_commit"])


if __name__ == "__main__":
    unittest.main()
