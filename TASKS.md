# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Test the retained `Debian2` practical-workload article under the frozen `ultra-minimal-wsl-v1` baseline in the dedicated disposable fixture. Preserve the article and all frozen Toybox, Alpine, Arch, and Debian candidates unchanged; run one bounded offline comparison that establishes the earliest practical-workload checkpoint or failure, captures exact package/kernel/article identities and diagnostics, restores pinned stock WSL, verifies the retained article remains usable under stock, and returns the fixture Off with absent `.wslconfig` and zero adapters.

The comparison must not copy secrets, credentials, SSH keys, or history, and must not promote any facility without narrow runtime evidence from the practical workload.

## Blocked

- No finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidate is eligible for an unchanged candidate-comparison rerun.
- No speculative Kconfig group or replacement fixture infrastructure is queued.

## Constraints

- Keep the frozen Toybox baseline and all completed Toybox, Alpine, Arch, and Debian evidence unchanged.
- A failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result.
- Preserve completed candidate records, terminal ledger rows, and trial evidence.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Proceed autonomously inside the disposable-fixture envelope. Require fresh explicit approval for any physical-host or shared-WSL effect and fail closed if isolation, hashes, offline status, or recovery cannot be proved.
