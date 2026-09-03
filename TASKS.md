# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Establish the Alpine compatibility boundary from the frozen `minimal-viable-wsl-v1` baseline:

1. preserve the frozen `minimal-v8-no-binfmt-mount` plus `K-PIDNS-001` Toybox baseline unchanged;
2. prepare the pinned Alpine rootfs and one bounded `B6-A` operation using the defined Alpine smoke contract, registered V2 broker launcher, unchanged timeouts/instrumentation, serial execution, and exact stock recovery;
3. if Alpine exposes a missing facility, attribute it as `PROVEN_ALPINE_REQUIRED` only through an evidence-selected additive candidate and controlled ablation; otherwise record that no compatibility addition is needed.

The complete non-mkroot audit and ten-cold-start acceptance are finalized in `CP-MINIMAL-V8-K-PIDNS-COLD-STARTS-001`; `STATUS.md` owns the frozen boundary and exact evidence summary. Do not reopen Toybox minimality, rebuild the frozen package or kernel without a changed compatibility candidate, or fold Alpine-specific support into the generic WSL classification.

## Blocked

- Arch and Debian compatibility testing wait for the preceding compatibility targets in the required Alpine → Arch → Debian sequence.
- No finalized v3, v4, v5, `K-PIDNS-001`, or `K-OVERLAY-PIDNS-001` candidate is eligible for an unchanged candidate-comparison rerun.
- No speculative Kconfig group or replacement fixture infrastructure is queued.

## Constraints

- Keep the frozen Toybox baseline and the plan-defined Alpine smoke command, timeouts, instrumentation, classification rules, and recovery proof unchanged.
- A failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result.
- Preserve completed candidate records, terminal ledger rows, and trial evidence.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Proceed autonomously inside the disposable-fixture envelope. Require fresh explicit approval for any physical-host or shared-WSL effect and fail closed if isolation, hashes, offline status, or recovery cannot be proved.
