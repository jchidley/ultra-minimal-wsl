# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns the target and experiment rules.

## Immediate

1. Keep additive stock-init kernel discovery frozen at `K-OVERLAY-DIAG-001`; do not add GNS or networking support.
2. Keep the large Windows environment phase deferred: do not download an ISO, install Visual Studio, create a Hyper-V VM, or request elevation until that later test is separately selected.
3. Preserve the completed post-profile recheck: all six fresh `JOBS=1` builds matched the committed candidate artifacts and metadata; a fresh `JOBS=2` fail-closed build also matched. Keep two jobs as the proven default on the 8 GiB builder and do not treat higher fan-out as validated.
4. Preserve `minimal-v1`, `minimal-v2-fail-closed`, `minimal-v2-stock-ns`, and `minimal-v2-mount-ns` patches/records; keep the 52-family policy enumeration and dispatch mutations as regression gates.
5. Continue source-only control-plane reduction/Kconfig review without selecting a namespace sibling. Do not add `CONFIG_IPC_NS`, `CONFIG_PID_NS`, or `CONFIG_UTS_NS` without deferred runtime evidence.
6. Treat any candidate source, ABI, or toolchain change as a new candidate requiring two distinct offline builds and preserved old/new evidence.
7. Keep `control-plane/deferred-runtime-plan.json` non-executable and carrying no approval. If the environment phase is later selected, first pin Windows media, compiler/SDK, package, checkpoint, and recovery inputs.
8. Before every commit, require the build-host, inventory/control-plane suites, pinned PowerShell 5.1 PSScriptAnalyzer profile, ShellCheck warning-or-higher checks, patch manifests, and documentation links to pass.

Continue excluding cgroups, networking/seccomp, Hyper-V networking, PTP, `CONFIG_PROC_CHILDREN`, page reporting, and extra console support. The latest errors occurred in excluded networking or shutdown cleanup and do not select those features.

## Minimal Viable WSL

Starting from the proven stock-init boundary:

1. Use the pinned host/guest source map in `WSL-CONTROL-PLANE-AUDIT.md` to define protocol fixtures for handshake, instance creation, command relay, exit status, and termination.
2. Retain only distro VHDX/ext4 mount, minimum root transition/isolation, process creation, stdio/exit relay, termination, and shutdown.
3. Patch the host not to advertise the system distro or await GNS/DNS and other excluded channels.
4. Remove GNS, DNS, interop/binfmt registration, DrvFs/Plan 9, WSLg/GPU, cgroup policy, cross-distro services, general disk management, and other audience-wide paths from the guest.
5. Prove every retained bundle necessary and freeze `minimal-viable-wsl-v1`.

Reduced-init deployment must use a controlled WSL package in a disposable Hyper-V Windows VM. The host’s installed initrd must not be replaced.

## Distribution compatibility

Starting from the frozen core:

1. test Alpine;
2. test Arch;
3. test Debian;
4. attribute and ablate any addition selected by each distro;
5. freeze `ultra-minimal-wsl-v1` after all four userspaces pass.

Before Arch or Debian trials, extend the durable harness/inventory result fields for `B6-ARCH` and `B6-D`.

## Parallel non-disruptive work

- Continue reviewing the mkroot-to-Stage-1 Kconfig delta by coherent feature group; use `control-plane/kernel-contract-review.md` as the retained-path starting point.
- Keep stock-init requirements separate from final control-plane requirements.
- Keep generated inventory exports out of Git; commit only durable manifests and annotations.

## Deferred profiles

- networking and DNS;
- DrvFs/9P/virtiofs;
- Windows executable interop;
- WSLg/GPU;
- systemd and cgroup policy;
- containers, netfilter, and BPF;
- USB/device forwarding;
- alternative filesystems such as Btrfs;
- import/export, resize, and arbitrary-disk management.
