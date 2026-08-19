# Work queue

`STATUS.md` owns current facts; `MINIMAL-BOOT-PLAN.md` owns the target and experiment rules.

## Immediate

1. Obtain fresh explicit approval before any `K-OVERLAY-001` boot.
2. Require canonical `safe:true`; do not stop the currently running distro automatically.
3. Run the ordinary unelevated kernel harness first.
4. Preserve trial evidence, append metadata, synchronize SQLite, and classify the highest checkpoint.
5. Use elevated WPR/ETW diagnostics only if ordinary evidence is insufficient and separately approved.

Continue excluding cgroups, networking/seccomp, Hyper-V networking, page reporting, and extra console support unless the earliest stable failure selects one of them.

## Minimal Viable WSL

After stock-init discovery reaches Toybox command dispatch:

1. Map the smallest retained `wslservice.exe` handshake and command protocol.
2. Retain only distro VHDX/ext4 mount, minimum root transition/isolation, process creation, stdio/exit relay, termination, and shutdown.
3. Remove GNS, DNS, interop/binfmt registration, DrvFs/Plan 9, WSLg/GPU, cgroup policy, cross-distro services, general disk management, and other audience-wide paths.
4. Remove Microsoft’s system distro and overlay if command dispatch works without them.
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
