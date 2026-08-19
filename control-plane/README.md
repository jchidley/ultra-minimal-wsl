# Reduced control-plane development

This directory contains the first source-level candidate for the host and guest path described in `WSL-CONTROL-PLANE-AUDIT.md`. It is a buildable prototype, not runtime proof of Minimal Viable WSL.

## Pinned protocol fixture

`protocol/wsl-2.7.12.json` records message identifiers, constants, sizes, and offsets compiled from WSL 2.7.12's shared host/guest header. Verify it on `LFS-Builder`:

```bash
SOURCE=/root/src/WSL-2.7.12 \
  /mnt/c/Users/jackc/git/ultra-minimal-wsl/tools/extract-control-plane-protocol.sh check
```

The fixture retains handshake, instance creation, initialization, command creation, exit status, and termination ABI. A value appearing in the fixture does not by itself prove runtime necessity.

## Candidate `minimal-v1`

`patches/0001-minimal-control-plane-v1.patch` applies to commit `68f601bba8eac1df20a0bbd403c6c87c92369ade`. It makes the first coarse reduction:

- host: supplies no system distro, swap, kernel-modules disk, GNS, DNS, networking engine, WSLg, DrvFs, interop, or OOBE policy;
- mini init: rejects excluded early/initial configuration and non-launch instance operations;
- distro host path: sends a zero-feature direct-command configuration and clears DrvFs, elevation, interop, and OOBE process flags;
- retained: primary and notification VSOCK channels, one registered distro VHDX/ext4 launch, distro-init channel, command sockets, stdio, exit status, and termination code.

The Linux side compiles reproducibly. `candidates/minimal-v1/` records the complete source-diff hash, build inputs, output hashes, and two-clean-build comparison. The Windows service side still requires a controlled Windows build and runtime test in the disposable VM.

To build a clean applied worktree offline, calculate the source diff hash after applying the patch and pass it explicitly:

```bash
base=68f601bba8eac1df20a0bbd403c6c87c92369ade
patch_sha=$(git diff --binary "$base" | sha256sum | cut -d' ' -f1)
SOURCE=$PWD BUILD=/root/experiments/minimal-wsl/control-plane-build/minimal-v1 \
OFFLINE=1 EXPECTED_SOURCE_PATCH_SHA256="$patch_sha" \
  /mnt/c/Users/jackc/git/ultra-minimal-wsl/tools/build-control-plane-linux.sh
```

## Disposable Hyper-V VM

`tools/New-DisposableWslDevVm.ps1` creates a Generation 2 VM from a Windows ISO or generalized Windows VHDX. It enables Secure Boot, vTPM, dynamic memory, and nested virtualization; disables automatic checkpoints; creates `clean-shell`; and deliberately leaves the VM off. It refuses execution without both elevation and `-Execute`.

Plan without changing Hyper-V:

```powershell
.\tools\New-DisposableWslDevVm.ps1 -WindowsMedia C:\path\to\pinned-windows.iso
```

After separate explicit approval, launch the reviewed fixed invocation through `windows-env/ps-elevate`. For ISO media, install Windows and establish the stock WSL/package-build baseline before replacing any package. When the VM is off, plan and then explicitly execute:

```powershell
.\tools\Checkpoint-DisposableWslDevVm.ps1
.\tools\Checkpoint-DisposableWslDevVm.ps1 -Execute
```

This creates `controlled-package-baseline`. Neither script starts or stops a VM automatically. Machine state is recorded outside Git under `%LOCALAPPDATA%\ultra-minimal-wsl\hyper-v-vm.json`.

## Remaining gates

1. Record and hash approved Windows installation media.
2. Obtain explicit approval for elevated VM creation.
3. Install Windows in the VM and establish a stock WSL 2.7.12 recovery baseline.
4. Build the patched Windows service/package inside the VM.
5. Create `controlled-package-baseline` while the VM is off.
6. Define a runtime trial record before booting the controlled package.
7. Prove B4, B5, B6-T, termination, and checkpoint recovery before further reduction.
