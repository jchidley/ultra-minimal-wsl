# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Establish the Arch compatibility boundary from the unchanged frozen `minimal-viable-wsl-v1` baseline:

1. preserve `minimal-v8-no-binfmt-mount` plus `K-PIDNS-001` and the completed Alpine result unchanged;
2. prepare only pinned hash-verified offline Arch inputs and one bounded `B6-ARCH` operation using the defined Arch smoke contract, registered V2 broker launcher, unchanged timeouts/instrumentation, serial execution, and exact stock recovery;
3. if Arch exposes a missing facility, attribute it as `PROVEN_ARCH_REQUIRED` only through an evidence-selected additive candidate and controlled ablation; otherwise record that no compatibility addition is needed.

Alpine 3.24.0 passed `B6-A` without a kernel change in `CP-MINIMAL-V8-K-PIDNS-ALPINE-003`; no `PROVEN_ALPINE_REQUIRED` addition exists. `STATUS.md` owns the frozen boundary and exact evidence summary. Do not reopen Toybox or Alpine minimality, rebuild unchanged artifacts, or fold distro-specific support into the generic WSL classification.

## Blocked

- Debian compatibility testing waits for Arch in the required Alpine → Arch → Debian sequence.
- No finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidate is eligible for an unchanged candidate-comparison rerun.
- No speculative Kconfig group or replacement fixture infrastructure is queued.

## Constraints

- Keep the frozen Toybox baseline, completed Alpine evidence, and plan-defined Arch smoke command, timeouts, instrumentation, classification rules, and recovery proof unchanged.
- A failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result.
- Preserve completed candidate records, terminal ledger rows, and trial evidence.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Proceed autonomously inside the disposable-fixture envelope. Require fresh explicit approval for any physical-host or shared-WSL effect and fail closed if isolation, hashes, offline status, or recovery cannot be proved.
