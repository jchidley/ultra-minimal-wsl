#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RunId,
    [Parameter(Mandatory)][string] $WorkloadId,
    [Parameter(Mandatory)][string] $WorkloadPath,
    [Parameter(Mandatory)][string] $WorkloadSha256,
    [ValidateRange(60, 28800)][int] $TimeoutSeconds = 7200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run creation must be elevated.' }
$installRoot = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $installRoot 'FixtureBroker.Policy.psm1') -Force
Assert-BrokerId $RunId 'runId' | Out-Null
Assert-BrokerId $WorkloadId 'workloadId' | Out-Null
Assert-Sha256 $WorkloadSha256 | Out-Null
$installation = Get-Content -LiteralPath (Join-Path $installRoot 'installation.json') -Raw | ConvertFrom-Json
if ($installation.schema -ne 1) { throw 'Unsupported broker installation.' }
$userSid = [string]$installation.userSid
Assert-ProtectedAcl -Path $installRoot -UserSid $userSid | Out-Null
$source = Assert-PathUnderRoots -Path $WorkloadPath -Roots @($installation.allowedControllerRoots) -MustExist -Leaf
Assert-NoReparsePoint $source
$sourceStream = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try {
    if ($sourceStream.Length -gt 1048576) { throw 'Host workload exceeds 1 MiB.' }
    $actualHash = Get-StreamSha256 $sourceStream
    if ($actualHash -ne $WorkloadSha256) { throw 'Host workload hash mismatch.' }
    $sourceStream.Position = 0
    $bytes = [byte[]]::new($sourceStream.Length)
    $read = 0
    while ($read -lt $bytes.Length) {
        $count = $sourceStream.Read($bytes, $read, $bytes.Length - $read)
        if ($count -eq 0) { throw 'Unexpected end of workload.' }
        $read += $count
    }
}
finally { $sourceStream.Dispose() }
$text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
if ($text -notmatch '(?m)^# FixtureBroker-SecureWorkload: 1\s*$') { throw 'Workload lacks the secure-broker marker.' }
if ($text -notmatch 'ULTRAMINIMALWSL_SECURE_RUN_ROOT' -or $text -notmatch 'ULTRAMINIMALWSL_SECURE_CREDENTIAL') {
    throw 'Workload does not use protected run and credential paths.'
}

$runBase = Join-Path $env:ProgramData 'UltraMinimalWslFixtureBroker\Runs'
$runRoot = Join-Path $runBase $RunId
if (Test-Path -LiteralPath $runRoot) { throw 'Secure run ID already exists.' }
foreach ($path in @($runRoot,(Join-Path $runRoot 'inbox'),(Join-Path $runRoot 'private'),(Join-Path $runRoot 'private\workloads'),(Join-Path $runRoot 'results'))) {
    [IO.Directory]::CreateDirectory($path) | Out-Null
}
function Set-ProtectedAcl([string]$Path, [bool]$UserModify) {
    & "$env:SystemRoot\System32\icacls.exe" $Path '/inheritance:r' '/grant:r' `
        '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' ("*$($userSid):" + $(if($UserModify){'(OI)(CI)M'}else{'(OI)(CI)RX'})) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to protect ACL: $Path" }
}
Set-ProtectedAcl $runRoot $false
Set-ProtectedAcl (Join-Path $runRoot 'inbox') $true
Set-ProtectedAcl (Join-Path $runRoot 'private') $false
Set-ProtectedAcl (Join-Path $runRoot 'results') $false

$protectedWorkload = Join-Path $runRoot ('private\workloads\' + $WorkloadId + '.ps1')
[IO.File]::WriteAllBytes($protectedWorkload, $bytes)
if ((Get-FileHash -LiteralPath $protectedWorkload -Algorithm SHA256).Hash.ToLowerInvariant() -ne $WorkloadSha256) { throw 'Protected workload copy mismatch.' }
$credentialSource = Get-CanonicalPath ([string]$installation.credentialPath)
Assert-NoReparsePoint $credentialSource
$credentialDestination = Join-Path $runRoot 'private\fixture.credential.clixml'
$credentialInput = [IO.File]::Open($credentialSource, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try {
    $credentialOutput = [IO.File]::Open($credentialDestination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $credentialInput.CopyTo($credentialOutput); $credentialOutput.Flush($true) }
    finally { $credentialOutput.Dispose() }
}
finally { $credentialInput.Dispose() }

$config = [ordered]@{
    schema = 1
    runId = $RunId
    userSid = $userSid
    vmName = [string]$installation.vmName
    vmId = [string]$installation.vmId
    checkpoint = [string]$installation.checkpoint
    idleTimeoutSeconds = 1800
    maximumLifetimeSeconds = 28800
    workloads = @([ordered]@{ id=$WorkloadId; file=($WorkloadId + '.ps1'); sha256=$WorkloadSha256; timeoutSeconds=$TimeoutSeconds })
}
[IO.File]::WriteAllText((Join-Path $runRoot 'private\run-config.json'), ($config | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Assert-ProtectedAcl -Path $runRoot -UserSid $userSid | Out-Null
Assert-ProtectedAcl -Path (Join-Path $runRoot 'private') -UserSid $userSid | Out-Null

$broker = Join-Path $installRoot 'FixtureBroker.ps1'
$launchPayload = [ordered]@{ broker=$broker; runRoot=$runRoot } | ConvertTo-Json -Compress
$launchPayload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($launchPayload))
$launchBootstrap = @"
`$ErrorActionPreference='Stop'
try {
    `$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$launchPayload64'))|ConvertFrom-Json
    & ([string]`$p.broker) -RunRoot ([string]`$p.runRoot)
} catch { Write-Error `$_; exit 1 }
"@
$launchEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launchBootstrap))
$brokerStdout = Join-Path $runRoot 'results\broker.stdout.log'
$brokerStderr = Join-Path $runRoot 'results\broker.stderr.log'
$process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$launchEncoded) -RedirectStandardOutput $brokerStdout -RedirectStandardError $brokerStderr -PassThru
$statusPath = Join-Path $runRoot 'results\broker-status.json'
$deadline = [DateTime]::UtcNow.AddSeconds(30)
do {
    Start-Sleep -Milliseconds 250
    if ($process.HasExited) {
        $detail = if (Test-Path -LiteralPath $brokerStderr) { (Get-Content -LiteralPath $brokerStderr -Raw).Trim() } else { '' }
        throw "Broker exited during startup with $($process.ExitCode): $detail"
    }
} while (-not (Test-Path -LiteralPath $statusPath) -and [DateTime]::UtcNow -lt $deadline)
if (-not (Test-Path -LiteralPath $statusPath)) { throw 'Broker did not become ready.' }
$status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
if ($status.state -ne 'ready') { throw 'Broker startup state is not ready.' }
[pscustomobject]@{ schema=1; runId=$RunId; workloadId=$WorkloadId; workloadSha256=$WorkloadSha256; brokerProcessId=$process.Id; runRoot=$runRoot; state=$status.state } | ConvertTo-Json -Compress
