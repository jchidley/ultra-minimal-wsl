# Ultra-minimal WSL 2 experiments

Prepared 2026-08-17. The normal Microsoft kernel remains active; no custom kernel is currently configured in `C:\Users\jackc\.wslconfig`.

The current objective is the smallest reproducible WSL kernel config that boots
the mkroot Toybox system and then Alpine. Networking, DrvFs, systemd,
containers, GUI integration, and unrelated Microsoft control-plane policy are
deferred.

## Source checkouts (WSL ext4)

Inside the dedicated `LFS-Builder` distro:

- `/root/src/toybox`
  - Upstream: <https://github.com/landley/toybox>
  - Commit: `b7ec52ac35e075caffca5d330995d44e8dbfc8c3`
- `/root/src/WSL2-Linux-Kernel`
  - Upstream: <https://github.com/microsoft/WSL2-Linux-Kernel>
  - Branch: `linux-msft-wsl-6.18.y`
  - Commit: `14794180686c2fb6307fbe359c359bec765249f3`
  - Describes as `linux-msft-wsl-6.18.40.1`

The kernel checkout is about 2 GB. Required kernel build packages are installed in `LFS-Builder`.

## Toybox minimal user space

Toybox is the AOSP-oriented BusyBox alternative. Its `mkroot` directory and `www/faq.html` contain the minimal-Linux discussion and executable builder.

A 73 MB x86-64 musl cross-toolchain was downloaded and used so the root does not have glibc static-linking limitations:

`/root/src/toybox/downloads/x86_64-linux-musl-cross.tar.xz`

The generated root is:

`/root/src/toybox/root/x86_64/fs`

Measured result:

- Root filesystem: about **832 KB** before WSL/VHD overhead
- Static Toybox multicall binary: about **748 KB**
- Toybox commands: **242**
- Filesystem entries: 268
- Chroot smoke test: passed
- WSL import and command execution: passed

Registered distro:

```powershell
wsl.exe --cd / -d Toybox-Minimal -u root -- /bin/toybox sh
```

Windows-drive automount and Windows PATH interop are deliberately disabled in this tiny distro because Toybox's minimal `mount` is not a drop-in implementation for WSL's DrvFs invocation. `toybox-minimal-wsl-rootfs.tar.gz` is the configured export; `toybox-minimal-rootfs.tar.gz` is the pristine mkroot output.

## What a minimal Linux user space actually needs

For this experiment the practical floor is:

1. A valid executable `/init` or a WSL-provided init path.
2. An ELF loader/libc, unless the programs are statically linked as Toybox is here.
3. A shell or another executable WSL can launch.
4. `/dev` backed by devtmpfs, especially `/dev/null` and a console/PTY path.
5. `/proc` and `/sys` for normal process and device discovery.
6. `/tmp` with mode 1777.
7. Minimal `/etc/passwd` and `/etc/group` if names are needed.
8. Kernel support for ELF, procfs, sysfs, tmpfs/devtmpfs, PTYs and the syscalls used by init/user space.

Networking, package management, systemd, shared libraries, login programs, documentation, locales, a compiler and most `/etc` policy are optional depending on the target.

## Stock WSL kernel audit

Microsoft's 6.18 config contains roughly:

- 1,802 built-in selections
- 760 module selections

It includes far more than a minimal WSL boot requires: Btrfs, XFS, F2FS, Ceph, NFS, CIFS, ISO/UDF/FAT/exFAT, KVM, Bluetooth, sound, media, CAN and many USB drivers. Btrfs is configured as a module and is loaded by the normal WSL system even when no Btrfs filesystem is mounted.

The first minimal-boot milestone is expected to need a dependency closure around:

- x86-64 and ELF execution
- Hyper-V/VMBus, timers and hypervisor integration
- Hyper-V storage (`storvsc`) and SCSI disk support
- ext4 built in, because distro VHDX roots are ext4
- Hyper-V sockets or other host-control facilities used by WSL
- devtmpfs, procfs, sysfs, tmpfs, Unix sockets and PTYs
- the exact syscall/features expected by Microsoft's `/init`

These are hypotheses until demonstrated by the mkroot-to-Stage-1 experiments. Hyper-V networking, 9P/virtiofs Windows integration, systemd/cgroups, containers and other services are deferred profiles rather than first-milestone assumptions. The distinction matters: a kernel can mount the WSL system disk successfully but still panic if Microsoft's `/init` encounters a missing facility.

## Built kernels and test results

| Image | Approx size | Result |
|---|---:|---|
| `vmlinux-wsl-baseline` | 15 MB | Build baseline from Microsoft config |
| `vmlinux-wsl-ultramin-stage1` | 14 MB | **Boot passed**; Alpine, ext4 root, DrvFs and networking passed |
| `vmlinux-wsl-ultramin-stage2` | 14 MB | Failed during WSL VM startup |
| `vmlinux-wsl-ultramin-stage3` | 6.7 MB | Mounted root and started `/init`, then `mini_init` segfaulted and the kernel panicked |

Stage 1 disables Btrfs and other clearly irrelevant filesystem/hardware families while retaining the broad WSL execution substrate. It is the current known-good custom kernel.

Stage 3 proves the kernel can be reduced substantially, but its panic trace shows that one or more features removed between stages 1 and 3 are required by Microsoft's proprietary WSL init. The trace is at:

`C:\Users\jackc\AppData\Local\Temp\wsl-crashes\kernel-panic-1786991541-{a98460e3-e479-4b0f-bb4a-d4da75dc1925}.txt`

