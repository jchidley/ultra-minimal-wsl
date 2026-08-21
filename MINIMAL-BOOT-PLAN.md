# Minimal Viable WSL plan

## Target contract

`minimal-viable-wsl-v1` is the mkroot/Toybox generic Linux floor plus only:

1. Hyper-V facilities required to start under WSL 2;
2. VSOCK communication with `wslservice.exe`;
3. attachment and mounting of a registered distro VHDX;
4. the minimum root transition or isolation needed to enter the distro;
5. process creation through `wsl.exe`;
6. stdin, stdout, stderr, and exit-status relay;
7. reliable startup, termination, shutdown, and stock-kernel recovery.

Basic control means selecting and starting a registered distro, executing a command, terminating it, and shutting WSL down. Install, import/export, resize, arbitrary-disk mounting, and other general management operations are not acceptance criteria.

The target excludes networking/DNS, DrvFs, Windows executable interop, WSLg/GPU, systemd, containers, cgroup policy, USB, general disk management, and cross-distro integration. Microsoft’s system distro and writable overlay are stock-init discovery requirements, not final requirements unless reduced-init testing proves them indispensable.

## Compatibility boundary

Freeze Minimal Viable WSL before testing additional userspace:

1. Alpine — musl/BusyBox;
2. Arch — glibc/rolling userspace;
3. Debian — glibc/stable userspace.

A facility selected only by one of these tests is a distro-compatibility requirement, not a generic WSL requirement. Freeze the combined result as `ultra-minimal-wsl-v1`.

## Experimental lower and upper bounds

- Lower bound: the pinned Toybox `mkroot` x86-64 config, proven under QEMU.
- Upper bound: `config-wsl-ultramin-stage1`, already proven to boot WSL.
- Kernel source: pinned Microsoft WSL kernel revision recorded with each candidate.
- Recovery kernel: Microsoft’s untouched packaged kernel.

Changing WSL, Windows, kernel source, toolchain, or a test rootfs starts a new minimisation run.

## Configuration rules

1. Generate the lower bound with mkroot; do not approximate it manually.
2. Expand every candidate with `make olddefconfig` against the pinned kernel tree.
3. Preserve requested fragments separately from generated full configs.
4. Keep discovery additive until command dispatch works or the earliest stable blocker is an excluded stock service; at that boundary, pivot to control-plane reduction.
5. Change one evidence-selected feature group at a time.
6. Query outgoing and incoming Kconfig relationships before changing a symbol.
7. Treat selected dependencies separately from explicit requests.
8. Prove necessity later by controlled removal, repeated failure, and restored success.
9. Do not add excluded integration features merely because stock `mini_init` attempts to use them.

## Requirement classifications

| Status | Meaning |
|---|---|
| `BASE` | Supplied by the mkroot lower bound |
| `PROVEN_WSL_REQUIRED` | Required by the retained WSL control contract |
| `PROVEN_TOYBOX_REQUIRED` | Required for Toybox command execution |
| `PROVEN_ALPINE_REQUIRED` | Required only after Alpine testing |
| `PROVEN_ARCH_REQUIRED` | Required only after Arch testing |
| `PROVEN_DEBIAN_REQUIRED` | Required only after Debian testing |
| `TRANSITIVE` | Selected by Kconfig rather than requested directly |
| `DOCUMENTED_PLATFORM` | Documented Hyper-V/WSL purpose, not yet experimentally required |
| `DOCUMENTED_SCENARIO` | Supports an out-of-scope workload |
| `DEFERRED` | Outside the selected target |
| `UNRESOLVED` | Present in a successful bundle but not isolated |
| `INCOMPATIBLE` | Demonstrated regression in the tested configuration |

A symbol is not “required” merely because Microsoft enables it or because it appears in a successful bundle.

## Checkpoints

### Generic mkroot

| Level | Evidence |
|---|---|
| `G0` | Image rejected or no useful output |
| `G1` | Kernel enters and initializes the selected QEMU machine |
| `G2` | Initramfs unpacked and `/init` found |
| `G3` | Toybox `/init` runs as PID 1 |
| `G4` | Toybox shell smoke test passes |

