# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Establish the remaining freeze-readiness evidence for the retained Toybox-capable boundary, `minimal-v8-no-binfmt-mount` plus `K-PIDNS-001`:

1. audit every non-mkroot enabled facility against the durable classifications and resolve only documentation/inventory gaps supported by completed runtime evidence;
2. define one bounded acceptance operation for the required ten cold starts using the unchanged retained candidate, the registered `Start-FixtureBrokerRunV2.ps1` launcher, exact fixed Toybox probe per start, serial execution, unchanged timeouts/instrumentation, and exact stock recovery;
3. preserve per-start evidence and finalize only if all ten starts, cleanup, stock recovery, and fixture-Off checks pass.

The no-overlay minimal-v8 comparison passed `B6-T`, proving `CONFIG_OVERLAY_FS` unnecessary for the retained Toybox contract. Both minimal-v8 kernel siblings are finalized and must not be rerun as ordinary candidate comparisons. Do not rebuild either kernel or the package, change control-plane source, add `CONFIG_PROC_CHILDREN`, or add another Kconfig facility. The ten-start acceptance is a distinct completion gate, not another minimality trial. Query `tools/experiment.py active` for exact executable operation state; this file does not own attempt identities.

## Blocked

- Alpine, Arch, and Debian compatibility testing waits for a frozen Toybox-capable `minimal-viable-wsl-v1`.
- No finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidate is eligible for an unchanged candidate-comparison rerun.
- No speculative Kconfig group or replacement fixture infrastructure is queued.

## Constraints

- Keep the fixed Toybox smoke command, timeouts, instrumentation, classification rules, and recovery proof unchanged.
- A failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result.
- Preserve completed candidate records, terminal ledger rows, and trial evidence.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Proceed autonomously inside the disposable-fixture envelope. Require fresh explicit approval for any physical-host or shared-WSL effect and fail closed if isolation, hashes, offline status, or recovery cannot be proved.
