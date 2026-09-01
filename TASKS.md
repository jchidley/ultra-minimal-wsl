# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Create the evidence-selected control-plane layer after `minimal-v6-excluded-initialize`:

1. remove only the unconditional `LaunchDistro` cross-distro temporary-mount block that moves `CROSS_DISTRO_SHARE_PATH` and sets its environment variable;
2. preserve all other minimal-v6 behavior, pass source-policy and mutation gates, and produce two byte-identical offline builds with complete hashes;
3. prepare and run one SQLite-recorded comparison using the unchanged `K-OVERLAY-PIDNS-001` kernel, fixed Toybox probe, protected broker, and independent stock `B6-T` recovery.

The finalized diagnostic's 216 `GuestLog` records prove ext4 mounted read-write and overlay construction succeeded. `LaunchDistro` then attempted the intentionally absent cross-distro share, failed with ENOENT at `main.cpp:1676`, entered the broad read-only/full-filesystem catch, and failed the same mount again before `CreateInstanceResult`. Recovery verified both manifests, zero diagnostic relays, absent `.wslconfig`, stock `B6-T`, and fixture Off. This evidence selects source reduction, not a Kconfig addition or unchanged rerun. Query `tools/experiment.py active` for exact executable operation state; this file does not own attempt identities.

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
