# WSL kernel development and recovery

This page explains how the stock kernel is preserved, how Microsoft documents development/testing, and where this experiment differs from the supported path.

## Custom kernels do not replace the stock kernel

WSL’s packaged kernel remains under:

`C:\Program Files\WSL\tools\kernel`

The supported `.wslconfig` setting points WSL at a separate custom image:

```ini
[wsl2]
kernel=C:/Users/jackc/git/ultra-minimal-wsl/candidates/kernel-test
```

The setting is global to WSL 2 and takes effect after `wsl.exe --shutdown`. It does not overwrite the packaged kernel.

To return to Microsoft’s kernel:

1. run `wsl.exe --shutdown`;
2. remove only the `kernel=` line from `%USERPROFILE%\.wslconfig`;
3. also remove `kernelModules=` if it belongs to that custom kernel;
4. start the designated distro;
5. verify `uname -r` and basic command execution.

An empty custom-kernel setting is not the fallback. Absence of the setting makes WSL select its packaged kernel.

Before testing, record:

- `wsl.exe --version`;
- SHA-256 of the packaged kernel;
- a byte-for-byte backup of `.wslconfig`;
- SHA-256 and source/config metadata for the candidate.

The packaged kernel may legitimately change after `wsl.exe --update`, so version and hash must be recorded together.

## Kernel trials remain serial

All WSL 2 distributions use the same utility VM and selected kernel. A kernel change therefore requires `wsl.exe --shutdown` and affects the next start of every WSL 2 distro. Keep multiple image files, but test them one at a time.

## The initrd is different

Microsoft documents `.wslconfig` overrides for `kernel`, `kernelModules` and `kernelCommandLine`, but not for the WSL initrd. WSL 2.7.11 source sets `InitRdPath` from its installation tools directory, normally:

`C:\Program Files\WSL\tools\initrd.img`

Therefore:

- kernel testing uses a supported external path and leaves packaged files untouched;
- reduced-control-plane testing cannot use the same mechanism;
- transient initrd replacement on the host would modify an installed WSL artifact and requires stronger recovery controls;
- the Microsoft-aligned isolation option is to build/deploy a custom WSL package into a disposable Hyper-V Windows VM, ideally with a checkpoint.

No custom initrd should be tested on the host until its separate deployment/recovery approach is explicitly approved and dry-run with a byte-identical stock copy.

## Microsoft’s documented development workflow

For WSL platform development, Microsoft documents:

1. build the WSL repository on Windows with Visual Studio, CMake and Windows SDK 26100;
2. deploy the generated MSI to the host with `tools\deploy\deploy-to-host.ps1`, or to a Hyper-V VM with `tools\deploy\deploy-to-vm.ps1`;
3. run `bin\<platform>\<target>\test.bat`, optionally selecting unit tests or a specific test;
4. use `WSL_DEV_BINARY_PATH` and `WSL_BUILD_THIN_PACKAGE` for faster development iterations;
5. collect ETL traces, enable `debugConsole=true`, or use `wsl --debug-shell` for diagnostics.

For this experiment, host `.wslconfig` switching is appropriate for kernel-only trials. A disposable Hyper-V VM is preferable once `wslservice.exe`, the MSI, or the installed initrd must change.

## Local kernel-only harness

`tools\Invoke-WslKernelTrial.ps1` implements the supported external-kernel path. It reads and hashes the packaged kernel but has no write path beneath `C:\Program Files\WSL`. It journals before changing `.wslconfig`, restores the exact original bytes in `finally`, enforces serial trials and timeouts, captures command/dmesg/event/crash output, verifies hashes, and boots a recovery distro on the packaged kernel before completing the ledger row.

`tools\Test-WslKernelTrial.ps1` and `-SelfTest` exercise parsing, guards, candidate hashes, encoding/newline transforms and plan mode without shutting WSL down. `tools\Test-WslSafeState.ps1` replaces ad-hoc inline verifiers: it emits one JSON document, uses process exit codes and encoding-aware native-output capture rather than `$LASTEXITCODE`/NUL heuristics, and checks the versioned `recovery-harness\expected-safe-state.json` baseline, custom settings, the recovery journal and ledger, WSL management/runtime state, debug relays, WPR, and optional Visual Studio components. A safe result exits 0; an unsafe result still emits complete JSON and exits 1. `-SelfTest` is host-state-independent and is included in the plan-only test suite. Do not update the baseline merely because a hash drifted: finish any installer/update, record the new WSL version, and repeat the stock recovery validation first.

Run it through the boundary helper:

```bash
windows-env/ps-exec --stdin <<'POWERSHELL'
& 'C:\Users\jackc\git\ultra-minimal-wsl\tools\Test-WslSafeState.ps1'
POWERSHELL
```

`tools\Invoke-WslDiagnosticKernelTrial.ps1` adds a plan-only-by-default wrapper around the same recovery harness. Its execute path requires elevation and the existing explicit custom-kernel gates, starts the pinned Microsoft WSL 2.7.11 WPR profile, transactionally enables `debugConsole=true`, and stops ETW capture in `finally`. See `PRE-DISPATCH-DIAGNOSTICS.md`. The first execute-mode validation, `K-RECOVERY-001`, passed with the external byte-identical copy at `candidates\wsl-2.7.11-stock-kernel`: Toybox booted, exact `.wslconfig` restoration and packaged-kernel hashes passed, and stock Debian booted. A PowerShell 5.1 lazy ledger-read handle was diagnosed after the journaled recovery path reverified stock startup; ledger headers are now read eagerly, genuine locks are retried, and repeated finalization is idempotent.

The harness changes a global WSL setting and invokes `wsl.exe --shutdown`; even stock-copy validation should run only when interruption of every active WSL distribution is acceptable.

## Primary Microsoft sources

- Advanced WSL settings (`kernel`, `kernelModules`, `safeMode`, shutdown semantics):
  <https://learn.microsoft.com/windows/wsl/wsl-config>
- WSL build, deployment and test loop:
  <https://wsl.dev/dev-loop/>
- WSL debugging and logging:
  <https://wsl.dev/debugging/>
- WSL architecture and boot process:
  <https://wsl.dev/technical-documentation/boot-process/>
- WSL source, matching development configuration:
  <https://github.com/microsoft/WSL>
- Microsoft WSL kernel source:
  <https://github.com/microsoft/WSL2-Linux-Kernel>
