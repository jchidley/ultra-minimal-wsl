#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $VmName = 'ultra-minimal-wsl-dev',
    [string] $VmId = 'dcbf722c-0702-444e-9496-04a4623c3198',
    [string] $Checkpoint = 'clean-shell',
    [string] $CredentialPath = '%LOCALAPPDATA%\ultra-minimal-wsl\credentials\ultra-minimal-wsl-dev.credential.clixml',
    [string[]] $AllowedControllerRoots = @('%LOCALAPPDATA%\ultra-minimal-wsl\approval-state'),
    [switch] $Confirmed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Confirmed) { throw 'Broker installation changes Program Files and requires -Confirmed.' }
$sourceRoot = Split-Path -Parent $PSCommandPath
$required = @('FixtureBroker.ps1','FixtureBroker.Policy.psm1','New-FixtureBrokerRun.ps1')
foreach ($name in $required) { if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $name) -PathType Leaf)) { throw "Missing broker payload: $name" } }
$user = [Security.Principal.WindowsIdentity]::GetCurrent()
$userSid = $user.User.Value
$installation = [ordered]@{
    schema = 1
    installedFor = $user.Name
    userSid = $userSid
    vmName = $VmName
    vmId = $VmId
    checkpoint = $Checkpoint
    credentialPath = [Environment]::ExpandEnvironmentVariables($CredentialPath)
    allowedControllerRoots = @($AllowedControllerRoots | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
}
$tempRoot = Join-Path $env:TEMP ('fixture-broker-install-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $tempRoot 'payload'
$zipPath = Join-Path $tempRoot 'payload.zip'
[IO.Directory]::CreateDirectory($payload) | Out-Null
try {
    foreach ($name in $required) { Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $payload $name) }
    [IO.File]::WriteAllText((Join-Path $payload 'installation.json'), ($installation | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $bundleHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $version = $bundleHash.Substring(0,16)
    $zip64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($zipPath))
    $hash64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bundleHash))
    $version64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($version))
    $sid64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($userSid))
    $bootstrap = @"
`$ErrorActionPreference='Stop'
`$decode={param([string]`$v)[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(`$v))}
`$zip=&`$decode '$zip64';`$expected=&`$decode '$hash64';`$version=&`$decode '$version64';`$sid=&`$decode '$sid64'
`$identity=[Security.Principal.WindowsIdentity]::GetCurrent();`$principal=[Security.Principal.WindowsPrincipal]::new(`$identity)
if(-not `$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Bootstrap is not elevated.'}
`$stream=[IO.File]::Open(`$zip,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{`$hash=[Security.Cryptography.SHA256]::Create();try{`$actual=([Convert]::ToHexString(`$hash.ComputeHash(`$stream))).ToLowerInvariant()}finally{`$hash.Dispose()};if(`$actual-ne`$expected){throw 'Bootstrap bundle hash mismatch.'};`$stream.Position=0;`$bytes=[byte[]]::new(`$stream.Length);`$read=0;while(`$read-lt`$bytes.Length){`$n=`$stream.Read(`$bytes,`$read,`$bytes.Length-`$read);if(`$n-eq 0){throw 'Unexpected bundle EOF.'};`$read+=`$n}}finally{`$stream.Dispose()}
`$base=Join-Path `$env:ProgramFiles 'UltraMinimalWslFixtureBroker';[IO.Directory]::CreateDirectory(`$base)|Out-Null
& "`$env:SystemRoot\System32\icacls.exe" `$base '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' ("*`$(`$sid):(OI)(CI)RX")|Out-Null;if(`$LASTEXITCODE-ne 0){throw 'Failed broker root ACL.'}
`$target=Join-Path `$base `$version;if(Test-Path -LiteralPath `$target){throw 'Broker version already installed.'};[IO.Directory]::CreateDirectory(`$target)|Out-Null
`$protectedZip=Join-Path `$target 'payload.zip';[IO.File]::WriteAllBytes(`$protectedZip,`$bytes)
Add-Type -AssemblyName System.IO.Compression.FileSystem
`$archive=[IO.Compression.ZipFile]::OpenRead(`$protectedZip);try{foreach(`$entry in `$archive.Entries){if([IO.Path]::IsPathRooted(`$entry.FullName)-or `$entry.FullName-match '(^|[\\/])\.\.([\\/]|$)'){throw 'Unsafe archive entry.'}}}finally{`$archive.Dispose()}
[IO.Compression.ZipFile]::ExtractToDirectory(`$protectedZip,`$target,`$false);Remove-Item -LiteralPath `$protectedZip -Force
& "`$env:SystemRoot\System32\icacls.exe" `$target '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' ("*`$(`$sid):(OI)(CI)RX")|Out-Null;if(`$LASTEXITCODE-ne 0){throw 'Failed broker version ACL.'}
[IO.File]::WriteAllText((Join-Path `$base 'current.txt'),`$version,[Text.UTF8Encoding]::new(`$false))
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
    $process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -Verb RunAs -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Elevated broker installation failed with $($process.ExitCode)." }
    $installRoot = Join-Path $env:ProgramFiles ('UltraMinimalWslFixtureBroker\' + $version)
    Import-Module (Join-Path $installRoot 'FixtureBroker.Policy.psm1') -Force
    Assert-ProtectedAcl -Path (Split-Path -Parent $installRoot) -UserSid $userSid | Out-Null
    Assert-ProtectedAcl -Path $installRoot -UserSid $userSid | Out-Null
    foreach ($name in $required) {
        $sourceHash = (Get-FileHash -LiteralPath (Join-Path $payload $name) -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash -LiteralPath (Join-Path $installRoot $name) -Algorithm SHA256).Hash
        if ($sourceHash -ne $installedHash) { throw "Installed broker file mismatch: $name" }
    }
    [pscustomobject]@{ schema=1; installed=$true; version=$version; bundleSha256=$bundleHash; installRoot=$installRoot; vmId=$VmId; userSid=$userSid } | ConvertTo-Json -Compress
}
finally { if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force } }
