# How this project reaches a minimal working WSL

This page explains the project’s mental model: what the control plane is, why the evidence gates exist, what different tests prove, and how the work leads to a fully functioning minimal WSL system.

It is an explanation, not the current status ledger or an execution runbook. For current results see `STATUS.md`; for exact gate definitions and experiment rules see `MINIMAL-BOOT-PLAN.md`.

## The system being minimized

A WSL command crosses several distinct layers:

```text
wsl.exe
    ↓
Windows WSL service
    ↓  Hyper-V VSOCK protocol
Linux mini_init in the WSL utility VM
    ↓
per-distribution /init
    ↓
requested Linux process
```

The Linux kernel makes the virtual machine run. It does not, by itself, make that machine controllable through `wsl.exe`.

### The control plane

The **control plane** is the Windows and Linux software that coordinates the layers above. For the project’s minimal contract it must:

- negotiate between the Windows service and guest;
- receive and mount one registered distribution’s ext4 VHDX;
- enter that distribution’s root filesystem;
- create a process requested by `wsl.exe`;
- relay stdin, stdout, stderr, and exit status;
- report child exits; and
- terminate cleanly or forcibly.

Microsoft’s stock control plane also implements networking, DNS, DrvFs, Windows executable interop, WSLg, systemd policy, import/export, resizing, arbitrary disk management, and other product features. Those are not automatically requirements of Minimal Viable WSL.

The project therefore minimizes two related things:

1. the **kernel/platform floor** needed to run under WSL; and
2. the **host/guest control plane** needed to behave like WSL through ordinary `wsl.exe` commands.

A tiny Linux VM without the second part is not a working WSL implementation.

## Why the project uses evidence gates

A report that a system “boots” is too vague. It could mean that the CPU entered the kernel, that `/init` ran, or that a user command completed. Those outcomes require different facilities.

The gates divide the path into ordered, observable milestones. A later gate depends on the earlier ones, so the first failed gate identifies the subsystem that needs investigation.

### Generic Linux gates

The `G` series proves that the mkroot/Toybox lower bound works independently of WSL:

| Gate | Observation |
|---|---|
| `G0` | Image rejected or no useful execution observed |
| `G1` | Kernel initializes the selected QEMU machine |
| `G2` | Initramfs is unpacked and `/init` is found |
| `G3` | Toybox `/init` runs as PID 1 |
| `G4` | Toybox shell smoke test passes |

### WSL gates

The `B` series follows the real Windows-to-Linux command path:

| Gate | Observation | What it establishes |
|---|---|---|
| `B0` | Image rejected or guest entry unobserved | No useful WSL progress |
| `B1` | Kernel initializes and executes WSL `/init` | WSL platform entry |
| `B2` | VMBus and Hyper-V VSOCK host channel operate | Host/guest transport |
| `B3` | Required Hyper-V storage appears and ext4 mounts | Registered-distro storage path |
| `B4` | Reduced host/guest control channels remain alive | Control-plane viability |
| `B5` | `wsl.exe` dispatches a command and relays its result | Actual WSL command control |
| `B6-T` | Toybox passes the smoke contract through `wsl.exe` | Minimal generic userspace works |
| `B6-A` | Alpine passes its smoke contract | Alpine compatibility |
| `B6-ARCH` | Arch passes its smoke contract | Arch compatibility |
| `B6-D` | Debian passes its smoke contract | Debian compatibility |

These are evidence boundaries, not software releases. For example, `B3` proves storage attachment and mounting; it does not imply that command dispatch at `B5` works.

## Different work proves different things

### Source inspection proves design boundaries

Source analysis can identify the messages, flags, sockets, mounts, and process paths used by stock WSL. It can also show that excluded operations are absent or rejected in a candidate.

It cannot prove that the Windows and Linux implementations successfully communicate at runtime.

### Protocol-policy tests prove fail-closed behavior

The tests can prove that the recorded implementation policy:

- accepts only named request families on each channel;
- rejects malformed or unknown messages;
- rejects excluded launch, configuration, and process flags; and
- preserves required exit-status and termination framing.

Mutation tests strengthen that claim by deliberately changing an allowlist and requiring the suite to fail.

These tests do not prove that an unmodified `wsl.exe` sends a sufficient sequence for the reduced implementation.

### Reproducible builds prove artifact identity

Two clean builds in distinct ext4 directories prove that the same pinned source, build-host profile, toolchain, and verified cached inputs produce byte-identical Linux artifacts.

This establishes provenance and gives later runtime comparisons controlled inputs. It does not prove that those artifacts boot or satisfy a WSL gate.

### Runtime trials prove behavior

Only a guarded runtime trial can establish `B`-series behavior, choose between namespace variants, or promote a provisional kernel requirement.

A requirement is retained because a controlled comparison shows that removing it causes a repeatable failure and restoring it restores success—not merely because Microsoft enables it or source code mentions it.

## Why stock discovery stopped after the storage boundary

