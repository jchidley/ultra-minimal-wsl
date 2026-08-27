import hashlib
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).parents[1]
CONTROL = ROOT / "control-plane"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def key_values(path):
    return dict(line.rstrip("\n").split("=", 1) for line in path.read_text(encoding="utf-8").splitlines() if line)


def sums(path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        digest, name = line.split(None, 1)
        result[name.strip()] = digest
    return result


class ControlPlaneRecordTests(unittest.TestCase):
    def test_fail_closed_patch_embeds_and_uses_the_recorded_policy_seam(self):
        patch = (CONTROL / "patches/0002-minimal-v2-fail-closed.patch").read_text(encoding="utf-8")
        marker = "diff --git a/src/linux/init/minimal_policy.h b/src/linux/init/minimal_policy.h"
        self.assertIn(marker, patch)
        policy_patch = patch.split(marker, 1)[1]
        policy_lines = []
        in_hunk = False
        for line in policy_patch.splitlines():
            if line.startswith("diff --git "):
                break
            if line.startswith("@@"):
                in_hunk = True
                continue
            if in_hunk and line.startswith("+") and not line.startswith("+++"):
                policy_lines.append(line[1:])
        embedded = "\n".join(policy_lines) + "\n"
        canonical = (CONTROL / "policy/minimal-v2-policy.h").read_text(encoding="utf-8")
        self.assertEqual(embedded, canonical)

        def cases(function_name):
            body = canonical.split(f"constexpr bool {function_name}", 1)[1].split("}", 1)[0]
            return set(re.findall(r"case (Lx[A-Za-z0-9]+):", body))

        self.assertEqual(cases("IsMiniInitRequestAllowed"), {
            "LxMiniInitMessageEarlyConfig",
            "LxMiniInitMessageInitialConfig",
            "LxMiniInitMessageLaunchInit",
        })
        self.assertEqual(cases("IsDistroControlRequestAllowed"), {
            "LxInitMessageCreateSession",
            "LxInitMessageInitialize",
            "LxInitMessageTerminateInstance",
            "LxInitCreateProcess",
        })
        self.assertIn("return Type == LxInitMessageCreateProcessUtilityVm;", canonical)
        self.assertIn("(Flags & ~ConsoleFlags) == 0", canonical)

        for call in (
            "IsMiniInitRequestAllowed(Type)",
            "IsDistroControlRequestAllowed(Header->MessageType)",
            "IsSessionRequestAllowed(Message->Header.MessageType)",
            "AreDirectProcessFlagsAllowed(CreateProcess.Common.Flags)",
        ):
            self.assertIn(call, patch)

    def test_no_interop_layer_removes_the_mini_init_hard_fail_only(self):
        patch = (CONTROL / "patches/0004-minimal-v3-no-interop.patch").read_text(encoding="utf-8")
        self.assertEqual(patch.count("diff --git "), 1)
        self.assertIn("a/src/linux/init/main.cpp b/src/linux/init/main.cpp", patch)
        removed = {line[1:].strip() for line in patch.splitlines() if line.startswith("-")}
        added = {line[1:].strip() for line in patch.splitlines() if line.startswith("+")}
        for excluded in (
            '#include "binfmt.h"',
            '#define BINFMT_PATH PROCFS_PATH "/sys/fs/binfmt_misc"',
            'if (UtilMount(nullptr, BINFMT_PATH, "binfmt_misc", MS_RELATIME, nullptr) < 0)',
            'if (WriteToFile(BINFMT_PATH "/register", BINFMT_REGISTER_STRING) < 0)',
        ):
            self.assertIn(excluded, removed)
            self.assertNotIn(excluded, added)
        self.assertNotIn("a/src/linux/init/config.cpp b/src/linux/init/config.cpp", patch)

    def test_namespace_variants_change_only_the_coherent_clone_bundle(self):
        for name in ("0003-minimal-v2-mount-ns.patch", "0005-minimal-v3-mount-ns.patch"):
            patch = (CONTROL / "patches" / name).read_text(encoding="utf-8")
            with self.subTest(patch=name):
                self.assertEqual(patch.count("diff --git "), 1)
                self.assertIn("a/src/linux/init/main.cpp b/src/linux/init/main.cpp", patch)
                removed = {line[1:].strip() for line in patch.splitlines() if line.startswith("-")}
                added = {line[1:].strip() for line in patch.splitlines() if line.startswith("+")}
                self.assertIn("(CLONE_NEWIPC | CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS | SIGCHLD));", removed)
                self.assertIn("(CLONE_NEWNS | SIGCHLD));", added)

    def test_candidate_records_and_patch_manifest_are_synchronized(self):
        profile_digest = hashlib.sha256()
        for path in (
            ROOT / "build-host/lfs-builder-profile.env",
            ROOT / "build-host/debian-snapshot.list",
            ROOT / "build-host/packages.tsv",
        ):
            profile_digest.update(path.read_bytes())
        expected_profile = profile_digest.hexdigest()

        expected = {
            "minimal-v2-fail-closed": {
                "parent_candidate": "minimal-v1",
                "diff": "6cb9e58956fc492230665acfe8791aa180dd62a0120070062ed5396e8e349759",
            },
            "minimal-v2-stock-ns": {
                "parent_candidate": "minimal-v2-fail-closed",
                "diff": "6cb9e58956fc492230665acfe8791aa180dd62a0120070062ed5396e8e349759",
            },
            "minimal-v2-mount-ns": {
                "parent_candidate": "minimal-v2-fail-closed",
                "diff": "b3c8cb69ae1a88b648c7dfa021dccaaf108930a337c1cff72e4768de936c4358",
            },
            "minimal-v3-fail-closed": {
                "parent_candidate": "minimal-v2-fail-closed",
                "diff": "97935ccd9541bb221e87cf2dee746cdcff221b5b69d98d3e43b42fddf69576ad",
            },
            "minimal-v3-stock-ns": {
                "parent_candidate": "minimal-v3-fail-closed",
                "diff": "97935ccd9541bb221e87cf2dee746cdcff221b5b69d98d3e43b42fddf69576ad",
            },
            "minimal-v3-mount-ns": {
                "parent_candidate": "minimal-v3-fail-closed",
                "diff": "5c36be2fce4bf497d1c480f7fac570089f9ba906b236b6fa9503f5820166058c",
            },
        }
        for name, values in expected.items():
            directory = CONTROL / "candidates" / name
            candidate = key_values(directory / "candidate.txt")
            metadata = key_values(directory / "build-metadata.txt")
            reproducibility = key_values(directory / "reproducibility.txt")
            recorded_sums = sums(directory / "SHA256SUMS")
            source_diff = (directory / "source-diff.sha256").read_text(encoding="utf-8").strip()

            with self.subTest(candidate=name):
                self.assertEqual(candidate["parent_candidate"], values["parent_candidate"])
                self.assertEqual(candidate["complete_source_diff_sha256"], values["diff"])
                self.assertEqual(source_diff, values["diff"])
                self.assertEqual(metadata["source_patch_sha256"], values["diff"])
                self.assertEqual(metadata["source_commit"], candidate["source_commit"])
                if candidate["layer_patch"] != "none":
                    self.assertEqual(sha256(ROOT / candidate["layer_patch"]), candidate["layer_patch_sha256"])
                self.assertEqual(metadata["minimal_link"], "1")
                self.assertEqual(reproducibility["offline"], "1")
                self.assertEqual(metadata["builder_profile_sha256"], expected_profile)
                self.assertEqual(metadata["builder_profile_sha256"], reproducibility["builder_profile_sha256"])
                self.assertEqual(reproducibility["runs"], "2")
                self.assertEqual(reproducibility["result"], "byte-identical")
                self.assertEqual(recorded_sums["init"], reproducibility["init_sha256"])
                self.assertEqual(recorded_sums["init.debug"], reproducibility["init_debug_sha256"])
                self.assertEqual(recorded_sums["initrd.img"], reproducibility["initrd_sha256"])

        fail_sums = sums(CONTROL / "candidates/minimal-v2-fail-closed/SHA256SUMS")
        stock_sums = sums(CONTROL / "candidates/minimal-v2-stock-ns/SHA256SUMS")
        mount_sums = sums(CONTROL / "candidates/minimal-v2-mount-ns/SHA256SUMS")
        self.assertEqual(fail_sums, stock_sums)
        self.assertNotEqual(fail_sums["init"], mount_sums["init"])

        fail_sums = sums(CONTROL / "candidates/minimal-v3-fail-closed/SHA256SUMS")
        stock_sums = sums(CONTROL / "candidates/minimal-v3-stock-ns/SHA256SUMS")
        mount_sums = sums(CONTROL / "candidates/minimal-v3-mount-ns/SHA256SUMS")
        self.assertEqual(fail_sums, stock_sums)
        self.assertNotEqual(fail_sums["init"], mount_sums["init"])

        manifest = sums(CONTROL / "patches/SHA256SUMS")
        for patch_name, digest in manifest.items():
            self.assertEqual(sha256(CONTROL / "patches" / patch_name), digest)

    def test_deferred_plan_is_non_executable_and_hash_synchronized(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        self.assertFalse(plan["executable"])
        self.assertFalse(plan["approval_carried_forward"])
        self.assertTrue(plan["status"].startswith("deferred-"))

        patch = ROOT / plan["source"]["patch"]
        self.assertEqual(sha256(patch), plan["source"]["patch_sha256"])
        self.assertEqual(
            (CONTROL / "candidates/minimal-v1/source-diff.sha256").read_text(encoding="utf-8").strip(),
            plan["source"]["patch_sha256"],
        )

        recorded_sums = sums(CONTROL / "candidates/minimal-v1/SHA256SUMS")
        self.assertEqual(recorded_sums["init"], plan["linux_build"]["init_sha256"])
        self.assertEqual(recorded_sums["init.debug"], plan["linux_build"]["init_debug_sha256"])
        self.assertEqual(recorded_sums["initrd.img"], plan["linux_build"]["initrd_sha256"])

        metadata = key_values(CONTROL / "candidates/minimal-v1/build-metadata.txt")
        self.assertEqual(metadata["source_base_commit"], plan["source"]["base_commit"])
        self.assertEqual(metadata["source_patch_sha256"], plan["source"]["patch_sha256"])
        self.assertEqual(metadata["minimal_link"], "1")
        self.assertTrue(plan["linux_build"]["minimal_link"])

    def test_plan_candidates_match_durable_records(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        self.assertEqual(plan["schema"], 3)
        self.assertEqual(set(plan["source_candidates"]), {
            "minimal-v3-fail-closed",
            "minimal-v3-stock-ns",
            "minimal-v3-mount-ns",
        })
        for name, planned in plan["source_candidates"].items():
            directory = CONTROL / "candidates" / name
            candidate = key_values(directory / "candidate.txt")
            recorded_sums = sums(directory / "SHA256SUMS")
            with self.subTest(candidate=name):
                self.assertFalse(planned["runtime_evidence"])
                self.assertTrue(planned["reproducible"])
                self.assertEqual(planned["complete_source_diff_sha256"], candidate["complete_source_diff_sha256"])
                self.assertEqual(planned["init_sha256"], recorded_sums["init"])
                self.assertEqual(planned["init_debug_sha256"], recorded_sums["init.debug"])
                self.assertEqual(planned["initrd_sha256"], recorded_sums["initrd.img"])

    def test_plan_contains_environment_recovery_and_host_safety_gates(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        preparation = plan["input_preparation"]
        self.assertEqual(
            preparation["status"],
            "authorized-core-input-cache-complete-stock-package-cached-build-procedure-pinned",
        )
        self.assertTrue(preparation["windows_media"]["verified"])
        self.assertEqual(preparation["windows_media"]["status"], "verified")
        self.assertEqual(
            preparation["visual_studio_layout"]["status"],
            "payload-verified-prerequisite-selection-incomplete",
        )
        self.assertEqual(
            preparation["visual_studio_community"]["status"],
            "catalog-and-license-audit-passed-layout-verified",
        )
        self.assertTrue(preparation["visual_studio_layout"]["unresolved_prerequisites"])

        stock = preparation["stock_wsl_package"]
        self.assertEqual(stock["status"], "verified-cached-non-executable")
        self.assertEqual(stock["release"]["tag"], "2.7.12")
        self.assertEqual(stock["asset"]["id"], 519890230)
        self.assertEqual(stock["asset"]["declared_bytes"], stock["cache"]["bytes"])
        self.assertEqual(stock["asset"]["declared_digest"], "sha256:" + stock["cache"]["sha256"])
        self.assertTrue(stock["cache"]["verified"])
        self.assertEqual(stock["signature"]["status"], "Valid")
        self.assertEqual(stock["msi_identity"]["product_version"], "2.7.12.0")
        self.assertEqual(stock["msi_identity"]["architecture"], "x64")
        self.assertEqual(stock["nested_payload"]["msix_identity"]["version"], "2.7.12.0")
        self.assertEqual(stock["nested_payload"]["msix_identity"]["processor_architecture"], "x64")
        self.assertTrue(stock["recovery_comparison"]["kernel"]["matches_expected"])
        self.assertTrue(stock["recovery_comparison"]["initrd"]["matches_expected"])

        attempt = plan["recovery_install_contract"]["baseline_attempt"]
        self.assertEqual(attempt["status"], "blocked-before-stock-install")
        self.assertFalse(attempt["guest_control"]["guest_service_interface"]["enabled"])
        self.assertIn("Credential", attempt["guest_control"]["powershell_direct"])
        self.assertFalse(attempt["stock_install_executed"])
        self.assertFalse(attempt["controlled_baseline_checkpoint_created"])
        self.assertEqual(attempt["final_state"], "Off")
        capability = attempt["guest_control_capability_evidence"]
        self.assertEqual(capability["status"], "authoritative-comparison-complete-no-selection")
        self.assertIn("unselected", capability["result"])
        self.assertIn("insufficient alone", capability["result"])
        self.assertIn("credential", capability["powershell_direct"]["requirements"].lower())
        self.assertIn("not an arbitrary", capability["guest_service_interface"]["limitation"].lower())
        self.assertIn("verified Off", capability["recovery_requirement"])

        selection = plan["recovery_install_contract"]["guest_control_selection"]
        self.assertEqual(selection["status"], "powershell-direct-proven-account-provisioned")
        self.assertEqual(selection["mechanism"], "PowerShell Direct")
        self.assertFalse(selection["executable"])
        self.assertFalse(selection["approval_carried_forward"])
        account = selection["account"]
        self.assertEqual(account["username_length"], 12)
        self.assertEqual(len(account["username"]), account["username_length"])
        self.assertEqual(account["password_length"], 12)
        self.assertTrue(account["password_generated"])
        self.assertFalse(account["password_recorded_in_repository"])
        self.assertEqual(
            set(account),
            {
                "username", "username_length", "password_length", "password_generated",
                "password_recorded_in_repository", "scope", "reuse", "disposition",
            },
        )
        provisioning = selection["account_provisioning"]
        self.assertEqual(provisioning["status"], "completed-and-independently-verified")
        self.assertIn("authenticated", provisioning["result"])
        self.assertTrue(provisioning["clean_shutdown_requested"])
        self.assertEqual(provisioning["operation_final_vm_state"], "Off")
        self.assertEqual(provisioning["independent_final_vm_state"], "Off")
        self.assertEqual(provisioning["independent_attached_vm_disks"], 0)
        discovery = provisioning["bootstrap_discovery"]
        self.assertEqual(discovery["autologon_registry_password"], "absent after the one-time autologon was consumed")
        self.assertIn("failed to unload", discovery["initial_cleanup_failure"])
        self.assertIn("detached", discovery["recovery_result"])

        missing = " ".join(plan["missing_before_controlled_execution"]).lower()
        self.assertNotIn("windows installation media", missing)
        self.assertIn("compiler", missing)
        self.assertIn("checkpoint", missing)
        self.assertIn("approval", missing)

        sequence = " ".join(plan["runtime_sequence"]).lower()
        self.assertIn("restore controlled-package-baseline", sequence)
        self.assertIn("prove stock wsl command execution", sequence)

        stops = " ".join(plan["stop_conditions"]).lower()
        self.assertIn("physical host", stops)
        self.assertIn("required hash differs", stops)
        self.assertIn("timeout", stops)

    def test_stock_baseline_packet_binds_artifact_and_fails_closed(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        packet = plan["recovery_install_contract"]["stock_baseline_approval_packet"]
        artifact = ROOT / packet["artifact"]
        self.assertTrue(packet["safe"])
        self.assertFalse(packet["executable"])
        self.assertFalse(packet["approval_carried_forward"])
        self.assertEqual(packet["artifact_sha256"], sha256(artifact))
        self.assertEqual(packet["required_clean_shell_checkpoint"], "clean-shell")
        self.assertIn("Get-Credential", packet["exact_command"])
        self.assertIn("-Message", packet["exact_command"])
        self.assertIn("-Execute", packet["exact_command"])
        self.assertIn("4cl8y955frge", packet["exact_command"])
        self.assertEqual(packet["status"], "runtime-blocked-powershell-direct-unavailable")
        self.assertTrue(packet["review_result"]["plan_validated"])
        self.assertFalse(packet["review_result"]["approval_present"])
        self.assertTrue(packet["review_result"]["executed"])
        self.assertIn("unsupported MSI exit code", " ".join(packet["stop_conditions"]))
        self.assertIn("not pinned", packet["open_blocker"])
        source = artifact.read_text(encoding="utf-8")
        self.assertIn("$ExpectedMsiSha256", source)
        self.assertIn("$ExpectedCheckpoint", source)
        self.assertIn("$ExpectedCleanShellCheckpoint", source)
        self.assertIn("Get-VMSnapshot -VM $vm -Name $ExpectedCleanShellCheckpoint", source)
        self.assertIn("Required checkpoint '$ExpectedCleanShellCheckpoint' does not exist", source)
        self.assertIn("function Get-TargetVm", source)
        self.assertIn("Hyper-V\\Get-VM -Name $Name", source)
        self.assertNotIn("function Get-Vm(", source)
        self.assertIn("Assert-NoAttachedVmDisk", source)
        self.assertIn("Get-VMHardDiskDrive -VMName $Name", source)
        self.assertIn("Get-DiskImage -ImagePath $_.Path", source)
        self.assertNotIn("Get-DiskImage -ErrorAction", source)
        self.assertNotIn("Stop-VM -Name $ExpectedVmName -Shutdown", source)
        self.assertIn("Stop-VM -Name $ExpectedVmName -Confirm:$false", source)
        self.assertIn("$sessionDeadline = [DateTime]::UtcNow.AddMinutes(10)", source)
        self.assertIn("New-PSSession -VMName $ExpectedVmName -Credential $GuestCredential", source)
        self.assertIn("Start-Sleep -Seconds 5", source)
        self.assertIn("PowerShell Direct session was unavailable after 10 minutes", source)
        self.assertIn("Guest .wslconfig must remain absent", source)
        self.assertNotIn("$guest.configSha256 -ne $script:Baseline.wslConfigSha256", source)
        self.assertIn("Checkpoint-DisposableWslDevVm.ps1", source)
        self.assertIn("Remove-PSSession", source)

    def test_powershell_direct_diagnostic_design_is_non_executable(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        packet = plan["recovery_install_contract"]["powershell_direct_diagnostic_packet"]
        self.assertTrue(packet["safe"])
        self.assertFalse(packet["executable"])
        self.assertFalse(packet["approval_carried_forward"])
        self.assertEqual(packet["status"], "blocked-manual-vmconnect-diagnostic-required")
        scope = packet["scope"]
        self.assertEqual(scope["vm"], "ultra-minimal-wsl-dev")
        self.assertEqual(scope["initial_state"], "Off")
        self.assertEqual(scope["final_state"], "Off")
        self.assertEqual(scope["required_existing_checkpoint"], "clean-shell")
        self.assertEqual(scope["required_absent_checkpoint"], "controlled-package-baseline")
        self.assertEqual(scope["required_host_attached_vm_disks"], 0)
        self.assertFalse(scope["network_dependency"])
        self.assertFalse(scope["installing"])
        urls = {source["url"] for source in packet["authoritative_sources"]}
        self.assertIn("https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell-direct", urls)
        self.assertIn("https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/integration-services", urls)
        procedure = " ".join(packet["proposed_procedure"]).lower()
        self.assertIn("vmconnect", procedure)
        self.assertIn("restart-service -name vmicvmsession", procedure)
        self.assertIn("new-pssession -vmname", procedure)
        self.assertIn("finally", procedure)
        exclusions = " ".join(packet["explicit_exclusions"]).lower()
        self.assertIn("not an executable artifact", exclusions)
        self.assertIn("not deterministic host command execution", exclusions)
        self.assertIn("no stock msi installation", exclusions)
        cleanup = " ".join(packet["cleanup_and_recovery"]).lower()
        self.assertIn("separate", cleanup)
        self.assertIn("off", cleanup)
        self.assertIn("zero attached disks", cleanup)
        boundary = packet["unresolved_boundary"].lower()
        self.assertIn("human", boundary)
        self.assertIn("host-side", boundary)
        self.assertIn("must not claim deterministic guest execution", boundary)

    def test_controlled_package_build_record_is_complete_and_fail_closed(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        build = plan["controlled_package_build"]
        self.assertFalse(build["executable"])
        self.assertEqual(build["status"], "prepared-source-backed-non-executable")
        self.assertEqual(build["source"]["commit"], plan["source"]["base_commit"])
        self.assertEqual(
            [item["sha256"] for item in build["source"]["candidate_patches"]["minimal-v3-stock-ns"]],
            [
                "3d54b4769fdb8c784f05387a9823af34fc0ee43f4a3533700d6eef2412f5381a",
                "47d57f86685e3adf00cf73866c1e27779b5195357c14eeda5fa441ce0e1934a0",
                "e68611ecc12ac556b8a8ffd84e7af9045ef552bf58cb6ddac2fe78a44825b981",
            ],
        )
        self.assertEqual(len(build["source"]["candidate_patches"]["minimal-v3-mount-ns"]), 4)
        self.assertEqual(build["inputs"]["nuget"]["module_overlay"], "control-plane/controlled-package-offline/FindNUGET.cmake")
        self.assertEqual(
            sha256(ROOT / build["inputs"]["nuget"]["module_overlay"]),
            build["inputs"]["nuget"]["module_overlay_sha256"],
        )
        self.assertTrue(build["inputs"]["nuget"]["local_source_only"])
        self.assertIn("-ConfigFile", build["inputs"]["nuget"]["restore_arguments"])
        self.assertIn("-NoCache", build["inputs"]["nuget"]["restore_arguments"])
        self.assertIn("CMAKE_MODULE_PATH", build["commands"]["configure"])
        self.assertEqual(set(build["commands"]["candidate_commands"]), {"minimal-v3-stock-ns", "minimal-v3-mount-ns"})
        for candidate_command in build["commands"]["candidate_commands"].values():
            self.assertIn("Visual Studio 17 2022", candidate_command["configure"])
            self.assertIn("x64", candidate_command["configure"])
            self.assertIn("CMAKE_MODULE_PATH", candidate_command["configure"])
            self.assertIn("msipackage", candidate_command["build"])
            self.assertIn("/m:2", candidate_command["build"])
        self.assertEqual(build["toolchain"]["platform"], "x64")
        self.assertEqual(build["toolchain"]["configuration"], "Release")
        self.assertEqual(build["toolchain"]["windows_sdk"], "10.0.26100.0")
        self.assertEqual(build["toolchain"]["package_version"], "2.7.12.0")
        self.assertTrue(build["expected_outputs"]["closed_set"])
        self.assertIn("bin/x64/Release/wsl.msi", [build["expected_outputs"]["msi"]])
        self.assertEqual(set(plan["recovery_install_contract"]["candidate_install_commands"]), {
            "minimal-v3-stock-ns",
            "minimal-v3-mount-ns",
        })
        self.assertIn("controlled-package-baseline", plan["recovery_install_contract"]["restore_command"])
        stock_install = plan["recovery_install_contract"]["stock_baseline"]["stock_package"]
        self.assertFalse(stock_install["executed"])
        self.assertIn("msiexec.exe /i", stock_install["install_command"])
        self.assertIn("2.7.12.0.x64.msi", stock_install["install_command"])
        self.assertIn("fresh explicit approval", " ".join(stock_install["pre_checks"]).lower())
        missing = " ".join(plan["missing_before_controlled_execution"]).lower()
        self.assertNotIn("exact fail-closed offline", missing)
        self.assertNotIn("pinned offline stock wsl", missing)
        self.assertIn("powershell direct", missing)
        self.assertIn("stock-baseline", missing)
        self.assertNotIn("account-bootstrap", missing)
        self.assertIn("compiler", missing)
        self.assertIn("checkpoint", missing)
        self.assertIn("approval", missing)
        stops = " ".join(build["stop_conditions"]).lower()
        self.assertIn("https", stops)
        self.assertIn("non-local", stops)
        self.assertIn("hash", stops)

    def test_protocol_and_source_share_the_same_base_commit(self):
        protocol = json.loads((CONTROL / "protocol/wsl-2.7.12.json").read_text(encoding="utf-8"))
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        self.assertEqual(protocol["source"]["commit"], plan["source"]["base_commit"])

    def test_static_restart_phase_is_named_and_non_destructive(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        static = plan["static_next_phase"]
        self.assertTrue((ROOT / static["restart_brief"]).is_file())
        self.assertEqual(static["preserved_parent"], "minimal-v2-fail-closed")
        self.assertEqual(
            static["new_candidates"],
            ["minimal-v3-fail-closed", "minimal-v3-stock-ns", "minimal-v3-mount-ns"],
        )
        claims = " ".join(static["forbidden_claims"]).lower()
        self.assertIn("no b4, b5, or b6", claims)
        self.assertIn("no namespace kconfig promotion", claims)
        self.assertIn("no approval carried", claims)


if __name__ == "__main__":
    unittest.main()
