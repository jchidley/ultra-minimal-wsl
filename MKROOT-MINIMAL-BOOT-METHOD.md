# Rob Landley’s minimal Linux boot method

This explanation records the method behind Toybox mkroot from its author’s code, documentation and presentations. It is the conceptual starting point for the WSL experiment; `MINIMAL-BOOT-PLAN.md` describes how we apply it to WSL.

## Two different definitions of minimal

Landley’s material addresses two related targets that must not be conflated:

1. **Minimal boot-to-shell system:** Linux, a libc supplied by the toolchain, and Toybox, packaged as an initramfs and booted under QEMU.
2. **Minimal self-hosting development system:** the smallest environment capable of rebuilding itself and then building a full distribution. Aboriginal Linux reached this with seven source packages: Linux, BusyBox, uClibc, GCC, binutils, make and bash.

Our first WSL milestone uses the first target as its generic Linux floor: boot Toybox, then add only the WSL management and command-dispatch contract to create `minimal-viable-wsl-v1`. Alpine, Arch, and Debian compatibility produce `ultra-minimal-wsl-v1`. A complete self-hosting development environment remains a later profile rather than a boot criterion.

## Primary source hierarchy

1. Current implementation: Toybox `mkroot/mkroot.sh` and `mkroot/README` at commit `b7ec52ac35e075caffca5d330995d44e8dbfc8c3`.
2. Line-by-line walkthrough: [mkroot walkthrough, 2023](https://landley.net/talks/mkroot-2023.txt).
3. Iterative derivation: [Building the Simplest Possible Linux System, 2017](https://www.youtube.com/watch?v=Sk9TatW9ino).
4. Current FAQ: [What does Toybox provide?](https://landley.net/toybox/faq.html#system) and [How does mkroot build a system?](https://landley.net/toybox/faq.html#mkroot).
5. Historical rationale: [Aboriginal Linux](https://landley.net/aboriginal/about.html), its [history](https://landley.net/aboriginal/history.html), and the [2009 QEMU presentation](https://speakerdeck.com/landley/developing-for-non-x86-targets-using-qemu).
6. Talk description: [mkroot: tiny Linux system builder, Texas Linux Fest 2024](https://2024.texaslinuxfest.org/talks/mkroot-tiny-linux-system-builder/).

Archived research copies are under `references/landley/`:

- `mkroot-2023.txt`
- `simplest-linux-2017-transcript.txt`
- `aboriginal-about.html`
- `aboriginal-faq.html`

The obsolete standalone `landley/mkroot` repository is not authoritative; mkroot was merged into Toybox.

## The method

### 1. Define one observable success condition

The coherent initial target is “boot to a shell prompt.” Do not begin by constructing a distribution or enabling every anticipated service. The test must expose serial output, launch PID 1 and terminate predictably on failure.

For QEMU, mkroot supplies:

- a known machine model;
- a serial console connected to QEMU stdin/stdout;
- `console=<device>` so kernel output is visible;
- `panic=1` plus QEMU `-no-reboot`, turning a panic into a failed process rather than a hung test;
- a small fixed memory allocation;
- a generated `run-qemu.sh` so the invocation is reproducible.

### 2. Fix the hardware model before configuring the kernel

A minimum kernel is relative to a board or virtual machine. Landley first identifies:

- architecture and kernel `ARCH=` value;
- board/machine model;
- console device;
- storage controller and block device;
- network controller, if networking belongs to the test;
- interrupt, clock and device-tree requirements;
- kernel image and optional DTB paths.

mkroot’s architecture staircase encodes this as `KARCH`, `QEMU`, `KARGS`, `VMLINUX`, `DTB` and architecture-specific `KCONF`. For x86-64 QEMU, the current script includes the PCI, ATA/PIIX, SCSI disk, E1000, RTC and 8250 serial facilities for its selected emulated machine.

This is why a generic minimum cannot simply be copied to WSL: WSL presents Hyper-V devices and a Microsoft control plane instead of mkroot’s QEMU hardware contract.

### 3. Start from `allnoconfig`, not a distribution defconfig

Landley rejects `defconfig` as a minimum because it enables broad policy defaults. mkroot writes a concise symbol list and asks Kconfig to expand it:

```sh
make ARCH="$KARCH" allnoconfig KCONFIG_ALLCONFIG=linux-miniconfig
```

The outputs preserve three levels:

- `linux-microconfig`: compact comma-separated intent;
- `linux-miniconfig`: explicit requested Kconfig settings;
- `linux-fullconfig`: Kconfig’s complete dependency-resolved `.config`.

The distinction between requested and dependency-selected symbols is part of the method. Our SQLite inventory preserves the same distinction and both directions of each relationship.

### 4. Add the generic execution substrate

The current mkroot generic microconfig enables the common facilities needed by its rootfs and tests, including:

- ELF and script execution;
- block/initrd support and gzip decompression;
- ext4, FAT/VFAT and SquashFS for its supported tests and images;
- tmpfs and POSIX ACLs;
- devtmpfs and automatic `/dev` mounting;
- Unix sockets, packet sockets, IPv4 and IPv6;
- loop devices and basic network-device infrastructure;
- embedded kernel-config reporting.

Not all current mkroot common symbols are logically necessary for merely reaching a shell. Some support mkroot’s broader block, clock and network smoke tests. Therefore the exact generated config is our reproducible lower-bound implementation, while later controlled subtraction can distinguish shell-boot requirements from mkroot test-profile requirements.

### 5. Build the smallest useful root filesystem

mkroot creates the directory layout, permissions and minimal account files, then installs a statically linked Toybox multicall binary and command symlinks. A musl cross-toolchain avoids glibc’s static-linking/runtime-loading complications.

Its `/init`:

- mounts `/dev`, `/dev/shm`, `/dev/pts`, `/proc` and `/sys`;
- performs optional package init hooks;
- when running as PID 1, uses Toybox `oneit` to run one child and shut down when it exits;
- when used in a chroot, launches a shell and unmounts virtual filesystems on exit.

Static linking removes the ELF interpreter/shared-library closure from this first rootfs. Alpine later tests musl dynamic userspace; Arch and Debian test glibc userspace separately.

### 6. Package the rootfs as initramfs

mkroot creates a `newc` cpio archive owned by root and compresses it. It can supply that archive externally or compile it into the kernel.

Initramfs avoids a bootloader, partition table and early disk driver for the first generic test. It places `/init` directly in the kernel’s initial root filesystem, making early failures easier to attribute.

### 7. Derive missing facilities from the earliest failure

The 2017 presentation demonstrates the intended progression from `allnoconfig`:

1. Enable board and serial-console facilities.
2. Boot and discover that kernel printing is unavailable; enable the required printing/config policy.
3. Boot and receive “no filesystem could mount root”; enable initrd and decompression support.
4. Boot and fail to execute the ELF binary; enable `BINFMT_ELF`.
5. Execute a binary, then enable `BINFMT_SCRIPT` to run `/init` as a script.
6. Run init, then enable devtmpfs facilities when `/dev` cannot be mounted/populated.
7. Continue according to the earliest stable failure rather than anticipating a complete distribution.

Exact symbols and dependencies evolve across kernel versions, so the current mkroot-generated configs and Kconfig graph supersede historical symbol lists. The invariant is the method: begin empty, make one observable layer work, and retain evidence for every addition.

### 8. Test more than “a prompt appeared”

`mkroot/testroot.sh` automates QEMU boots with timeouts and verifies serial execution, a compiled program, block access, clock and networking. It turns emulator exit status and expected output into regression evidence.

Minimal Viable WSL intentionally narrows that suite to Toybox command execution through normal `wsl.exe` management. The ultra-minimal compatibility stage adds Alpine, Arch, and Debian smoke tests. Later integration profiles should add similarly explicit tests rather than silently broadening “boot works.”

### 9. Keep the build hermetic and recorded

mkroot clears most inherited environment variables, can build an “airlock” PATH from Toybox plus the toolchain, records invoked commands, captures stdout/stderr and marks successful logs distinctly. This supports reproducibility and exposes accidental host dependencies.

Our experiment must preserve source/toolchain versions, all three config forms, command logs and hashes for the same reason.

## Applying the method to WSL

The shortest evidence-preserving sequence is:

1. Generate the untouched x86-64 mkroot image from the pinned Toybox and Microsoft 6.18 source in a dedicated clean worktree.
2. Boot that image under its generated QEMU launcher and run the minimal shell smoke test. This proves the mkroot baseline independently of WSL.
3. Save microconfig, miniconfig, fullconfig, kernel, initramfs, QEMU command, logs and hashes.
4. Add the fullconfig to the dependency inventory as `mkroot` and classify its symbols `BASE`.
5. Try the same kernel config through WSL without pre-adding speculative WSL features.
6. Classify the earliest WSL checkpoint reached.
7. Replace QEMU hardware assumptions with the smallest coherent Hyper-V/WSL bundle indicated by that failure.
8. Preserve requested versus Kconfig-selected symbols and retest.
9. Once WSL dispatches commands, run the Toybox smoke test and prove the retained WSL additions necessary by controlled removal; freeze `minimal-viable-wsl-v1`.
10. Test Alpine, Arch, and Debian in order, classify only their proved compatibility additions, and freeze `ultra-minimal-wsl-v1`.
11. Defer networking and Windows-integration services to later additive profiles.

This is Landley’s process extended by one extra platform layer: generic Linux boot is established first, then the undocumented Microsoft WSL startup contract is discovered without losing the known-good minimal baseline.