The additive experiments established WSL platform entry, host transport, and storage. Stock initialization then reached Microsoft’s system-distro overlay and finally blocked on GNS networking.

Networking is outside the target contract. Adding more networking support would minimize the kernel underneath Microsoft’s full product control plane rather than minimize WSL’s command-execution contract.

That was the reason to pivot from **adding kernel facilities for stock `/init`** to **removing stock-only host and guest policy**.

## How candidates are layered

Control-plane candidates form an immutable lineage rather than rewriting earlier experiments:

```text
pinned WSL source
    ↓
broad host/guest reduction
    ↓
fail-closed contract-only parent
    ↓
small layers removing reachable hard-fails for excluded policy
    ├── coherent stock-like namespace sibling
    └── mount-only namespace sibling
```

The namespace siblings must share the same parent so their coherent namespace bundle is the only source difference. Neither is preferred merely because it is smaller or resembles stock behavior; runtime evidence must select one. Current candidate identities, hashes, and build results belong in `STATUS.md`, `control-plane/README.md`, and the candidate audit records.

## Why Windows compiler preparation is on the critical path

Reproducible Linux builds can prove candidate source policy and artifact identity, but the retained command path crosses both Windows and Linux components. A Linux-only build cannot prove that an ordinary, unmodified `wsl.exe` can communicate with the reduced service, launch a distro process, relay its result, and terminate it.

A pinned offline Windows compiler layout is therefore experimental infrastructure, not part of Minimal Viable WSL. It makes the controlled package reproducible and allows the patched host and guest pieces to be tested together in a disposable environment without silently changing toolchains or risking the physical host. Compiler acquisition by itself proves no `B` gate.

The remaining proof has three distinct stages:

1. **Enable the experiment:** acquire and verify the pinned compiler inputs, then define the exact offline build and recovery procedure.
2. **Prove viability:** compile the controlled package and establish `B4`, `B5`, `B6-T`, relay, lifecycle, and recovery behavior.
3. **Prove minimality:** compare namespace siblings and ablate provisional kernel bundles, retaining a facility only when controlled removal fails and restoration succeeds.

## Path to Minimal Viable WSL

### 1. Freeze controlled source inputs

Preserve the layered patches, protocol fixture, policy tests, mutation evidence, candidate hashes, and reproducible Linux artifacts. Any source, ABI, or toolchain change becomes a new candidate.

### 2. Build in an isolated Windows environment

After preparation has pinned the compiler inputs and exact build procedure, a separately approved phase must create a disposable Windows VM, establish a known-good stock WSL baseline, install the verified build tools, build the controlled packages, and create a verified recovery checkpoint.

The physical host’s WSL package is not the test surface. Preparation and compilation do not establish a runtime gate; they create the controlled artifacts needed for the comparisons below.

### 3. Establish `B4`

Run each candidate without the system distro, GNS, DNS, DrvFs, WSLg, or interop and show that the required host, mini-init, distro-init, and lifecycle channels remain alive.

### 4. Establish `B5`

Use ordinary, unmodified `wsl.exe` to create a Linux process, relay all standard streams and exit status, and exercise clean and forced termination.

This is the gate that distinguishes a functioning WSL control path from a Linux VM that merely boots.

### 5. Establish `B6-T`

Run the deliberately small Toybox smoke contract through `wsl.exe`:

```sh
test -r /proc/self/status &&
test -d /sys &&
test -c /dev/null &&
printf 'toybox-ok'
```

### 6. Select the namespace bundle

Compare the stock-namespace and mount-only siblings from the same recovery baseline. If mount-only passes the full lifecycle contract, IPC/PID/UTS namespace support remains excluded. If it fails repeatably and the stock bundle restores success, retain only the coherent requirement demonstrated by that comparison.

### 7. Prove minimality by ablation

Remove each provisional feature bundle in turn, require repeated failure, restore it, and require repeated success. Classify every non-mkroot kernel facility and run repeated cold-start, termination, and recovery tests.

The resulting frozen Toybox-capable core becomes `minimal-viable-wsl-v1`.

### 8. Add distribution compatibility without changing the core definition

Test Alpine, Arch, and Debian in that order. Attribute every added requirement to the distribution that selected it, prove it by ablation, and freeze the combined result as `ultra-minimal-wsl-v1`.

This prevents assumptions from a large distribution or its service manager from being mistaken for generic WSL requirements.

## What “fully working” means

Minimal Viable WSL is complete only when it can reproducibly:

- start under WSL 2;
- mount one registered distro’s ext4 VHDX;
- execute commands through ordinary `wsl.exe`;
- relay stdin, stdout, stderr, and signed exit status;
- terminate cleanly and forcibly;
- pass the Toybox smoke contract;
- survive repeated cold starts without unexpected failures; and
- restore the exact known-good stock WSL environment.

Small source or artifact size is not sufficient. The minimum must remain recognizably and reliably WSL, with every retained facility supported by recorded evidence.
