# What to do next

Updated 2026-08-19. This is the canonical active task list. `STATUS.md` records evidence; `MINIMAL-BOOT-PLAN.md` defines trial rules and completion criteria.

## Current position

Completed:

- untouched mkroot passes Toybox checkpoint G4 under QEMU;
- matching unmodified WSL 2.7.11 Linux `init` and deterministic initrd build reproducibly;
- Microsoft’s documented custom-kernel, build, deployment, test and debugging workflows have been reviewed;
- the kernel-only harness passes isolated config-transform and non-mutating plan tests;
- `K-RECOVERY-001` validated the supported external-kernel switch and exact recovery path using a byte-identical stock-kernel copy;
- Toybox passed `B6-T`, `.wslconfig` was restored byte-for-byte, packaged kernel/initrd hashes remained correct, and stock Debian booted;
- a PowerShell 5.1 lazy ledger-read handle was diagnosed and fixed; the PASS row was finalized safely and the active journal was removed;
- `K-MKROOT-001` tested the untouched mkroot kernel and reached `B0` with no output before timeout;
- `K-HVCORE-001` added the reviewed nine-symbol Hyper-V execution closure but initially had no observable output;
- `K-HVCORE-DIAG-001` reran that unchanged artifact with ETL/debug-console diagnostics, proved `B1`, and isolated missing VMBus platform enumeration plus fatal VSOCK `EAFNOSUPPORT`;
- all custom trials restored exact stock state and proved stock Debian startup;
- `K-RECOVERY-002` revalidated WSL 2.7.12.0 and its new packaged initrd, and the canonical safe-state verifier passes;
- `K-HOSTCHAN-001` proved ACPI-driven VMBus 5.3 enumeration plus AF_VSOCK/`hv_sock`, advancing the sequential checkpoint from `B1` to `B2`;
- post-trial source/trace correlation corrected the preliminary diagnosis: the terminal exception was WSL 2.7.12 `GetLunDeviceName` timing out because Hyper-V storage was absent; cgroup failure was non-terminal, and mirrored-mode rejection was caused by `SeccompAvailable=0`;
- `K-STORAGE-001` added only `SCSI_LOWLEVEL` and `HYPERV_STORAGE`, proved `B3` through direct `storvsc` disk and system-distro ext4 evidence, then reproduced Stage 3's exact `mini_init` segfault/panic;
- exact restoration, stock recovery, WPR/relay cleanup, terminal ledger state, decoded ETL, extracted logs, crash artifacts, analysis, and hashes all passed;
- the canonical safe-state verifier passes;
- SQLite records the five reference configs, three evidence-directed candidate configs, and all eight trials; durable config/trial manifests supplement immutable ledger rows and integrity passes.

Not completed:

- no candidate has kept `mini_init` alive after the system-distro root mount (`B4`);
- the narrow overlayfs candidate has not been generated or built;
- most of the 1,792-symbol delta remains unreviewed;
- no reduced Microsoft init exists;
- no custom initrd or WSL package has been deployed.

## Immediate task: classify and prepare the post-B3 overlay closure

`POST-B2-CLOSURE-ANALYSIS.md` correlates the immutable `K-HOSTCHAN-001` trace with exact WSL 2.7.12 source commit `68f601b...69ade`:

- `CONFIG_CGROUPS` failure was logged, but stock mini-init ignores the cgroup2 mount result and continued;
- mirrored networking was rejected because mini-init reported `SeccompAvailable=0`; `CONFIG_NET_NS` was not the observed reason;
- the terminal guest exception was exact `main.cpp:972`, inside `GetLunDeviceName`, after its 15-second retry opening the Hyper-V SCSI LUN sysfs block path;
- the subsequent GNS socket closure and host `0x80072746` were consequences of guest termination;
- `CONFIG_SCSI=y` and `CONFIG_HYPERV_VMBUS=y` are already present, leaving the reviewed explicit closure `CONFIG_SCSI_LOWLEVEL=y` plus `CONFIG_HYPERV_STORAGE=y`.

