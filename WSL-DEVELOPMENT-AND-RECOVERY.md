# WSL kernel trial and recovery runbook

A custom WSL kernel is global to every WSL 2 distro. Use the guarded harness; never switch kernels manually during an experiment.

## Supported kernel override

Microsoft’s packaged kernel remains at `C:\Program Files\WSL\tools\kernel`. The supported override points `.wslconfig` at a separate image:

```ini
[wsl2]
kernel=C:/path/to/candidate/kernel
```

Removing `kernel=` and shutting WSL down restores selection of the packaged kernel. An empty value is not a fallback.

## Before any trial

1. Obtain explicit approval for interruption of every WSL 2 distro.
2. Require `tools/Test-WslSafeState.ps1` to report `safe:true`.
3. Record WSL version and packaged kernel/initrd hashes.
4. Preserve `.wslconfig` byte-for-byte.
5. Verify candidate config, image, metadata, and hashes.
6. Synchronize inventory records and require SQLite integrity `ok`.
7. Run `tools/Test-WslKernelTrial.ps1` and harness plan mode.

No approval is implied by a prepared candidate or plan validation.

## Ordinary trial

`tools/Invoke-WslKernelTrial.ps1` journals before changing `.wslconfig`, enforces serial execution and timeouts, restores the exact original file in `finally`, verifies packaged hashes, and boots a recovery distro before finalizing the ledger.

Run it unelevated. Its execute path requires both the explicit custom-kernel guard and `-Execute`. It has no write path beneath `C:\Program Files\WSL`.

After completion, independently run `tools/Test-WslSafeState.ps1`. A timeout does not prove a process, VM, or elevated child stopped.

## Diagnostic trial

Use `tools/Invoke-WslDiagnosticKernelTrial.ps1` only when ordinary evidence cannot classify a pre-dispatch failure. It adds Microsoft’s WPR profile, exact trace timing, and transactional `debugConsole=true` around the same recovery harness.

Diagnostic execution requires separate approval and elevation because WPR enables privileged ETW providers. Transport a reviewed fixed PowerShell script through `windows-env/ps-elevate`; do not rely on an agent-side timeout to stop it.

Interpret only evidence inside the recorded interval:

| Evidence | Highest supported conclusion |
|---|---|
| host loader/compute failure | guest entry not established |
| early kernel `GuestLog` | `B1` |
| VMBus/VSOCK enumeration | `B2` |
| Hyper-V disk plus ext4 mount | `B3` |
| stable host/control messaging | `B4` candidate |
| command output marker | `B5` or the applicable `B6-*` |

Absence is meaningful only when the relevant provider was active and trace start/stop succeeded.

## Recovery invariants

Every trial must leave:

- the original `.wslconfig` restored exactly;
- no custom kernel selected;
- packaged kernel/initrd hashes verified;
- stock Debian command execution proven;
- a terminal immutable ledger row;
- no active journal, WPR session, or diagnostic relay;
- analysis and hashes preserved under `recovery-harness/trials/<TRIAL_ID>/`.

If finalization is interrupted, use the harness recovery path. Never hand-edit a completed ledger row.

## Initrd and control-plane work

`.wslconfig` has no custom-initrd setting. Do not replace the installed initrd. Build and deploy reduced-control-plane changes as a controlled WSL package inside a disposable Hyper-V Windows VM with a checkpoint.

## References

- WSL advanced settings: <https://learn.microsoft.com/windows/wsl/wsl-config>
- WSL development loop: <https://wsl.dev/dev-loop/>
- WSL diagnostics: <https://wsl.dev/debugging/>
- WSL architecture: <https://wsl.dev/technical-documentation/boot-process/>
