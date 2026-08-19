# Minimal WSL kernel experiment status

Updated 2026-08-19. This is the factual project state. `MINIMAL-BOOT-PLAN.md` describes intended procedure and `TASKS.md` separates active work from optional machine setup.

## Safety/current machine state

- The stock Microsoft WSL kernel remains active. Current packaged kernel: 17,334,784 bytes, SHA-256 `d540850bfbf1beba3ded6b2965b9d0249b23fbcb3e90e7dc0845ac7ad86bc861`.
- `C:\Users\jackc\.wslconfig` has no custom `kernel=` entry.
- The mkroot baseline and one Hyper-V-core derivative were activated only inside journaled trials; both failed at `B0` and the stock kernel is active again.
- No file under `C:\Program Files\WSL` has been changed.
- Earlier live verification on 2026-08-19 confirmed the WSL 2.7.11 baseline. During later tooling work Windows updated WSL to 2.7.12.0: the packaged kernel remains `d540850b...bc861`, but the packaged initrd is now 2,836,768 bytes with SHA-256 `a76ddd9b8bad0771c100a32a715cfc15d8553464f4deffcb516454610cd6b118`, not the recovery-validated `bd9c5615...968` baseline. No active recovery journal or custom `.wslconfig` setting was present. This drift is deliberately not accepted in `recovery-harness\expected-safe-state.json` until a new stock recovery validation is explicitly approved and passes.
- `tools\Test-WslSafeState.ps1` now emits the complete check set as JSON and is the canonical verifier; it reports version/package drift or active WSL state as unsafe rather than silently treating teardown races as success.
- The existing Stage 1–3 configs and images remain untouched.
- The independent `Debian-Recovered` export ended with an archive renamed `.partial.failed`. Its separate backup workflow was confirmed idle before both custom trials; always recheck before another disruptive trial.

## Existing WSL kernel evidence

| Kernel | Approximate size | Result |
|---|---:|---|
| Microsoft-config baseline | 15 MB | Built reference |
| Stage 1 | 14 MB | Booted; Alpine, ext4, DrvFs and networking passed |
| Stage 2 | 14 MB | WSL VM creation failed |
| Stage 3 | 6.7 MB | Mounted ext4 and started `mini_init`; init then segfaulted and the kernel panicked |
| Untouched mkroot (`K-MKROOT-001`) | 3.44 MB | `B0`; no output or command dispatch; 45-second timeout; stock recovery passed |
| Hyper-V execution core (`K-HVCORE-001`) | 3.49 MB | Initially unobserved at `B0`; diagnostic retry proved `B1`, stock `/init` execution, missing console, absent VMBus enumeration, and fatal VSOCK `EAFNOSUPPORT`; stock recovery passed |

Stage 1 remains the working upper bound. The first two mkroot-derived WSL trials are failure evidence, not usable candidates.

## New mkroot baseline completed

QEMU 10.0.11 and SquashFS tools 4.6.1 were installed in `LFS-Builder`. Protected detached worktrees were created so mkroot could not clean or overwrite the original source/build trees:

- Toybox: `/root/experiments/minimal-wsl/mkroot-baseline/toybox`
- Microsoft kernel: `/root/experiments/minimal-wsl/mkroot-baseline/WSL2-Linux-Kernel`

Pinned inputs:

- Toybox commit: `b7ec52ac35e075caffca5d330995d44e8dbfc8c3`
- Microsoft WSL kernel commit: `14794180686c2fb6307fbe359c359bec765249f3`
- Compiler: x86_64 musl GCC 15.1.0
- Linker: GNU binutils 2.44

The untouched mkroot build completed successfully in ten minutes. It produced:

- Kernel: 3,441,664 bytes
- Initramfs: 514,424 bytes
- Expanded rootfs: 769,316 bytes, 268 entries
- Microconfig: 3 lines
- Miniconfig: 58 lines
- Full config: 2,273 lines

The generated kernel/initramfs booted with the generated QEMU launcher. It unpacked initramfs, executed `/init` as PID 1, mounted `/proc`, `/sys` and `/dev`, entered the Toybox shell and emitted `MKROOT_G4_PASS_V2`. QEMU exited cleanly. Generic checkpoint **G4 passed**.

Archived, hashed artifacts:

