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

Candidates form an immutable lineage rather than rewriting earlier experiments:

```text
pinned WSL source
    ↓
broad host/guest reduction
    ↓
fail-closed contract-only parent
    ↓
narrow layers removing reachable excluded-policy hard-fails
    ↓
controlled source or Kconfig siblings selected by runtime evidence
```

Each layer changes one evidence-selected boundary. Source, ABI, or toolchain changes create a new candidate with new policy, mutation, reproducibility, package, runtime, and recovery evidence as applicable. Exact identities belong in candidate records and the runtime plan, not in this conceptual document.

## Why the Windows build remains necessary

The command path crosses Windows and Linux components. A Linux-only build cannot prove that ordinary `wsl.exe` can communicate with the reduced service, launch a distro process, relay its result, and terminate it.

The pinned offline Windows compiler layout is experimental infrastructure, not a target-system requirement. It produces a hash-bound package for a disposable fixture; compiler acquisition or successful compilation proves no runtime gate.

Compilation and runtime are distinct evidence stages but one continuous loop:

1. preserve source and policy evidence;
2. build Linux artifacts twice offline and require byte identity;
3. build and independently verify one controlled package;
4. plan-validate the exact package, probe, and recovery operation;
5. run the unchanged candidate interval;
6. restore stock and prove independent recovery;
7. classify the earliest supported gate and select the next narrow change.

Only the disposable fixture carries standing authorization for that loop. Physical-host or shared-WSL effects require fresh explicit approval.

## Path to Minimal Viable WSL

1. Preserve the mkroot `G4` lower bound and stock `B6-T` comparison baseline.
2. Remove reachable host/guest hard-fails for excluded policy instead of adding their kernel facilities.
3. Establish command dispatch, relay, lifecycle, and Toybox `B6-T` through ordinary `wsl.exe`.
4. Ablate each provisional source and Kconfig bundle with controlled siblings, unchanged probes, and independent recovery.
5. Classify every non-mkroot facility and pass the repeated cold-start and reproducibility gates.
6. Freeze the resulting Toybox-capable core as `minimal-viable-wsl-v1`.
7. Test Alpine, Arch, and Debian in order, attributing and proving each compatibility addition before freezing `ultra-minimal-wsl-v1`.

This sequence prevents stock product policy, fixture mechanics, or assumptions from a large distribution from being mistaken for generic WSL requirements.

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
