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
        self.assertTrue(preparation["windows_media"]["verified"])
        self.assertEqual(preparation["windows_media"]["status"], "verified")
        self.assertEqual(
            preparation["visual_studio_layout"]["status"],
            "payload-verified-prerequisite-selection-incomplete",
        )
        self.assertTrue(preparation["visual_studio_layout"]["unresolved_prerequisites"])

        missing = " ".join(plan["missing_before_plan_validation"]).lower()
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
