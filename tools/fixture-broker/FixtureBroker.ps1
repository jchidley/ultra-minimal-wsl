#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $RunRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Fixture broker must run elevated.'
}

$installRoot = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $installRoot 'FixtureBroker.Policy.psm1') -Force
$runBase = Get-CanonicalPath (Join-Path $env:ProgramData 'UltraMinimalWslFixtureBroker\Runs')
$runRootPath = Assert-PathUnderRoots -Path $RunRoot -Roots @($runBase) -MustExist
$configPath = Join-Path $runRootPath 'private\run-config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'Protected run configuration is missing.' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.schema -ne 1) { throw 'Unsupported run configuration.' }
Assert-BrokerId ([string]$config.runId) 'runId' | Out-Null
Assert-ProtectedAcl -Path $installRoot -UserSid ([string]$config.userSid) | Out-Null
Assert-ProtectedAcl -Path (Join-Path $runRootPath 'private') -UserSid ([string]$config.userSid) | Out-Null
Assert-ProtectedAcl -Path (Join-Path $runRootPath 'results') -UserSid ([string]$config.userSid) | Out-Null

$inbox = Join-Path $runRootPath 'inbox'
$private = Join-Path $runRootPath 'private'
$results = Join-Path $runRootPath 'results'
$processing = Join-Path $private 'processing'
$workloadRoot = Join-Path $private 'workloads'
$credentialPath = Join-Path $private 'fixture.credential.clixml'
$brokerStatusPath = Join-Path $results 'broker-status.json'
$journalPath = Join-Path $results 'journal.jsonl'
[IO.Directory]::CreateDirectory($processing) | Out-Null

