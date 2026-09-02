# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Prove whether overlay remains necessary under the passing `minimal-v8-no-binfmt-mount` control plane:

1. derive a controlled comparison from terminal minimal-v8, replacing only the unchanged external kernel and kernel-config roles with the already-preserved `K-PIDNS-001` sibling;
2. retain the exact minimal-v8 package, fixed probe, timeouts, diagnostic instrumentation, broker, package transaction, and recovery contract;
3. run one serial candidate interval, preserve immutable candidate and stock-recovery evidence, and finalize transactionally.

Minimal v8 passed `B6-T`: the first `CreateInstanceResult` succeeded, the fixed command printed `toybox-ok` and exited zero, exact stock restoration and independent stock `B6-T` passed, `.wslconfig` was absent, relays were removed, and the fixture returned Off. The retained startup path no longer constructs the stock-only temporary overlay, so the existing `K-PIDNS-001` no-overlay sibling is now the narrow minimality comparison. Do not rerun minimal v8 with `K-OVERLAY-PIDNS-001`, rebuild either kernel, change the control-plane source, add `CONFIG_PROC_CHILDREN`, or add another Kconfig facility. Query `tools/experiment.py active` for exact executable operation state; this file does not own attempt identities.

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
