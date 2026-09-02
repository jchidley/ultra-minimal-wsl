from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "tools/Test-ProcessCommit.ps1"


class ProcessCommitTests(unittest.TestCase):
    def test_native_failure_self_test_passes(self) -> None:
        result = subprocess.run(
            ["pwsh.exe", "-NoProfile", "-File", str(SCRIPT), "-SelfTest"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Native nonzero self-test passed.", result.stdout)

    def test_commit_check_enables_native_error_policy_and_checks_both_diffs(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("$PSNativeCommandUseErrorActionPreference = $true", source)
        self.assertIn("@('diff', '--check')", source)
        self.assertIn("@('diff', '--cached', '--check')", source)


if __name__ == "__main__":
    unittest.main()
