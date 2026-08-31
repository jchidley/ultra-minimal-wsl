# Minimal Viable WSL plan

This is the canonical contract and experiment-rule reference. For a conceptual explanation of the control plane, gates, evidence types, and end-to-end path, read `PROJECT-MODEL.md`.

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

## Candidate comparison and instrumentation

The experiment target is the WSL Linux configuration, not its outer fixture. Fixture start, command transport, package placement, evidence extraction, and rollback are prerequisites only. Failure before the first probe `wsl.exe` process is infrastructure failure and creates no candidate result. Do not vary the probe or develop generalized fixture tooling in response.

Every candidate uses `tools/Invoke-WslCandidateProbe.ps1` with identical inputs and rules. It runs separate bounded `wsl.exe --version`, `--status`, `--list --quiet`, and exact Toybox smoke processes, then shuts WSL down. The interval captures exact package/candidate/rootfs/probe hashes; arguments, timestamps, stdout, stderr, exit, and timeout for every process; WSL WPR/ETW, relevant event delta, debug-console evidence where applicable, and new crash artifacts; an evidence manifest; and independent stock recovery proof.

Missing hashes, interval bounds, process results, trace evidence, manifest, or recovery prevents a positive classification. Reuse `inventory/trials.csv`, `inventory/trial-metadata.csv`, and `recovery-harness/trials/<TRIAL_ID>/`; append one immutable terminal row only after evidence and recovery complete. Infrastructure attempts get no separate experiment ledger.

Accepted controlled comparisons establish the current retained boundary: mount plus PID namespace semantics passes `B6-T`, while IPC and UTS remain omitted. PID-enabled storage-floor and overlay-floor reduced kernels both stop at `B2` after mini-init configuration and before registered-distro mount, so overlay is rejected as the missing facility. Follow source ordering into retained guest initialization and remove excluded-policy hard-fails before selecting another kernel group. Exact trial chronology and identities belong in `STATUS.md` and immutable evidence, not in this contract.

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
7. **Fail-closed static gate:** permit only handshake, one registered LUN/ext4 launch, minimal initialization, direct process relay, exit status, and termination; reject every other mini-init and distro-init operation in both implementation and tests.
8. **Namespace variants:** derive coherent IPC/mount/PID/UTS and mount-only launch variants from one fail-closed parent; preserve both and do not select namespace Kconfig from source preference alone.
9. **Command dispatch:** in the isolated controlled-package environment, establish the minimum root transition, process creation, relay, and lifecycle path through the reduced control plane.
10. **Prove minimality:** ablate every provisional WSL bundle and freeze `minimal-viable-wsl-v1`.
11. **Compatibility:** test Alpine, Arch, and Debian in order; attribute and ablate each addition; freeze `ultra-minimal-wsl-v1`.

If a failure does not select a narrow subsystem, delta-debug coherent feature groups between the candidate and Stage 1. Never bisect arbitrary individual symbols across dependency boundaries.

## Source-only readiness strategy

Reduced host/guest candidates must be source-ready before attempting `B4`, `B5`, and `B6-T` in the isolated controlled-package environment. Static Kconfig review supports a concrete retained-path question; it is not a substitute for runtime proof or an unbounded serial prerequisite.

Before runtime, eliminate reachable hard-fail paths for excluded policy rather than adding their kernel facilities. This includes convenience sysctls and setup for excluded development tooling: do not enable `CONFIG_INOTIFY_USER` solely to satisfy mini-init's Visual Studio Code Remote `max_user_watches` write. Any source change creates a new layered candidate: preserve its parents, keep policy/protocol/mutation gates passing, and require two distinct offline builds of every affected candidate with durable source, profile, artifact, and reproducibility hashes.

For a selected Kconfig review, query both relationship directions, inspect retained source reachability, and distinguish baseline support from Stage-1 additions. Record classifications only through `tools/inventory.py set` and require synchronized inventory integrity. Static review may classify excluded or baseline facilities, but it must not promote runtime requirements or select a namespace sibling. `TASKS.md` alone owns the current bounded work; detailed findings belong in `control-plane/kernel-contract-review.md`.

## Controlled-package environment

The command path under test spans the Windows service and Linux init components, so Linux-only artifacts cannot establish `B4`, `B5`, or `B6-T`. The pinned Windows compiler layout is experimental infrastructure used to produce a reproducible controlled package; it is not a target-system requirement and its acquisition proves no runtime gate.

Preparation must keep Windows media, compiler/SDK inputs, the PowerShell runtime required by the build procedure, pinned source, dependencies, stock package, candidate outputs, rootfs, and instrumentation in a reusable hash-verified cache with fail-closed offline reuse. Every fixture-side executable prerequisite must be pinned and checked before execution; host availability is not fixture availability. Preparation does not itself prove installation or execution. A controlled package build produces a closed output manifest and package hash; as soon as those identities exist, the agent must plan-validate the candidate operation and continue directly into disposable-fixture runtime testing.

`control-plane/deferred-runtime-plan.json` records these inputs, the reproducible build procedure, candidate identities, and the fixed trial contract. It is not an executable trial record. Preserve every candidate generation rather than rewriting it; any ABI or source change creates a new candidate and repeats the source-policy, mutation, and two-build reproducibility gates. Before runtime execution, require complete hashes and agent-validate the exact candidate operation and recovery path. Operations wholly confined to the dedicated disposable fixture are standing-authorized within that pinned, offline, hash-verified, recoverable envelope and require no human review, approval, confirmation, or gate-opening. Physical-host or shared-WSL effects still require fresh explicit approval.

Use a continuous evidence loop: build, validate, runtime-test, recover, analyze, then make the next evidence-selected change and repeat. Compiler acquisition enables reproducible compilation; compilation flows directly into guarded runtime comparison; runtime establishes viability; namespace comparison and kernel ablation establish minimality. Do not treat completion of an earlier stage as evidence for a later one, but do not pause between stages for operator review.

## Evidence and safety gates

Every candidate and trial follows `AGENTS.md`, `inventory/README.md`, and `WSL-DEVELOPMENT-AND-RECOVERY.md`. In particular:

- synchronize durable records and require SQLite integrity `ok`;
- require pinned PSScriptAnalyzer/PowerShell 5.1 compatibility checks for repository PowerShell and ShellCheck warning-or-higher checks for tracked shell scripts;
- agent-run plan validation before execution without treating it as a human checkpoint;
- obtain fresh explicit approval for any shutdown, boot, installation, elevation, or configuration change affecting the physical host or a shared WSL instance; disposable-fixture equivalents are standing-authorized within the recorded isolated recovery envelope and proceed autonomously;
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

Optional integration work must use separate additive profiles so these two measured baselines remain intact. The practical Rust-userspace idea is recorded as a separate, inactive follow-on in `RUST-MINIMAL-WSL-FOLLOW-ON.md`; its start gate is a frozen, reproducible Minimal Viable WSL result, and its work must not alter this experiment's candidates or evidence.