`K-STORAGE-001` evidence:

- kernel SHA-256 `3d3a4f9cee018590d986912b4379119cf22bb8b6e4aee3c29ad43f5450efa367`;
- `hv_storvsc` registered, `storvsc_host_t` appeared, two Microsoft Virtual Disks attached, and `EXT4-fs (sda)` mounted read-only;
- `mini_init` then segfaulted at `0x2e99dc`, followed by `Attempted to kill init` panic;
- the crash is byte-for-byte equivalent at the fault site to Stage 3;
- exact source calls `UtilMountOverlayFs` immediately after this ext4 mount, and `CONFIG_OVERLAY_FS=n` in both failing configs;
- `OVERLAY_FS` selects `FS_STACK`; `EXPORTFS` is already enabled.

Next:

1. generate a candidate from `K-STORAGE-001` with only `CONFIG_OVERLAY_FS=y` explicitly added;
2. add its full config, parent, hash, and trial ID to `inventory/config-snapshots.csv`;
3. review all resulting defaults, especially overlay redirect/xino options, and hold unrelated options disabled where possible;
4. run `uv run python tools/inventory_records.py` and require SQLite integrity `ok`;
5. build, hash, archive, and plan-validate without booting;
6. continue excluding cgroups, networking/seccomp, page reporting, and console support;
7. obtain new explicit approval before any overlay candidate boot.

Do not manually change the installed initrd. WSL 2.7.12.0 and initrd `a76ddd9b...6b118` are now the recovery-validated fixed condition.

The harness must never write under `C:\Program Files\WSL`. It eagerly closes ledger reads, retries genuine transient locks, rejects conflicting duplicate trial IDs, and can finalize a completed PASS result from its journal after independently reverifying stock startup.

## Parallel analysis: review the kernel delta

Before adding a bundle:

1. inspect its Kconfig dependencies and reverse dependencies;
2. identify symbols that support QEMU hardware rather than WSL/Hyper-V;
3. classify documented optional Microsoft scenarios as deferred;
4. group the remaining symbols into Hyper-V execution, storage, host channel, init substrate and command-dispatch bundles;
5. record evidence in the inventory before each trial.

## Later track: reduced Microsoft control plane

The final target remains a reduced single-user WSL control plane preserving `wsl.exe` dispatch. It is no longer a prerequisite for the first supported kernel trials.

Microsoft provides no `.wslconfig` custom-initrd setting. Do not replace the host’s installed initrd as part of the normal kernel workflow. For reduced-init testing, prefer Microsoft’s documented platform-development route:

1. install the optional Windows WSL build prerequisites only when the user chooses;
2. build a controlled WSL package or service-level initrd override;
3. deploy it to a disposable Windows Hyper-V VM with `tools\deploy\deploy-to-vm.ps1`;
4. use a VM checkpoint as an additional rollback safeguard;
5. run WSL tests and collect ETL/debug-console output there.

A transient host initrd replacement is a separate high-risk fallback, not the default plan. It requires a new explicit decision and recovery review.

## Optional user-invoked task: full Windows WSL build prerequisites

This is not required for kernel-only trials. It is needed only for building `wslservice.exe`, a complete MSI, or a supported custom-initrd mechanism.

The Visual Studio installer estimated approximately **3 GB**. The attempted installation on 2026-08-18 was cancelled; verification showed none of the requested components installed.

From an elevated PowerShell, explicitly invoke:

```powershell
cd C:\Users\jackc\git\ultra-minimal-wsl
.\tools\install-wsl-windows-build-prereqs.ps1 -Install
```

The script does nothing without `-Install` and must never be started automatically.

## Deferred until minimal command dispatch works

- networking and DNS;
- DrvFs/9P/virtiofs;
- systemd and broader cgroups;
- containers, netfilter and BPF;
- USB/device forwarding;
- GUI/GPU integration.
