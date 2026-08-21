import hashlib
import json
from pathlib import Path
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

    def test_plan_contains_environment_recovery_and_host_safety_gates(self):
        plan = json.loads((CONTROL / "deferred-runtime-plan.json").read_text(encoding="utf-8"))
        missing = " ".join(plan["missing_before_plan_validation"]).lower()
        self.assertIn("windows installation media", missing)
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


if __name__ == "__main__":
    unittest.main()
