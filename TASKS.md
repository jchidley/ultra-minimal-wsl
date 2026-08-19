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
- the evidence-directed `K-HOSTCHAN-001` candidate is built, hashed, reviewed, and plan-validated but not booted.

Not completed:

- the automatic WSL 2.7.12 update changed the packaged initrd after the 2.7.11 recovery gate; the new package state has not been recovery-validated or accepted in `expected-safe-state.json`;
- `K-HOSTCHAN-001` has not been booted, so VMBus/VSOCK restoration is not yet demonstrated;
- most of the 1,792-symbol delta remains unreviewed;
- no reduced Microsoft init exists;
- no custom initrd or WSL package has been deployed.

## Immediate task: revalidate stock state after the WSL 2.7.12 update

`K-HVCORE-DIAG-001` reran the unchanged Hyper-V-core artifact under the pinned ETL/debug-console workflow. It advanced the evidence to `B1`: Linux and stock `/init` ran, but no VMBus device enumerated. Missing `/dev/hvc1` and `/dev/console` were observed; the final fatal error was `UtilConnectVsock` errno 97 (`EAFNOSUPPORT`). Recovery and evidence capture passed.

Completed after diagnosis:

1. raw ETL, decoded XML, extracted custom/stock guest logs, analysis, and hashes are preserved under `recovery-harness/trials/K-HVCORE-DIAG-001/`;
2. `CONFIG_ACPI`, `CONFIG_VSOCKETS`, `CONFIG_HYPERV_VSOCKETS`, console symbols, and Kconfig closure were reviewed/classified in the inventory;
3. `K-HOSTCHAN-001` was built with the minimal controlled ACPI platform-enumeration plus Hyper-V VSOCK bundle;
4. build hashes and plan-only diagnostic validation passed;
5. storage, networking, init-substrate, and virtio/HVC console additions remain excluded.

Next:

1. obtain explicit approval for a new stock recovery validation under WSL 2.7.12;
2. require exact `.wslconfig` restoration, packaged kernel/initrd evidence, Toybox success, and stock recovery before updating `expected-safe-state.json`;
3. only after the canonical safe-state verifier passes, obtain a separate explicit decision before booting `K-HOSTCHAN-001`;
4. run it through `tools/Invoke-WslDiagnosticKernelTrial.ps1` with raw ETL and `debugConsole=true`;
5. require VMBus and `hv_sock` evidence before assigning `B2` or retaining the bundle, then classify the next exact failure.

Do not manually change the installed initrd. The installed 2.7.12 control plane becomes the new fixed condition only after the recovery gate passes.

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
cd C:\Users\jackc\Downloads\ultra-minimal-wsl
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
