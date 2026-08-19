# WSL control-plane audit

Status: reduced single-user control plane selected as the final target. The matching unmodified Linux-side init/initrd builds reproducibly. Kernel-only discovery will proceed first through Microsoft’s supported external-kernel setting with the stock initrd; reduced-init deployment is deferred to an isolated platform-development track. No custom WSL boot or installed WSL modification has occurred.

## Question

Microsoft’s WSL init processes serve a broad product audience. This experiment serves one user and should not retain kernel facilities merely because optional WSL services expect them. The goal is to separate the smallest host/guest command-dispatch contract from automount, interop, networking, GUI, GPU, systemd, disk-management and policy features.

## Exact environment examined

- Installed WSL: `2.7.11.0`
- Installed kernel reported by WSL: `6.18.33.2-2`
- Installed Windows build: `10.0.26200.9168`
- Installed artifacts:
  - `C:\Program Files\WSL\tools\init` — 2,836,528 bytes
  - `C:\Program Files\WSL\tools\initrd.img` — 2,836,768 bytes
  - `C:\Program Files\WSL\tools\kernel` — 17,334,784 bytes
  - `C:\Program Files\WSL\system.vhd` — 374,252,032 bytes
- Matching open-source WSL tag: `2.7.11`
- Matching source commit: `acbcb81fc61079b74835ea7dc2563046b2557033`
- Matching source worktree: `/root/src/WSL-2.7.11`
- A current-master reference checkout also exists at `/root/src/WSL`, commit `1ef0817a0465b9ad7458f155bec0a2c877462e6d`.

The tagged source, not current master, is the primary evidence for this installed WSL version.

## Architecture confirmed from Microsoft documentation

WSL supplies its own initramfs containing `mini_init`. The VM boots the selected stock/custom kernel and then runs that `/init`. Normal `wsl.exe` process launch depends on this chain:

1. `mini_init` establishes Hyper-V socket channels with `wslservice.exe`.
2. It receives a request to mount a distribution VHD.
3. It creates mount, PID, IPC and UTS namespaces, mounts/chroots the distribution and executes the per-distribution WSL `/init`.
4. Distribution init establishes another host channel and creates a session leader.
5. A relay process carries stdin, stdout and stderr between the Linux command and `wsl.exe`.

Therefore Microsoft init is not ordinary distro PID 1 that can simply be replaced while retaining normal `wsl.exe -d ... -- command` behavior. At least the host protocol, VHD mount, namespace, command creation and relay functions need an implementation.

Primary documentation:

- <https://wsl.dev/technical-documentation/boot-process/>
- <https://wsl.dev/technical-documentation/mini_init/>
- <https://wsl.dev/technical-documentation/init/>
- Matching source: `src/linux/init/main.cpp`, `src/shared/inc/lxinitshared.h`

## What `mini_init` does before launching a distribution

The matching 2.7.11 source shows several unconditional operations that can force kernel configuration beyond a generic Toybox boot:

- mount devtmpfs, procfs and sysfs;
- open `/dev/kmsg`, `/dev/console` and `/dev/null`;
- connect two Hyper-V socket channels to `wslservice.exe`;
- mount cgroup v2;
- create a signalfd and poll the service/signalfd channels;
- set dmesg, inotify, file-descriptor and locked-memory policy;
- create an IPv4 datagram socket and enable loopback;
- mount a shared tmpfs at `/mnt/wsl`;
- replace `/etc/resolv.conf` with a cross-distro symlink;
- mount binfmt_misc and register `/init` as the Windows executable interpreter;
- start the guest network service after early configuration.

This confirms the user’s suspicion: some facilities that appeared to be mysterious WSL kernel requirements are requirements of Microsoft’s chosen control plane, not requirements for Linux or Toybox to boot.

## Conditional or audience-wide facilities

The source also supports or starts facilities according to host/config messages:

- system distribution VHD and writable overlays;
- swap;
- chronyd/PTP time synchronization;
- kernel-module VHD and module loading;
- memory reclaim workers;
- GNS networking and DNS tunneling;
- localhost/port tracking;
- mirrored-networking seccomp/BPF interception;
- DHCP and IPv6 policy;
- GPU and WSLg shares;
- debug shell and crash dumps;
- disk format, mount, resize, import and export;
- cross-distribution mounts;
- user-process cgroup resource reservation.

