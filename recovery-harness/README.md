# Kernel-only recovery harness status

The host workflow uses only Microsoft’s supported external `kernel=` setting and never writes beneath `C:\Program Files\WSL`.

Current files:

- `..\tools\Invoke-WslKernelTrial.ps1` — plan, execute, and journal-recovery paths for external-kernel trials;
- `..\tools\Test-WslKernelTrial.ps1` — parser, guard, hash, safe-state fixture, and plan-only safety checks;
- `..\tools\Test-WslSafeState.ps1` — canonical JSON-producing live-state verifier with stable exit semantics;
- `expected-safe-state.json` — single versioned source for accepted `.wslconfig`, packaged-kernel, and packaged-initrd hashes;
- `..\candidates\wsl-2.7.11-stock-kernel` — external byte-identical packaged-kernel copy used for recovery validation;
- `trials\K-RECOVERY-001\` — stock-copy trial logs, exact config backup, and result evidence.

Verified:

- PowerShell parsing and isolated config transforms pass;
- plan mode leaves the packaged kernel, `.wslconfig`, and trial ledger unchanged;
- the safe-state verifier's UTF-16/native-output decoder, safe self-test, and unsafe custom-kernel fixture pass;
- candidates under the installed WSL directory and unguarded custom trials are rejected;
- `K-RECOVERY-001` selected the external stock copy and passed the Toybox smoke test at `B6-T`;
- the original `.wslconfig` hash `6539e72bf44774aefcf1aaff6f9673e59e9b091bcdb575f16ed879f272982577` was restored exactly with no `kernel=` setting;
- packaged kernel SHA-256 remained `d540850bfbf1beba3ded6b2965b9d0249b23fbcb3e90e7dc0845ac7ad86bc861`;
- stock Debian booted as `6.18.33.2-microsoft-standard-WSL2`;
- the terminal PASS row exists in `inventory\trials.csv` and no active recovery journal remains.

A PowerShell 5.1 lazy `File.ReadLines` enumerator kept the ledger open and blocked the first append after all runtime and restoration checks had passed. The journal was retained. The hardened `-Recover` path later restored and verified state again, booted stock Debian again, finalized the existing PASS result, and removed the journal. Ledger headers are now read eagerly, genuine transient locks are retried, repeated finalization is idempotent, and conflicting duplicate trial IDs are rejected. The self-test holds an isolated ledger open from another process and proves that retry succeeds.

Three custom-kernel trial rows now exist. `K-MKROOT-001` and the first `K-HVCORE-001` run both timed out with no output at `B0`; each restored the exact original configuration, verified packaged hashes, booted stock Debian, wrote a terminal FAIL row with `stock_restore_verified=yes`, and removed its journal. No custom initrd has been booted. A plan-only-by-default diagnostic wrapper combines this harness with Microsoft's pinned WSL 2.7.11 WPR profile, exact timing metadata, and transactionally restored `debugConsole=true`. Approved retry `K-HVCORE-DIAG-001` used that wrapper and proved `B1`, stock `/init` execution, no VMBus enumeration, missing console devices, and fatal VSOCK `EAFNOSUPPORT`. It restored stock state, booted stock Debian, stopped WPR, wrote a terminal recovery-verified row, and removed its journal. The raw/decoded ETL and analysis are in `trials\K-HVCORE-DIAG-001\`. A stale debug-console relay discovered after the run was stopped; the wrapper now removes only `wslrelay.exe` processes created by its invocation. The evidence-directed `K-HOSTCHAN-001` candidate is built and plan-validated but requires a new explicit decision before boot. See `..\PRE-DISPATCH-DIAGNOSTICS.md`. Reduced-init testing remains a separate controlled-package track, preferably in a disposable Hyper-V Windows VM.
