# Work queue

`STATUS.md` owns verified current facts. `MINIMAL-BOOT-PLAN.md` owns strategy and acceptance criteria. This file contains incomplete work only.

## Active action

Prepare the next reduced control-plane source layer by removing the excluded inotify hard-fail from mini-init `Initialize`, then retest the finalized `k-pidns-001` kernel under the unchanged fixed probe and recovery contract. Both `CP-MINIMAL-V5-K-PIDNS-001` and the conservative overlay-parent sibling finalized at `B2`: mini-init exchanged capabilities and configuration, then the utility VM ended before registered-distro attachment completed. ETW ordering proves the invalid HCS storage handle was consequential. Do not add `CONFIG_INOTIFY_USER`: the source comment ties `max_user_watches` only to excluded Visual Studio Code Remote integration. Review the remaining `Initialize` operations for retained-contract reachability, keep the source change narrow and fail closed, build twice offline, rebuild the controlled package, and proceed through one fixed candidate interval plus mandatory stock recovery.

## Comparison queue

1. stock WSL 2.7.12 calibration with `toybox-minimal-wsl-rootfs.tar.gz` — complete at `B6-T` in `CP-STOCK-2.7.12-003`;
2. `minimal-v3-stock-ns` — superseded after its B2 sender-policy evidence;
3. `minimal-v4-stock-ns` — complete at `B6-T` in `CP-MINIMAL-V4-STOCK-NS-001`;
4. `minimal-v4-mount-ns` — complete at `B3` in `CP-MINIMAL-V4-MOUNT-NS-001`;
5. provisional v4 decision — full bundle retained pending a narrow PID ablation; mount-only rejected;
6. `minimal-v5-mount-pid-ns` — complete at `B6-T` in `CP-MINIMAL-V5-MOUNT-PID-NS-001`; retain mount plus PID, omit IPC and UTS;
7. `K-PIDNS-001` — complete at `B2`; dynamic VHDX association failed after mini-init configuration and independent stock recovery passed `B6-T`;
8. `K-OVERLAY-PIDNS-001` — complete at the same `B2`, rejecting overlay as the missing facility;
9. next source layer — remove the excluded inotify initialization hard-fail without enabling `CONFIG_INOTIFY_USER`, then retest `k-pidns-001`.

Every comparison uses the identical Toybox smoke command, timeouts, instrumentation, rootfs, classification rules, and recovery proof.

## Blocked

- `minimal-v3-stock-ns` is finalized at `B2`; do not rerun the byte-identical candidate.
- IPC and UTS namespace semantics are rejected for the tested minimal contract; `CONFIG_PID_NS` remains proven required and is incorporated in both finalized reduced-kernel candidates.
- The retained mini-init `Initialize` path hard-fails on the absent inotify sysctl before registered-distro attachment; source reduction is required before further kernel selection.
- Alpine, Arch, and Debian compatibility testing is blocked until `minimal-viable-wsl-v1` passes Toybox and is frozen.
- No speculative Kconfig group, VM-control diagnostic, or replacement infrastructure packet is queued.

## Constraints

- Do not retry or extend historical VM-rebuild, baseline-installer, command-diagnostic, PowerShell Direct, or checkpoint-race work.
- A fixture start/transport/recovery failure is infrastructure failure and creates no candidate result.
- Preserve completed candidate and trial evidence; never rewrite terminal ledger rows.
- Keep Linux builds on `LFS-Builder` ext4 and use only pinned, hash-verified offline inputs.
- Disposable-fixture operations are standing-authorized inside the pinned, offline, hash-verified, plan-validated recovery envelope and proceed without human stage reviews or confirmations. Require fresh explicit approval for any physical-host or shared-WSL effect; fail closed if target isolation, hashes, offline status, or recovery cannot be proved.