The machine currently requests mirrored networking and DNS tunneling in `.wslconfig`, so it selects more of this surface than a boot-only profile would.

## Existing reduction controls

Per-distribution `/etc/wsl.conf` can disable automount, fstab processing, Windows PATH injection, Windows interop, generated hosts/resolver files, Plan 9, GPU/GUI integration and systemd. WSL safe mode applies many of those reductions.

However, source inspection shows that safe mode is not equivalent to a minimal `mini_init`: core mini-init startup still mounts cgroup2, initializes network-related state, registers binfmt interop and starts GNS in the normal early-config path. Configuration can reduce launched distribution services without removing every kernel dependency of the utility-VM control plane.

## Candidate targets

### A. Minimal profile using Microsoft’s unmodified init

Disable every exposed optional feature and discover the remaining kernel closure. This preserves normal WSL servicing and command dispatch but accepts unconditional Microsoft policy as part of the floor.

### B. Single-user patched WSL control plane

Build from the matching 2.7.11 source and retain only:

- service protocol handshake/capabilities;
- VHD attachment and ext4 mounting;
- required namespaces/chroot;
- process/session creation and stdio relay;
- child exit notification and shutdown.

Candidates for removal or compile-time exclusion include GNS, localhost tracking, binfmt Windows interop, cross-distro tmpfs, GPU/WSLg, system distro, disk-management operations, module VHD, memory reclaim policy, cgroup resource reservation, debug/crash facilities and automatic resolver policy.

This remains the best final fit for an audience of one. The Linux-side init can be built without the full Windows toolchain, but WSL exposes no external initrd selection. Reduced-init runtime testing should therefore use a controlled WSL package in a disposable Hyper-V Windows VM rather than blocking supported host kernel discovery or modifying the host’s installed initrd.

### C. Bypass WSL’s control plane

Boot the mkroot kernel/initramfs directly under QEMU or another Hyper-V VM. This gives the smallest conventional Linux system but loses normal WSL distribution registration, `wsl.exe` process dispatch, Windows integration and WSL lifecycle management.

## Decision recorded

The selected target is **B: a single-user patched WSL control plane preserving normal `wsl.exe` command dispatch**.

This best matches the audience-of-one requirement without redefining the project as a generic QEMU/Hyper-V VM. Stock Microsoft init remains a reference and possible temporary diagnostic profile, not the intended minimum.

The reproducible-build part of the feasibility gate has passed for the Linux-side binary. `tools/build-control-plane-linux.sh` produced identical unmodified `init` and deterministic `initrd.img` artifacts in two clean runs from source commit `acbcb81fc61079b74835ea7dc2563046b2557033`.

The stock-copy recovery gate is complete. `K-RECOVERY-001` validated the kernel-only `.wslconfig` harness using an external byte-identical stock-kernel copy, proved exact `.wslconfig` restoration and stock-distro startup, and left Microsoft’s installed initrd unchanged. The first uninstrumented trials, `K-MKROOT-001` and the reviewed Hyper-V execution-core derivative `K-HVCORE-001`, were conservatively classified `B0`; both restored stock operation. Diagnostic retry `K-HVCORE-DIAG-001` then proved the unchanged derivative reached `B1`, executed stock `/init`, and failed its host connection with VSOCK `EAFNOSUPPORT` before VMBus enumeration. The evidence-directed ACPI/platform plus Hyper-V VSOCK candidate `K-HOSTCHAN-001` is built but requires a new explicit decision before boot.

For the later reduced-control-plane track:

1. map the exact retained host protocol, VHD mount, namespace/chroot, process relay, exit-notification and shutdown code paths;
2. build the reduced variant twice and verify identical outputs;
3. separately install the optional Windows build workload only when the user chooses;
4. deploy a controlled package or service-level initrd override to a disposable Hyper-V Windows VM;
5. fail closed if any protocol, packaging or recovery assumption cannot be verified.

Source inspection shows WSL 2.7.11 assigns `InitRdPath` from its installation tools directory and exposes no `.wslconfig` custom-initrd setting. The approximately 3 GB Visual Studio workload remains a separate optional task in `TASKS.md` and must not be installed automatically.
