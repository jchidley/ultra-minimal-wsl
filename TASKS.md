# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns the target and experiment rules.

## Immediate

1. Preserve and commit the completed `K-OVERLAY-001` ordinary trial as inconclusive at the B0 evidence ceiling.
2. Obtain separate explicit approval for elevation and a byte-identical `K-OVERLAY-DIAG-001` WPR/ETW rerun.
3. Require canonical `safe:true`; do not stop a running distro automatically unless that interruption is also approved.
4. Classify whether overlay removed the prior crash without adding networking or another excluded feature.
5. Stop additive stock-init discovery if the next stable failure selects an excluded service rather than a retained control-contract primitive.

Continue excluding cgroups, networking/seccomp, Hyper-V networking, page reporting, and extra console support unless the earliest stable failure selects one of them.

## Minimal Viable WSL

After stock-init discovery reaches Toybox command dispatch:

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

- Continue reviewing the mkroot-to-Stage-1 Kconfig delta by coherent feature group.
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
