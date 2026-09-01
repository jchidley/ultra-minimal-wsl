# WSL candidate trial and recovery runbook

A custom WSL kernel is global to every WSL 2 distro. Use the guarded harness; never switch kernels manually during an experiment.

## Supported kernel override

Microsoft's packaged kernel remains at `C:\Program Files\WSL\tools\kernel`. The supported `.wslconfig` override points to a separate candidate image. Removing `kernel=` and shutting WSL down restores the packaged kernel; an empty value is not a fallback.

## Before any trial

1. Confirm the target boundary. Obtain explicit approval before interrupting the physical host or any shared WSL instance; no additional approval is required for operations wholly confined to the dedicated disposable fixture's pinned, offline, hash-verified, recoverable envelope.
2. Require `tools/Test-WslSafeState.ps1` to report `safe:true` for a shared WSL target, or independently verify the disposable fixture identity and recoverable baseline.
3. Record WSL version and packaged kernel/initrd hashes.
4. Preserve `.wslconfig` byte-for-byte.
5. Verify candidate config, image/package, rootfs, metadata, and hashes.
6. Synchronize inventory records and require SQLite integrity `ok`.
7. Pass the repository PowerShell, ShellCheck, record, and plan validations.
8. Reserve a unique evidence directory, but append no terminal ledger row yet.

A prepared candidate or valid plan implies no authorization outside the disposable-fixture envelope. Inside that envelope, complete the build → validate → test → recover → analyze loop autonomously; do not stop for operator stage review, routine confirmation, or gate-opening.

## Kernel-only trial

`tools/Invoke-WslKernelTrial.ps1` journals before changing `.wslconfig`, enforces serial execution and timeouts, restores the exact original file in `finally`, verifies packaged hashes, and boots a recovery distro before finalizing the ledger.

Use `tools/Invoke-WslDiagnosticKernelTrial.ps1` only when ordinary evidence cannot classify a pre-dispatch failure. Its elevated WPR path requires separate approval on the physical host or a shared WSL target, but is standing-authorized inside the disposable fixture envelope. Interpret only evidence inside the recorded interval.

## Controlled-package candidate trial

The accepted stock baseline is `CP-STOCK-2.7.12-003`: stock WSL 2.7.12 and the pinned Toybox rootfs passed the fixed probe and an independent recovery interval at `B6-T`. Reusing that baseline requires its recorded identities and recovery contract.

Compilation produces a closed output manifest, package hash, and build evidence. Once those outputs are recorded and the agent has plan-validated the exact installation/restoration operation, continue directly to installation and runtime testing. Compilation and runtime are standing-authorized when wholly confined to the disposable fixture envelope; the separation is evidentiary, not a human checkpoint.

The candidate experiment begins when the fixed probe starts its first `wsl.exe` process, not when an outer fixture starts.

1. Establish the recorded stock baseline using the already-reviewed fixture state.
2. Install exactly one hash-verified candidate.
3. Run `tools/Invoke-WslCandidateProbe.ps1` once with the fixed Toybox rootfs and candidate manifest.
4. Extract the complete evidence directory.
5. Restore the exact stock baseline and independently prove recovery.
6. Analyze the earliest supported B-gate.
7. Append one immutable terminal trial row only after evidence and recovery are complete.

Outer fixture start, toolchain/package build, command transport, and rollback are prerequisites. If any fails, record infrastructure failure outside the candidate ledger and do not alter the probe or classify the candidate. Do not develop infrastructure diagnostics as part of the minimisation loop.

## Evidence required

Every candidate interval records:

- exact WSL package, candidate, rootfs, and instrumentation hashes;
- separate arguments, start/end times, stdout, stderr, exit code, and timeout for each `wsl.exe` process;
- WSL ETW/WPR, relevant event delta, debug-console evidence where applicable, and new crash files;
- exact Toybox smoke output;
- WSL shutdown result;
- a hash manifest for all evidence;
- independent proof that the stock baseline was restored.

Finalize trial state transactionally in `inventory/experiments.sqlite` and preserve files under `recovery-harness/trials/<TRIAL_ID>/`. Detailed package identity and B0–B6-T reasoning belong in the trial's `analysis.json`.

## Recovery invariants

Every terminal candidate trial must leave:

- the original `.wslconfig` restored exactly;
- no custom kernel or candidate package selected;
- packaged kernel/initrd and stock package hashes verified;
- stock command execution proven;
- a terminal immutable ledger row;
- no active journal, WPR session, or diagnostic relay;
- analysis and hashes preserved under the trial evidence root.

A timeout does not prove a process or elevated child stopped. Verify durable state independently. If finalization is interrupted, use the existing harness recovery path; never hand-edit a completed ledger row.

## References

- WSL advanced settings: <https://learn.microsoft.com/windows/wsl/wsl-config>
- WSL development loop: <https://wsl.dev/dev-loop/>
- WSL diagnostics: <https://wsl.dev/debugging/>
- WSL boot process: <https://wsl.dev/technical-documentation/boot-process/>