function Write-AtomicJson {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][object] $Value)
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-Journal {
    param([Parameter(Mandatory)][string] $EventName, [hashtable] $Data = @{})
    $entry = [ordered]@{ utc = [DateTime]::UtcNow.ToString('o'); event = $EventName; data = $Data }
    [IO.File]::AppendAllText($journalPath, (($entry | ConvertTo-Json -Depth 10 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Write-BrokerStatus {
    param([Parameter(Mandatory)][string] $State, [string] $Detail = '')
    Write-AtomicJson $brokerStatusPath ([ordered]@{
        schema = 1
        runId = $config.runId
        state = $State
        detail = $Detail
        processId = $PID
        vmId = $config.vmId
        updatedUtc = [DateTime]::UtcNow.ToString('o')
    })
}

function Stop-ExactFixture {
    $vm = Get-VM -Name ([string]$config.vmName) -ErrorAction Stop
    if ($vm.Id.Guid -ne [string]$config.vmId) { throw 'Fixture identity mismatch during finalization.' }
    if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
        Stop-VM -VM $vm -Confirm:$false | Out-Null
    }
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do {
        $vm = Get-VM -Name ([string]$config.vmName) -ErrorAction Stop
        if ($vm.State -eq [Microsoft.HyperV.PowerShell.VMState]::Off) { return }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Fixture did not return Off.'
}

function Copy-JobToProtectedSnapshot {
    param([Parameter(Mandatory)][string] $Source)
    Assert-NoReparsePoint $Source
    $name = [IO.Path]::GetFileName($Source)
    if ($name -notmatch '^([0-9]{9})-([A-Za-z0-9][A-Za-z0-9._-]{0,63})\.job\.json$') {
        throw 'Invalid job filename.'
    }
    $destination = Join-Path $processing ($name + '.' + [Guid]::NewGuid().ToString('N'))
    $jobStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        if ($jobStream.Length -gt 65536) { throw 'Job manifest exceeds 64 KiB.' }
        $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $jobStream.CopyTo($output); $output.Flush($true) }
        finally { $output.Dispose() }
    }
    finally { $jobStream.Dispose() }
    Remove-Item -LiteralPath $Source -Force
    $destination
}

function Get-Workload {
    param([Parameter(Mandatory)][string] $Id)
    $workloadMatches = @($config.workloads | Where-Object { $_.id -eq $Id })
    if ($workloadMatches.Count -ne 1) { throw 'Workload is not in the protected allowlist.' }
    $workload = $workloadMatches[0]
    Assert-BrokerId ([string]$workload.id) 'workloadId' | Out-Null
    Assert-Sha256 ([string]$workload.sha256) | Out-Null
    $path = Assert-PathUnderRoots -Path (Join-Path $workloadRoot ([string]$workload.file)) -Roots @($workloadRoot) -MustExist -Leaf
    Assert-NoReparsePoint $path
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { $actual = Get-StreamSha256 $stream }
    finally { $stream.Dispose() }
    if ($actual -ne [string]$workload.sha256) { throw 'Protected workload hash mismatch.' }
    [pscustomobject]@{ Record = $workload; Path = $path }
}

function Invoke-AllowlistedWorkload {
    param([Parameter(Mandatory)][object] $Workload)
    $stdout = Join-Path $results ($Workload.Record.id + '.stdout.log')
    $stderr = Join-Path $results ($Workload.Record.id + '.stderr.log')
    $env:ULTRAMINIMALWSL_SECURE_RUN_ROOT = $runRootPath
    $env:ULTRAMINIMALWSL_SECURE_CREDENTIAL = $credentialPath
    try {
        $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Workload.Path)
        $process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList $arguments `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $timeout = [TimeSpan]::FromSeconds([int]$Workload.Record.timeoutSeconds)
        if (-not $process.WaitForExit([int]$timeout.TotalMilliseconds)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw 'Allowlisted workload timed out.'
        }
        if ($process.ExitCode -ne 0) { throw "Allowlisted workload failed with exit $($process.ExitCode)." }
        Stop-ExactFixture
        [ordered]@{ exitCode = 0; stdout = [IO.Path]::GetFileName($stdout); stderr = [IO.Path]::GetFileName($stderr) }
    }
    finally {
        Remove-Item Env:ULTRAMINIMALWSL_SECURE_RUN_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:ULTRAMINIMALWSL_SECURE_CREDENTIAL -ErrorAction SilentlyContinue
    }
}

$mutexName = 'Global\UltraMinimalWslFixtureBroker-' + $config.vmId
$mutex = [Threading.Mutex]::new($false, $mutexName)
$hasMutex = $false
$finished = $false
$expectedSequence = 1L
$processedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$executedWorkloads = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$startedUtc = [DateTime]::UtcNow
$lastJobUtc = $startedUtc
try {
    $hasMutex = $mutex.WaitOne(0)
    if (-not $hasMutex) { throw 'Another fixture broker owns this VM.' }
    $vm = Get-VM -Name ([string]$config.vmName) -ErrorAction Stop
    if ($vm.Id.Guid -ne [string]$config.vmId -or $vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
        throw 'Fixture must match the protected identity and begin Off.'
    }
    $snapshots = @(Get-VMSnapshot -VM $vm | Select-Object -ExpandProperty Name)
    if ($snapshots.Count -ne 1 -or $snapshots[0] -ne [string]$config.checkpoint) { throw 'Fixture checkpoint mismatch.' }
    Write-BrokerStatus 'ready'
    Write-Journal 'broker-ready' @{ expectedSequence = $expectedSequence }
    while (-not $finished) {
        if ([DateTime]::UtcNow - $startedUtc -gt [TimeSpan]::FromSeconds([int]$config.maximumLifetimeSeconds)) {
            throw 'Broker maximum lifetime expired.'
        }
        if ([DateTime]::UtcNow - $lastJobUtc -gt [TimeSpan]::FromSeconds([int]$config.idleTimeoutSeconds)) {
            throw 'Broker idle timeout expired.'
        }
        $jobs = @(Get-ChildItem -LiteralPath $inbox -File -Filter '*.job.json' | Sort-Object Name)
        if ($jobs.Count -eq 0) { Start-Sleep -Milliseconds 250; continue }
        $snapshot = $null
        try {
            $snapshot = Copy-JobToProtectedSnapshot $jobs[0].FullName
            $job = Read-StrictJob $snapshot
            $sequence = Assert-Sequence $job.sequence
            if ($sequence -ne $expectedSequence) { throw 'Job sequence is not the next expected value.' }
            if (-not $processedIds.Add([string]$job.id)) { throw 'Job ID replay rejected.' }
            $result = $null
            switch ([string]$job.operation) {
                'status' { $result = [ordered]@{ state = 'ready'; expectedSequence = $expectedSequence + 1 } }
                'execute' {
                    if (-not $executedWorkloads.Add([string]$job.workloadId)) { throw 'Workload replay rejected.' }
                    Write-BrokerStatus 'executing' ([string]$job.workloadId)
                    $result = Invoke-AllowlistedWorkload (Get-Workload ([string]$job.workloadId))
                    Write-BrokerStatus 'ready'
                }
                'finish' { Stop-ExactFixture; $result = [ordered]@{ fixtureState = 'Off' }; $finished = $true }
            }
            $resultPath = Join-Path $results ('{0:D9}-{1}.result.json' -f $sequence, $job.id)
            Write-AtomicJson $resultPath ([ordered]@{ schema=1; id=$job.id; sequence=$sequence; operation=$job.operation; success=$true; result=$result; completedUtc=[DateTime]::UtcNow.ToString('o') })
            Write-Journal 'job-completed' @{ id=$job.id; sequence=$sequence; operation=$job.operation }
            $expectedSequence++
            $lastJobUtc = [DateTime]::UtcNow
        }
        catch {
            $message = $_.Exception.Message
            $failurePath = Join-Path $results ('failure-{0:D9}.json' -f $expectedSequence)
            Write-AtomicJson $failurePath ([ordered]@{ schema=1; success=$false; error=$message; completedUtc=[DateTime]::UtcNow.ToString('o') })
            Write-Journal 'job-failed' @{ sequence=$expectedSequence; error=$message }
            throw
        }
        finally { if ($snapshot -and (Test-Path -LiteralPath $snapshot)) { Remove-Item -LiteralPath $snapshot -Force } }
    }
    Write-BrokerStatus 'completed' 'fixture Off'
}
catch {
    $failure = $_.Exception.Message
    try { Stop-ExactFixture } catch { $failure += '; finalization: ' + $_.Exception.Message }
    Write-BrokerStatus 'failed' $failure
    Write-Journal 'broker-failed' @{ error=$failure }
    throw
}
finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
