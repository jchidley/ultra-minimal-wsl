# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Prepare the next reduced control-plane source layer and retest the finalized `K-PIDNS-001` kernel:

1. remove mini-init `Initialize` operations that hard-fail on excluded inotify, loopback/networking, GNS/DNS, and cross-distro policy;
2. retain reachable resource-limit, diagnostic, hostname, command-relay, lifecycle, and fail-closed protocol behavior unless evidence selects a narrower change;
3. pass source-policy, protocol, record, mutation, and repository validation;
4. build the Linux artifacts twice offline in distinct `LFS-Builder` ext4 directories and require byte identity;
5. build and independently verify the hash-bound controlled package;
6. plan-validate and run one fixed `K-PIDNS-001` candidate interval in the disposable fixture, restore stock, prove independent stock `B6-T` recovery, preserve evidence, and finalize the ledger.

Do not treat the in-progress source, test, or package-preparation files as a completed candidate until all applicable gates above pass.

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
