#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RunId,
    [Parameter(Mandatory)][string] $WorkloadId,
    [Parameter(Mandatory)][string] $WorkloadPath,
    [Parameter(Mandatory)][string] $WorkloadSha256,
    [ValidateRange(60,28800)][int] $TimeoutSeconds = 7200,
    [switch] $Confirmed
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Confirmed) { throw 'Starting a secure fixture run requires -Confirmed and one UAC approval.' }
$base = Join-Path $env:ProgramFiles 'UltraMinimalWslFixtureBroker'
$currentPath = Join-Path $base 'current.txt'
if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) { throw 'Fixture broker is not installed.' }
$version = (Get-Content -LiteralPath $currentPath -Raw).Trim()
if ($version -notmatch '^[a-f0-9]{16}$') { throw 'Installed broker version pointer is invalid.' }
$installRoot = Join-Path $base $version
Import-Module (Join-Path $installRoot 'FixtureBroker.Policy.psm1') -Force
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Assert-ProtectedAcl -Path $base -UserSid $userSid | Out-Null
Assert-ProtectedAcl -Path $installRoot -UserSid $userSid | Out-Null
Assert-BrokerId $RunId 'runId' | Out-Null
Assert-BrokerId $WorkloadId 'workloadId' | Out-Null
Assert-Sha256 $WorkloadSha256 | Out-Null
$creator = Get-CanonicalPath (Join-Path $installRoot 'New-FixtureBrokerRun.ps1')
$payload = [ordered]@{
    creator = $creator
    runId = $RunId
    workloadId = $WorkloadId
    workloadPath = Get-CanonicalPath $WorkloadPath
    workloadSha256 = $WorkloadSha256
    timeoutSeconds = $TimeoutSeconds
} | ConvertTo-Json -Compress
$payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$bootstrap = @"
`$ErrorActionPreference='Stop'
try {
    `$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payload64'))|ConvertFrom-Json
    & ([string]`$p.creator) -RunId ([string]`$p.runId) -WorkloadId ([string]`$p.workloadId) -WorkloadPath ([string]`$p.workloadPath) -WorkloadSha256 ([string]`$p.workloadSha256) -TimeoutSeconds ([int]`$p.timeoutSeconds)
} catch { Write-Error `$_; exit 1 }
"@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
$process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -Verb RunAs -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Secure run creation failed with $($process.ExitCode)." }
$runRoot = Join-Path $env:ProgramData ('UltraMinimalWslFixtureBroker\Runs\' + $RunId)
$statusPath = Join-Path $runRoot 'results\broker-status.json'
if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) { throw 'Secure run was not created.' }
$status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
if ($status.state -ne 'ready') { throw "Secure broker did not become ready: $($status.state)" }
[pscustomobject]@{ schema=1; runId=$RunId; workloadId=$WorkloadId; workloadSha256=$WorkloadSha256; brokerProcessId=$status.processId; runRoot=$runRoot; state=$status.state } | ConvertTo-Json -Compress
