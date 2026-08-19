# Why mkroot is the lower bound

Toybox `mkroot` provides the project’s principled generic-Linux starting point. `MINIMAL-BOOT-PLAN.md` adds the WSL-specific contract.

## Two meanings of minimal

Rob Landley’s work distinguishes:

1. a minimal boot-to-shell system: Linux, libc, and Toybox in an initramfs;
2. a self-hosting development system capable of rebuilding itself and a larger distribution.

This project begins with the first. Full self-hosting is not a Minimal Viable WSL acceptance criterion.

## Method

### Start from `allnoconfig`

mkroot records a small requested config and lets Kconfig expand dependencies:

```sh
make ARCH="$KARCH" allnoconfig KCONFIG_ALLCONFIG=linux-miniconfig
```

Preserve all three representations:

- microconfig — concise intent;
- miniconfig — explicit requests;
- fullconfig — dependency-expanded result.

### Fix the machine model

A minimum is relative to hardware. mkroot first fixes the architecture, QEMU machine, console, storage, interrupts, clocks, kernel image, and boot arguments. WSL presents a different Hyper-V machine and control plane, so QEMU hardware assumptions must be replaced rather than accumulated.

### Use a static Toybox root

mkroot creates the basic directory layout and installs a statically linked Toybox multicall binary. Its `/init` mounts `/dev`, `/proc`, `/sys`, and related pseudo-filesystems before launching a shell. Static linking removes the dynamic-loader closure from the generic baseline.

### Package it as initramfs

An initramfs avoids a bootloader, partition table, and early root-disk dependency. It makes kernel entry, archive unpacking, `/init`, and shell execution separately observable.

### Follow the earliest failure

The method is iterative:

1. boot the smallest generated system;
2. identify the earliest stable failure;
3. add one coherent dependency closure;
4. preserve requested versus selected symbols;
5. repeat;
6. prove retained additions necessary by subtraction.

Do not begin with a distribution defconfig or enable anticipated services.

## Application to WSL

1. Prove the untouched mkroot image under its generated QEMU launcher (`G4`).
2. Test the same config through WSL.
3. Replace QEMU assumptions with only the Hyper-V entry, VSOCK, storage, root-transition, and command-relay facilities selected by evidence.
4. Freeze Toybox command dispatch as `minimal-viable-wsl-v1`.
5. Test Alpine, Arch, and Debian separately and classify their additions.

Primary sources:

- Toybox mkroot source and README: <https://github.com/landley/toybox/tree/master/mkroot>
- mkroot walkthrough: <https://landley.net/talks/mkroot-2023.txt>
- Toybox FAQ: <https://landley.net/toybox/faq.html#mkroot>
- Aboriginal Linux rationale: <https://landley.net/aboriginal/about.html>
