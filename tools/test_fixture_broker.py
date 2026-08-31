import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).parents[1]
BROKER = ROOT / "tools" / "fixture-broker"


class FixtureBrokerSecurityTests(unittest.TestCase):
    def pwsh(self, script):
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-NonInteractive", "-Command", script],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            self.fail(f"PowerShell failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
        return result.stdout

    def test_all_broker_powershell_parses(self):
        for path in sorted(BROKER.iterdir()):
            if path.suffix.lower() not in {".ps1", ".psm1"}:
                continue
            escaped = str(path).replace("'", "''")
            with self.subTest(path=path.name):
                self.pwsh(
                    "$t=$null;$e=$null;"
                    f"[Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$t,[ref]$e)|Out-Null;"
                    "if($e.Count){$e|Out-String|Write-Error;exit 1}"
                )

    def test_policy_rejects_malformed_and_ambiguous_jobs(self):
        module = str(BROKER / "FixtureBroker.Policy.psm1").replace("'", "''")
        cases = [
            ({"schema": 1, "id": "ok", "sequence": 1, "operation": "execute"}, False),
            ({"schema": 1, "id": "ok", "sequence": 1, "operation": "execute", "workloadId": "trial"}, True),
            ({"schema": 1, "id": "ok", "sequence": 1, "operation": "finish", "workloadId": "trial"}, False),
            ({"schema": 1, "id": "ok", "sequence": 1, "operation": "status", "extra": "x"}, False),
            ({"schema": 1, "id": "../x", "sequence": 1, "operation": "status"}, False),
            ({"schema": 1, "id": "ok", "sequence": 0, "operation": "status"}, False),
            ({"schema": 2, "id": "ok", "sequence": 1, "operation": "status"}, False),
            ({"schema": 1, "id": "ok", "sequence": 1, "operation": "run-command"}, False),
        ]
        with tempfile.TemporaryDirectory() as temp:
            for index, (record, accepted) in enumerate(cases):
                path = Path(temp) / f"{index}.json"
                path.write_text(json.dumps(record), encoding="utf-8")
                escaped = str(path).replace("'", "''")
                command = (
                    f"Import-Module '{module}' -Force;"
                    f"try{{Read-StrictJob '{escaped}'|Out-Null;exit 0}}catch{{exit 42}}"
                )
                result = subprocess.run(["pwsh", "-NoProfile", "-NonInteractive", "-Command", command])
                with self.subTest(record=record):
                    self.assertEqual(result.returncode == 0, accepted)

    def test_policy_rejects_path_traversal_and_untrusted_acl(self):
        module = str(BROKER / "FixtureBroker.Policy.psm1").replace("'", "''")
        self.pwsh(
            f"Import-Module '{module}' -Force;"
            "$failed=0;"
            "try{Assert-RelativeOutputPath '..\\escape'|Out-Null}catch{$failed++};"
            "try{Assert-GuestPath 'C:\\controlled-package\\..\\Windows\\x' @('C:\\controlled-package')|Out-Null}catch{$failed++};"
            "$tmp=Join-Path $env:TEMP ('broker-acl-'+[guid]::NewGuid());mkdir $tmp|Out-Null;"
            "try{try{Assert-ProtectedAcl $tmp ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)|Out-Null}catch{$failed++}}finally{Remove-Item $tmp -Recurse -Force};"
            "if($failed-ne 3){exit 1}"
        )

    def test_broker_has_no_arbitrary_host_execution_surface(self):
        broker = (BROKER / "FixtureBroker.ps1").read_text(encoding="utf-8")
        policy = (BROKER / "FixtureBroker.Policy.psm1").read_text(encoding="utf-8")
        combined = broker + policy
        for forbidden in (
            "Invoke-Expression",
            "ScriptBlock]::Create",
            "TcpListener",
            "HttpListener",
            "NamedPipeServerStream",
            "-Verb RunAs",
        ):
            self.assertNotIn(forbidden, combined)
        self.assertIn("@('status','execute','finish')", policy)
        self.assertIn("Workload is not in the protected allowlist", broker)
        self.assertIn("Get-Workload ([string]$job.workloadId)", broker)
        self.assertNotIn("$job.scriptPath", broker)
        self.assertNotIn("$job.command", broker)

    def test_queue_is_snapshotted_and_workload_is_reverified(self):
        broker = (BROKER / "FixtureBroker.ps1").read_text(encoding="utf-8")
        self.assertIn("[IO.FileShare]::None", broker)
        self.assertIn("Copy-JobToProtectedSnapshot", broker)
        self.assertIn("Get-StreamSha256", broker)
        self.assertIn("Protected workload hash mismatch", broker)
        self.assertIn("Workload replay rejected", broker)
        self.assertIn("Job sequence is not the next expected value", broker)
        self.assertIn("Global\\UltraMinimalWslFixtureBroker-", broker)

    def test_installer_is_race_and_archive_traversal_resistant(self):
        installer = (BROKER / "Install-FixtureBroker.ps1").read_text(encoding="utf-8")
        self.assertIn("[IO.FileShare]::None", installer)
        self.assertIn("Bootstrap bundle hash mismatch", installer)
        self.assertIn("Unsafe archive entry", installer)
        self.assertIn("$env:ProgramFiles", installer)
        self.assertIn("'/inheritance:r'", installer)
        self.assertIn("Assert-ProtectedAcl", installer)

    def test_run_creation_requires_protected_output_and_credentials(self):
        creator = (BROKER / "New-FixtureBrokerRun.ps1").read_text(encoding="utf-8")
        self.assertIn("FixtureBroker-SecureWorkload: 1", creator)
        self.assertIn("ULTRAMINIMALWSL_SECURE_RUN_ROOT", creator)
        self.assertIn("ULTRAMINIMALWSL_SECURE_CREDENTIAL", creator)
        self.assertIn("[IO.FileShare]::None", creator)
        self.assertIn("$env:ProgramData", creator)
        self.assertNotIn("Invoke-Expression", creator)


if __name__ == "__main__":
    unittest.main()
