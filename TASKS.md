# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Localize the retained distro-init startup failure after `minimal-v7-no-cross-distro-launch`:

1. review the exact retained path from `ProcessLaunchInitMessage` through `LaunchInit`'s `execle` into distro-init startup and its first `CreateInstanceResult` response;
2. correlate that path with the finalized trace and 216 `GuestLog` records, distinguishing the initiating failure from the later `ErrorExit` cleanup read of `/proc/self/task/1/children`;
3. select at most one narrow source diagnostic or reduction that can expose or remove the earliest retained-contract blocker, while keeping `K-OVERLAY-PIDNS-001`, the fixed probe, timeouts, diagnostic instrumentation, broker, and recovery contract unchanged.

The minimal-v7 comparison removed the prior cross-distro ENOENT, broad read-only catch, and temporary-overlay signature but again finalized at `B3`: ext4 mounted read-write, `LaunchInit` began, and `WslCorePort` closed without `CreateInstanceResult`. The `/proc/self/task/1/children` error is reached only during cleanup and does not select `CONFIG_PROC_CHILDREN`. Do not rerun minimal v7 unchanged or add a Kconfig facility from this evidence. Query `tools/experiment.py active` for exact executable operation state; this file does not own attempt identities.

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