Stage 1 remains the known-good upper bound. Stage 3 remains useful failure evidence, but the revised experiment starts from Toybox mkroot's generated minimum and adds dependency-aware WSL feature groups. If error-directed additions stall, Stage 1 supplies the upper bound for group-level delta debugging.

## Kernel choices and security implications

- **Microsoft stock:** broadest compatibility, normal Microsoft servicing and lowest maintenance risk, but the largest enabled feature set.
- **Locally rebuilt baseline:** proves reproducibility but retains nearly the stock feature set and transfers update responsibility to us.
- **Stage 1:** working conservative reduction and current recovery/reference custom kernel.
- **Stages 2 and 3:** failure boundaries for research, not deployable kernels.
- **mkroot-derived candidate:** the new lower bound; generic Linux boot capability does not imply WSL control-plane compatibility.
- **Generic upstream/LFS kernel:** possible, but using it directly would require reproducing the Microsoft WSL patches and integration contract.

Removing unused drivers, filesystem parsers and protocols can reduce attack surface, but image size is not a security metric by itself. A smaller configuration can be worse if it removes mitigations, integrity controls, isolation or diagnostics. A custom kernel also stops receiving Microsoft kernel fixes automatically, so any deployable result needs source tracking, repeatable rebuilds, regression tests and a stock-kernel fallback.

## Safely activating the known-good stage 1 image

A `.wslconfig` kernel setting is global to all WSL 2 distros. Preserve the stock fallback and shut WSL down before switching.

Add under `[wsl2]`:

```ini
kernel=C:/Users/jackc/git/ultra-minimal-wsl/vmlinux-wsl-ultramin-stage1
```

Then:

```powershell
wsl.exe --shutdown
wsl.exe -d Alpine -- uname -r
```

Expected kernel string:

`6.18.40.1-wsl-ultramin-stage1+`

To revert, remove the `kernel=` line and run `wsl.exe --shutdown`. Forward slashes avoid `.wslconfig` backslash-escaping mistakes.

## Rebuilding

```powershell
wsl.exe -d LFS-Builder
```

```bash
cd /root/src/WSL2-Linux-Kernel
cp /root/kernel-builds/config-wsl-ultramin-stage1 .config
make olddefconfig
make -j"$(nproc)" bzImage
```

Output: `arch/x86/boot/bzImage`.

The Toybox rootfs already produced in this project was built without `LINUX=`, so no mkroot kernel was generated. Reproduce that userspace-only build with:

```bash
cd /root/src/toybox
mkroot/mkroot.sh CROSS=x86_64
sudo chroot root/x86_64/fs /init
```

The kernel-enabled mkroot baseline has now been built in protected worktrees and passed checkpoint G4 under QEMU. Its 3.44 MB kernel, 514 KB initramfs, three config forms, logs and verified hashes are in `mkroot-baseline/`. See `STATUS.md` for exact revisions, toolchain and results. It was later tested through WSL as `K-MKROOT-001`; it produced no observable output or command dispatch (`B0`) and stock recovery passed.

## Minimal-boot experiment plan and dependency inventory

Rob Landley’s documented minimal-boot derivation is summarized with primary sources in `MKROOT-MINIMAL-BOOT-METHOD.md`. The WSL adaptation plan is in `MINIMAL-BOOT-PLAN.md`, current active/optional work is in `TASKS.md`, supported kernel switching and Microsoft’s development workflow are explained in `WSL-DEVELOPMENT-AND-RECOVERY.md`, the ETL/debug-console workflow is documented in `PRE-DISPATCH-DIAGNOSTICS.md`, the corrected B2-to-B3 diagnosis is in `POST-B2-CLOSURE-ANALYSIS.md`, kernel configuration provenance is recorded in `KERNEL-CONFIG-PROVENANCE.md`, and the control-plane audit is in `WSL-CONTROL-PLANE-AUDIT.md`.

The searchable Kconfig dependency graph and review checklist are under `inventory/`; begin with `inventory/README.md`. It contains SQLite and CSV representations of 18,449 symbols, 126,629 conditional relationships and five config snapshots including mkroot. `inventory/mkroot-stage1-delta.csv` contains the 1,792-symbol lower-to-upper-bound review queue.

`STATUS.md` is the current-state checkpoint. The matching unmodified WSL 2.7.11 Linux `init` and deterministic initrd now build reproducibly; artifacts are under `control-plane-build/native-build/`. The supported external-kernel harness is `tools/Invoke-WslKernelTrial.ps1`, with non-disruptive checks in `tools/Test-WslKernelTrial.ps1` and state notes in `recovery-harness/README.md`. Its execute-mode stock-copy validation `K-RECOVERY-001` passed, including exact configuration restoration and stock Debian startup. The approximately 3 GB full Windows WSL build workload was cancelled and is listed in `TASKS.md` as an optional, separately invoked task.

## Repository and artifact integrity

Git tracks the experiment's scripts, configurations, metadata, hashes, review inventory, extracted diagnostics, and written conclusions. Reproducible or downloaded binaries, the generated SQLite database, and bulky raw ETL/XML captures remain local and are listed in `.gitignore`; their `SHA256SUMS`, build metadata, extracted logs, and analyses remain tracked where available. This keeps the repository reviewable without treating GitHub as binary artifact storage.

The root `SHA256SUMS` covers the original configs, kernels, rootfs archives and musl toolchain in this directory. Newer candidate and trial directories carry their own manifests. A hash manifest records integrity but does not make an omitted artifact recoverable: rebuild it from the pinned source/toolchain metadata or preserve it separately before deleting the local copy.

No repository-wide licence is asserted yet. The tree contains original orchestration alongside generated output and material derived from Microsoft WSL, the Linux kernel, and Toybox; licensing should be documented per component before making the repository public.
