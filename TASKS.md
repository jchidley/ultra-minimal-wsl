# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Prepare one bounded diagnostic sibling of the finalized minimal-v6 plus `K-OVERLAY-PIDNS-001` comparison:

1. keep the package, kernel, rootfs, command, timeouts, ETW, package transaction, recovery proof, and fixture broker unchanged;
2. add only transactional `debugConsole=true` capture so the already-enabled kernel printk stream is recorded through `GuestLog`, with exact relay cleanup and `.wslconfig` restoration;
3. run one protected diagnostic interval, restore stock, prove independent stock `B6-T` recovery, preserve evidence, finalize the SQLite ledger, and choose the next change only from the captured guest failure.

Operation 013 is finalized at `B3`. Dynamic registered-distro association succeeded and `LaunchInit` began; overlay removed the prior absent-overlay signal-11 signature, but `WslCorePort` closed before `CreateInstanceResult` and ETW captured no guest log records. Stock recovery passed `B6-T`, all manifests verified, `.wslconfig` was absent, the fixture returned Off, and the ledger and immutable evidence are complete. This result selects diagnostic capture, not another Kconfig group or an unchanged candidate rerun. Operation 014 is prepared in `inventory/experiments.sqlite` with an atomic SQL-selected artifact set, a 19-path recovery matrix, protected controller, and `debugConsole`/relay-cleanup-only delta; independently validate and execute that exact contract.

## Blocked

- Alpine, Arch, and Debian compatibility testing waits for a frozen Toybox-capable `minimal-viable-wsl-v1`.
- No finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidate is eligible for an unchanged rerun.
- No speculative Kconfig group or replacement fixture infrastructure is queued.

## Constraints

- Keep the fixed Toybox smoke command, timeouts, instrumentation, classification rules, and recovery proof unchanged.
- A failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result.
- Preserve completed candidate records, terminal ledger rows, and trial evidence.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Proceed autonomously inside the disposable-fixture envelope. Require fresh explicit approval for any physical-host or shared-WSL effect and fail closed if isolation, hashes, offline status, or recovery cannot be proved.
