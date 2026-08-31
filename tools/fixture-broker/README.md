# Ephemeral fixture broker

The broker replaces repeated execution of user-writable scripts as Administrator. It is installed under an ACL-protected Program Files directory, started once for a bounded experiment run, and accepts only one or more explicitly allowlisted workload snapshots.

## Security boundary

- The broker is bound to one configured Hyper-V VM GUID and checkpoint.
- A workload is copied while held with `FileShare.None`, hash-verified, and stored under an administrator-protected run directory before the broker starts.
- Queue files are untrusted data. They may select only a workload already present in the protected allowlist; they cannot provide host paths, hashes, commands, executables, or PowerShell text.
- Jobs are serialized, monotonically numbered, non-replayable, and limited to `status`, `execute`, and `finish`.
- Workload output, credentials, state, and journals live under `%ProgramData%\UltraMinimalWslFixtureBroker\Runs`, where the normal user has no write access except to the run's inbox.
- The broker has no network listener, service, scheduled task, automatic startup, or arbitrary host-command endpoint.
- Failure, idle expiry, maximum lifetime, or `finish` forces the exact fixture Off.

This protects against post-approval replacement and queue injection. It does not make an intentionally allowlisted host workload safe: every workload still requires source review and an exact expected hash before the one UAC approval that creates its run.

## Install

Installation is an explicit physical-host elevation. From PowerShell in the repository root:

```powershell
& tools/fixture-broker/Install-FixtureBroker.ps1 -Confirmed
```

The installer snapshots the broker into `%ProgramFiles%\UltraMinimalWslFixtureBroker`, removes inherited write permissions, and independently verifies the installed hashes and ACLs.

## Start a bounded run

The workload must contain:

```powershell
# FixtureBroker-SecureWorkload: 1
```

It must use `$env:ULTRAMINIMALWSL_SECURE_RUN_ROOT` for every host result and extracted-evidence path and `$env:ULTRAMINIMALWSL_SECURE_CREDENTIAL` for the fixture credential.

```powershell
& tools/fixture-broker/Start-FixtureBrokerRun.ps1 `
  -RunId minimal-v6-k-pidns-runtime-011 `
  -WorkloadId minimal-v6-k-pidns-runtime `
  -WorkloadPath <reviewed-controller.ps1> `
  -WorkloadSha256 <sha256> `
  -Confirmed
```

This is the only UAC prompt for the run.

## Submit and finish

```powershell
& tools/fixture-broker/Submit-FixtureBrokerJob.ps1 `
  -RunId minimal-v6-k-pidns-runtime-011 -Sequence 1 `
  -JobId execute -Operation execute `
  -WorkloadId minimal-v6-k-pidns-runtime

& tools/fixture-broker/Submit-FixtureBrokerJob.ps1 `
  -RunId minimal-v6-k-pidns-runtime-011 -Sequence 2 `
  -JobId finish -Operation finish
```

Never retry a timed-out submission until the protected result and broker status have been inspected.
