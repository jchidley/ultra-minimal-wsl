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

Five custom-kernel trial rows now exist. `K-MKROOT-001` and the first `K-HVCORE-001` run both timed out with no output at `B0`; each restored exact stock state. The diagnostic wrapper then proved `K-HVCORE-DIAG-001` reached `B1` but lacked VMBus enumeration and VSOCK. After `K-RECOVERY-002` revalidated WSL 2.7.12.0, approved `K-HOSTCHAN-001` proved `B2`; exact-source correlation selected missing Hyper-V storage. Approved `K-STORAGE-001` then proved `B3` through `storvsc`, two attached disks, and system-distro ext4 mount before reproducing Stage 3's exact `mini_init` segfault/panic. Exact source selects the narrow overlayfs path next. Every trial restored the exact original configuration, booted stock Debian, wrote a terminal row with `stock_restore_verified=yes`, stopped WPR, removed its journal, and cleaned up its diagnostic relay. Raw/decoded ETL, crash artifacts, analyses, and verified manifests are under `trials\K-HVCORE-DIAG-001\`, `trials\K-HOSTCHAN-001\`, and `trials\K-STORAGE-001\`. No custom initrd has been booted. See `..\PRE-DISPATCH-DIAGNOSTICS.md`; any next custom boot requires a new explicit decision.
