# Rust minimal WSL follow-on

This is a provisional charter for a separate follow-on project. It is not part of the current minimisation run, does not change either frozen-target contract, and authorizes no build, deployment, shutdown, or boot.

## Purpose

Build a minimal but conventional Linux system that remains controllable through ordinary `wsl.exe` operations. It should use a persistent registered ext4 root filesystem, run native Linux executables with normal process and file semantics, relay standard streams and exit status, and terminate cleanly.

The objective is a useful minimal Linux userspace, not a container appliance or merely a bootable toolbox.

## Start gate

Do not start this project until `minimal-viable-wsl-v1` has been frozen with reproducible B6-T, lifecycle, and recovery evidence. Develop it in a separate repository or otherwise isolated records so it cannot alter the Toybox lower bound, control-plane candidate hashes, trial ledger, or the later `ultra-minimal-wsl-v1` compatibility result.

The frozen minimal control plane remains an experimental baseline. Any controlled-package use continues to require the existing disposable-VM and recovery safeguards.

## Proposed system boundary

```text
wsl.exe
    -> proven minimal Windows/guest WSL control plane
        -> registered ext4 distro root
            -> Brush as /bin/sh
            -> selected uutils multicall commands
            -> minimal /etc and persistent home
```

The first version should retain the proven reduced Linux-side WSL init. Reimplementing that init in Rust is a later, independently tested phase, not a prerequisite for the userspace.

“Rust” describes the selected userspace implementation language. It does not imply that the Linux kernel, Windows WSL service, musl, or every build-time dependency is written in Rust.

## Candidate components

These are investigation candidates, not pinned dependencies or accepted claims:

- [Brush](https://github.com/reubeno/brush) for a POSIX/Bash-compatible `/bin/sh`, built without optional interactive features that the acceptance contract does not need;
- [uutils coreutils](https://github.com/uutils/coreutils) as a selectively enabled multicall command set;
- [Armybox](https://github.com/quinnjr/armybox) as a size-oriented comparison requiring independent compatibility, implementation, and provenance review;
- [NVRC](https://github.com/NVIDIA/nvrc) only as a reference for reproducible static builds, early mounts, diagnostics, and fail-closed PID-1 behavior. Kata, GPU setup, networking, modules, and container orchestration are not part of this project.

Prefer measured behavior, dependency closure, reproducibility, and test quality over upstream size or compatibility claims.

## Initial scope

Retain:

- ordinary `wsl.exe` selection, direct execution, shell execution, and termination;
- persistent files on one registered ext4 VHDX;
- `/dev`, `/proc`, `/sys`, `/run`, `/tmp`, `/etc`, and a writable home;
- environment, working-directory, signal, process, standard-stream, and signed exit-status behavior needed by normal command-line use;
- a static or otherwise self-contained shell and selected basic utilities;
- pinned, hash-verified, offline-capable, reproducible builds.

Initially exclude the same integrations as Minimal Viable WSL: networking/DNS, DrvFs, Windows executable interop, WSLg/GPU, systemd, containers, cgroup policy, USB, general disk management, and cross-distro integration. Any later convenience feature belongs in a separate additive profile.

## Milestones

### `R0` — reproducible userspace artifact

Pin the Rust toolchain, source revisions, crate graph, target and linker inputs. Build the selected root filesystem twice offline in clean ext4 directories and require byte-identical outputs.

### `R1` — stock-WSL userspace proof

Register the root filesystem through an approved, reversible workflow and prove direct command execution, shell execution, persistence, standard streams, exit status, termination, and restart under the stock WSL package.

### `R2` — minimal-control-plane proof

Run the unchanged `R1` userspace on frozen `minimal-viable-wsl-v1`. Attribute any difference to the userspace or control plane rather than changing both simultaneously.

### `R3` — practical minimal Linux baseline

Freeze the smallest selected Brush/uutils feature closure that passes the acceptance contract repeatedly with clean logs and recovery. Compare, but do not substitute, a narrowly built Armybox candidate if it passes the same gates.

### `R4` — optional Rust WSL init

Only after `R3`, consider a static Rust replacement for the Linux-side reduced WSL init. It must preserve the pinned protocol ABI, fail-closed message policy, VSOCK channels, ext4 launch, root transition, process/PTY relay, signed exit status, termination, and recovery. Keep the proven C++ init as the behavioral oracle and recovery path.

## Acceptance contract

A candidate is not accepted merely because it reaches a prompt. Through ordinary `wsl.exe`, it must reproducibly prove:

1. direct execution of a native Linux ELF;
2. `/bin/sh -c` sequencing, pipelines, redirection, and non-zero status propagation;
3. readable `/proc/self/status`, mounted `/sys`, and working `/dev/null`;
4. separate stdin, stdout, and stderr relay, including binary data;
5. environment and working-directory propagation;
6. file persistence across distro termination and restart;
7. foreground signal delivery and child cleanup without zombies;
8. signed exit-status fidelity;
9. clean and forced termination followed by successful restart;
10. reproducible source, dependency, rootfs, and recovery hashes.

The follow-on project must define guarded trial records and recovery procedures before any runtime work. Completion of this charter itself proves none of these behaviors.