`C:\Users\jackc\git\ultra-minimal-wsl\mkroot-baseline\`

Important files:

- `linux-{microconfig,miniconfig,fullconfig}`
- `linux-kernel`
- `initramfs.cpio.gz`
- `toybox-init`
- `run-qemu.sh`
- `build.log`, `qemu-g4.log`, metadata and result files
- `SHA256SUMS` — independently verified

## Dependency inventory updated

The SQLite/CSV inventory now contains five configs:

- `mkroot`
- `baseline`
- `stage1`
- `stage2`
- `stage3`

Current counts:

- 18,449 Kconfig symbols
- 126,629 conditional relationships
- 608 symbols enabled in mkroot’s full config
- 1,792 mkroot-to-Stage-1 differences

Primary scoped queue:

`inventory\mkroot-stage1-delta.csv`

SQLite integrity passed after regeneration. Real per-symbol review/classification has not started; annotation rows remain unchecked.

## WSL control-plane finding

The user identified that Microsoft init may itself impose unnecessary requirements. This was confirmed by a preliminary source audit and documented in:

`WSL-CONTROL-PLANE-AUDIT.md`

Exact installed/source match:

- Installed WSL: 2.7.11.0
- Matching source tag: `2.7.11`
- Matching commit: `acbcb81fc61079b74835ea7dc2563046b2557033`
- Source worktree: `/root/src/WSL-2.7.11`

Microsoft’s `mini_init` unconditionally performs more than minimal Linux boot, including cgroup2, binfmt_misc/Windows interop registration, cross-distro tmpfs/resolver setup, IPv4 loopback setup, GNS startup and policy/sysctl changes. It also conditionally supports system VHD, swap, chronyd/PTP, module VHD, memory reclaim, DNS tunneling, localhost tracking, mirrored-networking BPF/seccomp, GPU/WSLg, disk management and resource isolation.

This means some apparent kernel requirements are requirements of Microsoft’s broad control plane, not requirements of Toybox or Linux boot.

## Reproducible Linux control-plane build

The unmodified Linux-side WSL 2.7.11 `init` was built from the matching source without installing the full Windows WSL build workload. The WSL-native build uses hash-pinned Microsoft Linux SDK/dependency packages and a deterministic initrd writer.

Two clean builds produced identical hashes:

- `init`: `f953300206810becae4d558445288d49af85c895ee12ae769b722a5ed134663b`
- `init.debug`: `dd9776081f1ce9f63b19c68181fc664b109f3fd4247aa191b7a41c204db87231`
- `initrd.img`: `8c112fd337324585d5f171704ddee38bb533528e04083a2c3e81494c0d429821`

The result is a static x86-64 ELF. Extraction verified that the generated initrd contains the exact generated `init`. A separate extraction verified that Microsoft’s installed initrd contains the exact installed `C:\Program Files\WSL\tools\init`.

The generated binary differs from Microsoft’s installed binary because this reproducible path uses Debian Clang 19.1.7 rather than Microsoft’s Windows build environment. It has not been booted, so protocol/runtime compatibility is not yet claimed.

Artifacts: `control-plane-build/native-build/`. Rebuild tools: `tools/build-control-plane-linux.sh` and `tools/create-initrd-repro.py`.

## Cancelled optional Windows workload

A full Windows WSL build prerequisite installation was offered by Visual Studio at approximately 3 GB. The user cancelled it on 2026-08-18. Post-cancellation checks confirmed that the requested SDK, ATL, Clang, UWP C++ and Managed Desktop components were not installed. No installer process remained and no WSL artifact was changed.

This workload is not required for Linux-side init reduction. It is now an explicitly user-invoked optional task in `TASKS.md`, using `tools/install-wsl-windows-build-prereqs.ps1 -Install`. The script performs no installation without `-Install`.

Source inspection also established that WSL 2.7.11 takes `InitRdPath` from its fixed installation tools directory; `.wslconfig` has no custom-initrd setting. Custom-initrd testing is therefore separated from supported kernel-only trials and deferred to the platform-development track, preferably in a disposable Hyper-V Windows VM.

## Documents and tools

- `README.md` — overview/navigation
- `STATUS.md` — current factual state
- `TASKS.md` — active, optional and deferred tasks
- `MKROOT-MINIMAL-BOOT-METHOD.md` — Landley’s derivation
- `MINIMAL-BOOT-PLAN.md` — experiment procedure
- `KERNEL-CONFIG-PROVENANCE.md` — Microsoft config rationale
- `WSL-CONTROL-PLANE-AUDIT.md` — preliminary mini-init audit and target choices
- `WSL-DEVELOPMENT-AND-RECOVERY.md` — Microsoft-supported kernel recovery and platform test workflow
- `inventory/README.md` — inventory usage
- `tools/build-kconfig-inventory.py` — graph generator
- `tools/inventory.py` — graph search/annotation utility
- `tools/build-control-plane-linux.sh` — reproducible Linux-side WSL init builder
- `tools/create-initrd-repro.py` — deterministic one-file WSL initrd writer
- `tools/install-wsl-windows-build-prereqs.ps1` — guarded optional full Windows build prerequisites
- `tools/Invoke-WslKernelTrial.ps1` — supported external-kernel switch/test/restore harness
- `tools/Test-WslKernelTrial.ps1` — non-disruptive parser, guard and plan-only tests
- `recovery-harness/README.md` — harness evidence and remaining runtime gate
- `candidates/wsl-2.7.11-stock-kernel` — external byte-identical packaged-kernel copy
- `references/landley/` — archived primary research

## Pre-dispatch diagnostic result

Microsoft's matching WSL 2.7.11 `wsl.wprp` and collector are pinned and hashed under `references/microsoft/WSL-2.7.11/diagnostics/`. `tools/Invoke-WslDiagnosticKernelTrial.ps1` wraps the recovery harness with the Microsoft `WSL` WPR profile, exact UTC metadata, durable ETL output, and transactionally restored `debugConsole=true`.

Approved trial `K-HVCORE-DIAG-001` reran the unchanged `K-HVCORE-001` image and produced decisive evidence:

- 180 `GuestLog` records prove Linux 6.18.40.1+ entry, Microsoft Hyper-V detection, CPU/memory initialization, initramfs unpack, and execution of Microsoft stock `/init`;
- no VMBus devices enumerated, so the highest checkpoint is `B1`, not `B2`;
- the kernel and `mini_init` reported missing `/dev/hvc1` and `/dev/console`;
- `mini_init` then failed `UtilConnectVsock` with errno 97 (`EAFNOSUPPORT`) while `CONFIG_VSOCKETS` and `CONFIG_HYPERV_VSOCKETS` were disabled;
- the custom VM had no `CreateVmEnd` and ended with host timeout `0x800705b4`;
- exact `.wslconfig` restoration, packaged hashes, stock Debian startup, ETL stop, terminal ledger append, and journal removal all passed;
- the debug-console relay outlived the completed VM and was stopped; the wrapper now removes only `wslrelay.exe` processes created by that diagnostic invocation.

Evidence is under `recovery-harness/trials/K-HVCORE-DIAG-001/`, including raw ETL, less-restricted XML, extracted custom/stock guest logs, `analysis.json`, and verified `SHA256SUMS`. `PRE-DISPATCH-DIAGNOSTICS.md` records the source workflow and interpretation rules.

## Next candidate prepared, not booted

`candidates/K-HOSTCHAN-001/` retains the Hyper-V execution core and adds only the evidence-directed host-channel/platform bundle:

- explicit: `CONFIG_ACPI`, `CONFIG_VSOCKETS`, `CONFIG_HYPERV_VSOCKETS`;
- unrelated ACPI/VSOCK defaults are held disabled where Kconfig permits;
- hidden/default ACPI platform closure is recorded and classified as transitive;
- kernel: 3,712,000 bytes, SHA-256 `7dbf16c3bb9129f3634f3700ed2dfc59974df4de9a7ad0b9aec6a05b7cc8703b`;
- config SHA-256 `8a6d7bd1731e6af350a6138a92dc157e5d7c0b36602cf87a697520fd125bbc6e`;
- build and diagnostic plan-only validation passed.

The separate virtio/HVC console bundle was not added because console absence was observable but the final fatal blocker was VSOCK. `K-HOSTCHAN-001` has not been booted and requires a new explicit decision.

## Deliberately not done

- No mkroot-derived trial has reached Toybox command dispatch; the diagnostic retry made kernel and `/init` execution observable at `B1`.
- The evidence-directed host-channel candidate has been built but not booted.
- The target is a patched single-user WSL control plane preserving `wsl.exe` command dispatch; only an unmodified reference init/initrd has been built, and no replacement has been deployed.
- The 1,792-symbol delta has not been grouped or reviewed.
- Toybox and Alpine have not been tested under a mkroot-derived WSL kernel.
- No project-wide checksum manifest has been refreshed; the mkroot-baseline subdirectory has its own verified manifest.

## Selected target and next gate

Selected on resumption: **smallest kernel plus a patched single-user WSL control plane preserving `wsl.exe` command dispatch**.

Rationale:

- unmodified Microsoft init would make audience-wide policy and optional services part of the measured minimum;
- bypassing WSL would lose distribution registration, `wsl.exe` dispatch and WSL lifecycle management, changing the project rather than minimising it;
- the reduced control plane retains the defining host/guest command path while allowing unrelated services to be excluded.

Custom-kernel recovery is supported and does not replace Microsoft’s kernel: candidates remain outside `C:\Program Files\WSL`, and removing `.wslconfig` `kernel=` restores the packaged kernel. `K-RECOVERY-001` selected the external byte-identical stock copy, passed the Toybox smoke test at `B6-T`, restored the exact original `.wslconfig`, reverified the packaged-kernel hash, and booted stock Debian. A PowerShell 5.1 lazy `File.ReadLines` handle blocked ledger append and left the completed PASS journaled; the hardened `-Recover` path reverified stock startup, finalized the PASS row, and removed the journal. The harness now reads the header eagerly, retries genuine transient locks, and treats repeated finalization idempotently. `K-MKROOT-001` then tested the unchanged mkroot kernel with Microsoft’s stock initrd and reached `B0`: no output, no command dispatch, and timeout. `K-HVCORE-001` added only the reviewed Hyper-V execution-core closure and its first uninstrumented trial was conservatively classified `B0`. Both trials restored exact stock state and proved stock Debian startup. `K-HVCORE-DIAG-001` then proved the unchanged artifact reached `B1` and executed stock `/init`. The diagnostic gate identified missing runtime VMBus platform enumeration and AF_VSOCK transport. The next gate, after a new explicit decision, is the prepared `K-HOSTCHAN-001` trial under the same ETL/debug-console wrapper. No storage, networking, init-substrate, or console bundle should be added before that result. Reduced-init testing remains a later controlled-package track, preferably in a disposable Hyper-V Windows VM. The optional approximately 3 GB Windows workload remains uninstalled. See `TASKS.md` and `WSL-DEVELOPMENT-AND-RECOVERY.md`.