### WSL

| Level | Evidence |
|---|---|
| `B0` | Image rejected or guest entry unobserved |
| `B1` | Kernel initializes CPU/memory and executes WSL `/init` |
| `B2` | Hyper-V/VMBus and host channel enumerate |
| `B3` | Required Hyper-V storage is detected and ext4 mounted |
| `B4` | Control plane remains alive |
| `B5` | `wsl.exe` dispatches a command into a distro |
| `B6-T` | Toybox smoke test passes |
| `B6-A` | Alpine smoke test passes |
| `B6-ARCH` | Arch smoke test passes |
| `B6-D` | Debian smoke test passes |

Extend the durable trial schema before using the Arch or Debian result fields.

## Smoke-test contract

Each distro must execute through `wsl.exe` and verify only:

```sh
test -r /proc/self/status &&
test -d /sys &&
test -c /dev/null &&
printf '<distro>-ok'
```

Alpine additionally runs `/bin/busybox true`; Arch and Debian run `/bin/true`. Do not test DNS, package management, `/mnt/c`, Windows executables, systemd, or containers.

## Discovery sequence

1. **Generic proof:** preserve the mkroot config/artifacts and require `G4` under QEMU.
2. **Hyper-V entry:** add only the platform execution closure selected by the earliest WSL failure.
3. **Host channel:** establish VMBus and VSOCK communication with `wslservice.exe`.
4. **Distro storage:** attach and mount the registered distro VHDX.
5. **Stock stopping gate:** if an excluded stock service is the earliest stable blocker, preserve that boundary and stop adding kernel support for stock policy.
6. **Reduce control plane:** remove stock-only host and guest policy, including the Microsoft system distro/overlay and GNS path.
7. **Command dispatch:** establish the minimum root transition, process creation, relay, and lifecycle path through the reduced control plane.
8. **Prove minimality:** ablate every provisional WSL bundle and freeze `minimal-viable-wsl-v1`.
9. **Compatibility:** test Alpine, Arch, and Debian in order; attribute and ablate each addition; freeze `ultra-minimal-wsl-v1`.

If a failure does not select a narrow subsystem, delta-debug coherent feature groups between the candidate and Stage 1. Never bisect arbitrary individual symbols across dependency boundaries.

## Deferred controlled-package environment

The Windows controlled-package phase is deferred until large environment inputs are practical. Until separately selected:

- do not download Windows installation media or Visual Studio;
- do not create or start the Hyper-V development VM;
- do not request elevation;
- do not install a controlled package or modify host WSL files;
- continue only static protocol, source-reduction, reproducible Linux-build, Kconfig, and recovery-plan work.

`control-plane/deferred-runtime-plan.json` is preparation, not an executable trial record. It carries no approval forward. Before later execution, replace every missing input with a pinned hash, plan-validate the fixed operation, and obtain fresh explicit approval.

## Evidence and safety gates

Every candidate and trial follows `AGENTS.md`, `inventory/README.md`, and `WSL-DEVELOPMENT-AND-RECOVERY.md`. In particular:

- synchronize durable records and require SQLite integrity `ok`;
- plan-validate before execution;
- obtain fresh explicit approval for any shutdown or boot;
- use one serial trial because all WSL 2 distros share the kernel;
- restore the exact original `.wslconfig` in all outcomes;
- verify packaged hashes and boot a stock recovery distro;
- preserve terminal ledger rows and trial evidence.

## Completion

### `minimal-viable-wsl-v1`

- QEMU `G4` and WSL `B6-T` pass reproducibly.
- The retained control plane implements only the target contract.
- Every non-mkroot feature is classified.
- Ten cold starts pass without unexpected warnings, oopses, or init crashes.
- Source, config, image, and recovery hashes are reproducible.
- Stock-kernel restoration is proven.

### `ultra-minimal-wsl-v1`

- The frozen core still passes Toybox.
- Alpine, Arch, and Debian smoke tests pass.
- Each compatibility addition is attributed and proven necessary.
- The same reproducibility, cold-start, clean-log, and recovery gates pass.

Optional integration work must use separate additive profiles so these two measured baselines remain intact.
