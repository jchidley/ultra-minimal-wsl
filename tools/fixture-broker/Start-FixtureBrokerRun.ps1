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
$creator = Join-Path $installRoot 'New-FixtureBrokerRun.ps1'
$arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$creator,'-RunId',$RunId,'-WorkloadId',$WorkloadId,'-WorkloadPath',(Get-CanonicalPath $WorkloadPath),'-WorkloadSha256',$WorkloadSha256,'-TimeoutSeconds',[string]$TimeoutSeconds)
$stdout = Join-Path $env:TEMP ($RunId + '.broker-start.stdout')
$stderr = Join-Path $env:TEMP ($RunId + '.broker-start.stderr')
$process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -Verb RunAs -ArgumentList $arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
$out = if(Test-Path $stdout){Get-Content $stdout -Raw}else{''}
$err = if(Test-Path $stderr){Get-Content $stderr -Raw}else{''}
Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
if ($process.ExitCode -ne 0) { throw "Secure run creation failed with $($process.ExitCode): $err" }
$out
