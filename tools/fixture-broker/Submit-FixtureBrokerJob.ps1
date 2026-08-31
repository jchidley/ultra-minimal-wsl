#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RunId,
    [Parameter(Mandatory)][ValidateRange(1,999999999)][long] $Sequence,
    [Parameter(Mandatory)][string] $JobId,
    [Parameter(Mandatory)][ValidateSet('status','execute','finish')][string] $Operation,
    [string] $WorkloadId,
    [ValidateRange(1,28800)][int] $WaitSeconds = 7200
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'FixtureBroker.Policy.psm1'
Import-Module $module -Force
Assert-BrokerId $RunId 'runId' | Out-Null
Assert-BrokerId $JobId 'jobId' | Out-Null
if ($Operation -eq 'execute') { Assert-BrokerId $WorkloadId 'workloadId' | Out-Null }
elseif ($WorkloadId) { throw 'WorkloadId is valid only for execute.' }
$runRoot = Join-Path $env:ProgramData ('UltraMinimalWslFixtureBroker\Runs\' + $RunId)
$statusPath = Join-Path $runRoot 'results\broker-status.json'
if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) { throw 'Secure broker run is not available.' }
$status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
if ($status.state -notin @('ready','executing')) { throw "Broker is not accepting jobs: $($status.state)" }
$job = [ordered]@{ schema=1; id=$JobId; sequence=$Sequence; operation=$Operation }
if ($Operation -eq 'execute') { $job.workloadId = $WorkloadId }
$inbox = Join-Path $runRoot 'inbox'
$fileName = '{0:D9}-{1}.job.json' -f $Sequence,$JobId
$final = Join-Path $inbox $fileName
$temporary = Join-Path $inbox ($fileName + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
if (Test-Path -LiteralPath $final) { throw 'Job path already exists.' }
[IO.File]::WriteAllText($temporary, ($job | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $final
$result = Join-Path $runRoot ('results\{0:D9}-{1}.result.json' -f $Sequence,$JobId)
$failure = Join-Path $runRoot ('results\failure-{0:D9}.json' -f $Sequence)
$deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
do {
    if (Test-Path -LiteralPath $result) { Get-Content -LiteralPath $result -Raw; exit 0 }
    if (Test-Path -LiteralPath $failure) { Get-Content -LiteralPath $failure -Raw; exit 1 }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $deadline)
throw 'Broker job wait timed out; durable state must be inspected before retry.'
