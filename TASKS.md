# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Prepare the next reduced-kernel candidate by promoting the now-proven `CONFIG_PID_NS` requirement while retaining the finalized `minimal-v5-mount-pid-ns` control plane. `CP-MINIMAL-V5-MOUNT-PID-NS-001` passed `B6-T` with independent stock recovery, proving mount-plus-PID sufficient and selecting PID semantics after the mount-only `B3` failure. Keep IPC and UTS namespaces omitted. Record the full config, parent, hashes, and reserved trial before any boot; build twice offline and continue through the unchanged fixed probe and recovery contract.

## Comparison queue

1. stock WSL 2.7.12 calibration with `toybox-minimal-wsl-rootfs.tar.gz` — complete at `B6-T` in `CP-STOCK-2.7.12-003`;
2. `minimal-v3-stock-ns` — superseded after its B2 sender-policy evidence;
3. `minimal-v4-stock-ns` — complete at `B6-T` in `CP-MINIMAL-V4-STOCK-NS-001`;
4. `minimal-v4-mount-ns` — complete at `B3` in `CP-MINIMAL-V4-MOUNT-NS-001`;
5. provisional v4 decision — full bundle retained pending a narrow PID ablation; mount-only rejected;
6. `minimal-v5-mount-pid-ns` — complete at `B6-T` in `CP-MINIMAL-V5-MOUNT-PID-NS-001`; retain mount plus PID, omit IPC and UTS;
7. next reduced-kernel candidate — promote `CONFIG_PID_NS` and verify the finalized minimal control plane against the reduced kernel.

Every comparison uses the identical Toybox smoke command, timeouts, instrumentation, rootfs, classification rules, and recovery proof.

## Blocked

- `minimal-v3-stock-ns` is finalized at `B2`; do not rerun the byte-identical candidate.
- IPC and UTS namespace semantics are rejected for the tested minimal contract; `CONFIG_PID_NS` is proven required and awaits incorporation into the next reduced-kernel candidate.
- Alpine, Arch, and Debian compatibility testing is blocked until `minimal-viable-wsl-v1` passes Toybox and is frozen.
- No speculative Kconfig group, VM-control diagnostic, or replacement infrastructure packet is queued.

## Constraints

- Do not retry or extend historical VM-rebuild, baseline-installer, command-diagnostic, PowerShell Direct, or checkpoint-race work.
- A fixture start/transport/recovery failure is infrastructure failure and creates no candidate result.
- Preserve completed candidate and trial evidence; never rewrite terminal ledger rows.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Disposable-fixture operations are standing-authorized inside the pinned, offline, hash-verified, plan-validated recovery envelope and proceed without human stage reviews or confirmations. Require fresh explicit approval for any physical-host or shared-WSL effect; fail closed if target isolation, hashes, offline status, or recovery cannot be proved.
