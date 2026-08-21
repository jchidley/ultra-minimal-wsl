# `minimal-v1` source-reduction audit

This audit separates code that the first patch removes from code that remains compiled but is rejected or merely unused. It is static evidence only; Windows compilation and runtime behavior remain deferred.

## Removed from the selected host startup path

- `WslCoreVm` no longer discovers, validates, attaches, or reserves MMIO for Microsoft's system distro.
- Early configuration advertises no swap, system distro, kernel-modules disk, debug shell, DNS tunnelling, page reporting, or memory-reclaim policy.
- `WslCoreVm` no longer accepts a GNS socket, creates a networking engine, creates NAT, or performs fallback networking.
- `WslCoreInstance` does not initialize a system distro or DrvFs and generates a zero-feature instance configuration.
- Process creation clears elevation, Windows interop, and OOBE flags and requests the non-elevated session leader.

These are direct source-path omissions rather than configuration assumptions.

## Explicitly rejected by Linux `mini_init`

- Any operation in the launch/import/export switch other than `LxMiniInitMessageLaunchInit`.
- Any launch flag, including system-distro, overlay, export, and verbose policy.
- Early configuration containing a system distro, swap, modules disk, debug shell, safe mode, DNS tunnelling, page reporting, or memory reclamation.
- Initial configuration containing networking mode, port tracking, ephemeral-port policy, DHCP, IPv6 policy, GUI, or GPU shares.

The protocol test suite independently mutates each excluded policy field and requires rejection.

## Disabled but still represented in the ABI

- The five-socket process ABI is preserved for compatibility. Interop flags and ports must remain disabled; the fifth socket is not proof that Windows executable interop is retained.
- Initialization messages retain broad stock layouts, but Minimal v1 requires zero DrvFs and feature fields and an invalid interop port.
- The notification channel and child-exit messages remain provisional lifecycle facilities.

## Still compiled or reachable

The patch is deliberately coarse and does not yet delete all stock implementation:

- Linux source still contains Plan 9, DrvFs, networking, DNS, seccomp, telemetry, import/export, mount, resize, and system-distro functions.
- Several broad `ProcessMessage` cases remain reachable on the mini-init channel even though the patched host does not send them. They need compile-time removal or explicit rejection before freezing the contract.
- Distro `init.cpp` still handles timezone, DrvFs remount, session, and other stock policy messages. Host omission is not a complete guest-side security boundary.
- `ProcessMessage` still clones the distro launcher with `CLONE_NEWIPC | CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS`. The current reduced kernel candidates have `IPC_NS`, `PID_NS`, and `UTS_NS` disabled, so direct command launch cannot be assumed to work. This is an ablation decision for the deferred runtime phase: either reduce the clone flags or add only the namespaces proved necessary.
- The Windows patch has not compiled, so unused-parameter, type, and package-integration issues remain possible despite static review.

## Link-time reduction

`MINIMAL_LINK=1` compiles each function/data item into its own section and asks pinned LLD 19.1.7 to garbage-collect unreachable sections. Two clean builds were byte-identical.

| Artifact | Full candidate | Minimal link | Change |
|---|---:|---:|---:|
| stripped `init` | 2,835,320 bytes | 2,511,032 bytes | -324,288 bytes (-11.4%) |
| `init.debug` | 36,298,568 bytes | 35,787,384 bytes | -511,184 bytes (-1.4%) |

This proves deterministic dead-section elimination, not behavioral necessity. It does not replace source deletion or runtime ablation.

## Fulfilled follow-on gates

`minimal-v2-fail-closed` was layered without rewriting this patch, and its stock/mount namespace siblings are recorded separately. Mini-init and distro-init now use a shared fail-closed allowlist, excluded process/configuration flags are rejected, semantic dispatch mutations are caught, and each Linux candidate built reproducibly twice. See `minimal-v2-audit.md`.

Five-socket wire compatibility remains provisional until an unmodified `wsl.exe` command succeeds. The Windows package must still compile in the deferred disposable VM before either namespace sibling is eligible for an approved boot.
