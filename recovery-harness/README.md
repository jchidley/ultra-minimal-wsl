# Recovery evidence

The kernel harness uses only Microsoft’s external `kernel=` setting and never writes beneath `C:\Program Files\WSL`.

- `expected-safe-state.json` records the recovery-validated WSL package baseline.
- `trials/<TRIAL_ID>/` contains immutable result, analysis, extracted logs, and hashes. Controlled-package trials keep fixed-probe evidence under `candidate/` and independent stock proof under `recovery/`, with one final `SHA256SUMS`.
- `inventory/experiments.sqlite` is the transactional trial and operation ledger.
- Terminal rows and dispositions are immutable; update them only through `tools/experiment.py`.

Use:

- `tools/Test-WslSafeState.ps1` for canonical live-state verification;
- `tools/Test-WslKernelTrial.ps1` for non-mutating harness tests;
- `tools/Invoke-WslKernelTrial.ps1` for ordinary unelevated trials;
- `tools/Invoke-WslDiagnosticKernelTrial.ps1` only for separately approved elevated ETW diagnostics.

Kernel trials must restore the exact original `.wslconfig`, verify packaged hashes, prove stock Debian execution, stop diagnostics, remove their journal, and write terminal evidence. Controlled-package trials must restore the accepted stock package, pass the fixed stock recovery probe, stop diagnostics, and preserve both evidence trees before ledger finalization.

`trials/CP-STOCK-2.7.12-003/` is the accepted stock WSL 2.7.12/Toybox calibration baseline. Never rewrite a completed row or trial directory. See `WSL-DEVELOPMENT-AND-RECOVERY.md`.
