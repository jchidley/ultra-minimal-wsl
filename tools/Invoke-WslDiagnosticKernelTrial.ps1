#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$TrialId,

    [Parameter(Mandatory = $true)]
    [string]$CandidateKernel,

    [Parameter(Mandatory = $true)]
    [string]$TestDistribution,

    [string]$RecoveryDistribution = 'Debian',

    [ValidateRange(5, 600)]
    [int]$TimeoutSeconds = 45,

    [string]$TestCommand = 'test -r /proc/self/status && test -d /sys && test -c /dev/null && printf toybox-ok',

    [Parameter(Mandatory = $true)]
    [string]$SourceCommit,

    [Parameter(Mandatory = $true)]
    [string]$Toolchain,

    [Parameter(Mandatory = $true)]
    [string]$KernelConfigPath,

    [switch]$AllowCustomKernel,
    [switch]$Execute,

    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$WprProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'references\microsoft\WSL-2.7.11\diagnostics\wsl.wprp'),
    [string]$ExpectedWprProfileSha256 = '3f829a9af733d6dce9454a1df2e2aa07096acaaed5b6865ffb5c202d089479f2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$harness = Join-Path $PSScriptRoot 'Invoke-WslKernelTrial.ps1'
$stateRoot = Join-Path $ProjectRoot 'recovery-harness'
$trialDirectory = Join-Path $stateRoot ('trials\' + $TrialId)
$profile = (Resolve-Path -LiteralPath $WprProfilePath).Path
$profileHash = (Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($profileHash -ne $ExpectedWprProfileSha256.ToLowerInvariant()) {
    throw "Pinned WPR profile hash mismatch: $profileHash"
}
if (-not (Get-Command wpr.exe -ErrorAction SilentlyContinue)) { throw 'wpr.exe is not available.' }

$trialArguments = @{
    Mode = 'KernelTrial'
    TrialId = $TrialId
    CandidateKernel = $CandidateKernel
    TestDistribution = $TestDistribution
    RecoveryDistribution = $RecoveryDistribution
    TimeoutSeconds = $TimeoutSeconds
    TestCommand = $TestCommand
    SourceCommit = $SourceCommit
    Toolchain = $Toolchain
    KernelConfigPath = $KernelConfigPath
    AllowCustomKernel = $AllowCustomKernel
    EnableDebugConsole = $true
    StateRoot = $stateRoot
}

Write-Output ([ordered]@{
    diagnosticMode = 'Microsoft WSL ETW profile plus transactional debugConsole'
    execute = [bool]$Execute
    requiresElevation = [bool]$Execute
    elevationReason = 'WPR starts privileged WSL, kernel, and Hyper-V ETW providers; the underlying kernel harness does not require elevation.'
    wprProfile = $profile
    wprProfileSha256 = $profileHash
    wprProfileName = 'WSL'
    etlDestination = (Join-Path $trialDirectory 'windows-wsl.etl')
    exactTimingMetadata = (Join-Path $trialDirectory 'diagnostic-trace.json')
    debugConsole = $true
    note = 'The console window is supplementary; Microsoft.Windows.Lxss.Manager GuestLog events in ETL are the programmatic kernel-log source.'
} | ConvertTo-Json -Depth 5)

# Always run the kernel harness's complete plan/preflight path first. This is
# non-mutating because -Execute is deliberately absent.
& $harness @trialArguments
if (-not $Execute) {
    Write-Host 'DIAGNOSTIC PLAN ONLY: WPR was not started and WSL was not shut down.'
    exit 0
}

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Diagnostic ETW collection requires an elevated PowerShell session.'
}

$staging = Join-Path $stateRoot ('trace-staging\' + $TrialId + '-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($staging) | Out-Null
$startLog = Join-Path $staging 'wpr-start.log'
$stopLog = Join-Path $staging 'wpr-stop.log'
$etlPath = Join-Path $staging 'windows-wsl.etl'
$traceStarted = (Get-Date).ToUniversalTime()
$traceStopped = $null
$wprStarted = $false
$trialError = $null
$stopError = $null
$relayCleanupError = $null
$existingRelayIds = @(Get-Process -Name 'wslrelay' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$newRelayIds = @()

try {
    $startOutput = & wpr.exe -start ($profile + '!WSL') -filemode 2>&1
    $startCode = $LASTEXITCODE
    [IO.File]::WriteAllLines($startLog, [string[]]@($startOutput), [Text.UTF8Encoding]::new($false))
    if ($startCode -ne 0) {
        throw "WPR refused to start (exit $startCode). An existing trace session is not cancelled automatically; see $startLog"
    }
    $wprStarted = $true
    try { & $harness @trialArguments -Execute }
    catch { $trialError = $_ }
}
finally {
    if ($wprStarted) {
        try {
            $stopOutput = & wpr.exe -stop $etlPath 2>&1
            $stopCode = $LASTEXITCODE
            [IO.File]::WriteAllLines($stopLog, [string[]]@($stopOutput), [Text.UTF8Encoding]::new($false))
            if ($stopCode -ne 0) { throw "WPR stop failed with exit $stopCode" }
        }
        catch {
            $stopError = $_
            & wpr.exe -cancel 2>&1 | Out-File -LiteralPath (Join-Path $staging 'wpr-cancel.log') -Encoding utf8
        }
    }
    $traceStopped = (Get-Date).ToUniversalTime()
    try {
        # debugConsole=true creates a wslrelay window which can survive the VM
        # and later restart WSL. Remove only relays created by this wrapper.
        $newRelays = @(Get-Process -Name 'wslrelay' -ErrorAction SilentlyContinue | Where-Object { $existingRelayIds -notcontains $_.Id })
        $newRelayIds = @($newRelays | ForEach-Object { $_.Id })
        $newRelays | Stop-Process -Force -ErrorAction Stop
    }
    catch { $relayCleanupError = $_ }

    $destination = if (Test-Path -LiteralPath $trialDirectory -PathType Container) { $trialDirectory } else { $staging }
    $metadata = [ordered]@{
        schemaVersion = 1
        trialId = $TrialId
        traceStartedUtc = $traceStarted.ToString('o')
        traceStoppedUtc = $traceStopped.ToString('o')
        wprProfile = $profile
        wprProfileSha256 = $profileHash
        wprProfileName = 'WSL'
        debugConsoleEnabledForTrial = $true
        etlCreated = Test-Path -LiteralPath $etlPath -PathType Leaf
        trialError = if ($trialError) { $trialError.Exception.ToString() } else { $null }
        traceStopError = if ($stopError) { $stopError.Exception.ToString() } else { $null }
        diagnosticRelayProcessIds = $newRelayIds
        diagnosticRelayCleanupError = if ($relayCleanupError) { $relayCleanupError.Exception.ToString() } else { $null }
    }
    [IO.File]::WriteAllText((Join-Path $staging 'diagnostic-trace.json'), ($metadata | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    if ($destination -eq $trialDirectory) {
        Get-ChildItem -LiteralPath $staging -File | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination (Join-Path $trialDirectory $_.Name) -Force }
        Remove-Item -LiteralPath $staging -Force
    }
}

if ($stopError) { throw "Diagnostic trace cleanup failed: $($stopError.Exception.Message)" }
if ($relayCleanupError) { throw "Diagnostic relay cleanup failed: $($relayCleanupError.Exception.Message)" }
if ($trialError) { throw $trialError }
Write-Host "Diagnostic trial '$TrialId' completed; ETL and exact timing metadata are in $trialDirectory"
