# Recovery evidence

The kernel harness uses only Microsoft’s external `kernel=` setting and never writes beneath `C:\Program Files\WSL`.

- `expected-safe-state.json` records the recovery-validated WSL package baseline.
- `trials/<TRIAL_ID>/` contains immutable result, analysis, extracted logs, and hashes.
- `inventory/trials.csv` is the append-only ledger.
- `inventory/trial-metadata.csv` supplements historical rows.

Use:

- `tools/Test-WslSafeState.ps1` for canonical live-state verification;
- `tools/Test-WslKernelTrial.ps1` for non-mutating harness tests;
- `tools/Invoke-WslKernelTrial.ps1` for ordinary unelevated trials;
- `tools/Invoke-WslDiagnosticKernelTrial.ps1` only for separately approved elevated ETW diagnostics.

Every completed trial must restore the exact original `.wslconfig`, verify packaged hashes, prove stock Debian execution, stop diagnostics, remove its journal, and write terminal evidence. Never rewrite a completed row or trial directory. See `WSL-DEVELOPMENT-AND-RECOVERY.md`.
