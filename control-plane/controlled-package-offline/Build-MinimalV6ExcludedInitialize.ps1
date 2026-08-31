#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Execute)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Candidate = 'minimal-v6-excluded-initialize'
$InputRoot = 'C:\controlled-inputs\ultra-minimal-wsl'
$ProcedureRoot = Join-Path $InputRoot 'procedure\controlled-package-offline'
$PatchRoot = Join-Path $InputRoot 'procedure\patches'
$SourceArchive = Join-Path $InputRoot 'controlled-inputs\wsl-source\WSL-2.7.12-68f601bba8eac1df20a0bbd403c6c87c92369ade.tar.gz'
$NugetRoot = Join-Path $InputRoot 'controlled-inputs\nuget'
$FetchRoot = Join-Path $InputRoot 'controlled-inputs\cmake-fetchcontent'
$SourceRoot = 'C:\controlled-package\source\minimal-v6-excluded-initialize'
$BuildRoot = 'C:\controlled-package\build\minimal-v6-excluded-initialize'
$DepsRoot = 'C:\controlled-package\deps'
$GslRoot = Join-Path $DepsRoot 'GSL-4.0.0'
$JsonRoot = Join-Path $DepsRoot 'nlohmann-json-3.12.0'
$ToolchainRoot = 'C:\controlled-toolchain\VS2022'
$Cmake = Join-Path $ToolchainRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$Git = Join-Path $ToolchainRoot 'Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe'
$Tar = 'C:\Windows\System32\tar.exe'
$ExpectedSourceArchiveSha256 = '2b0d80f6d3b81d3baa03de895195beea60a7859c6d60fca73d71fa85720749c3'
$ExpectedNugetManifestSha256 = 'f4641032e9114251a5468b76bb466aa2ce2657546bb5c943ef654a282d4b455b'
$ExpectedGslSha256 = 'f0e32cb10654fea91ad56bde89170d78cfbf4363ee0b01d8f097de2ba49f6ce9'
$ExpectedJsonSha256 = '42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa'
$ExpectedOverlaySha256 = 'eb0b3cb4a6915a5c7221ca18a052afd5bfdd2d44dbaad40101f54bf9ccb92989'
$ExpectedCompleteDiffSha256 = '6dc4920fcf3632161137036c126550ee843b1019d268e291ad586211ceaae2c0'
$Patches = [ordered]@{
    '0001-minimal-control-plane-v1.patch' = '3d54b4769fdb8c784f05387a9823af34fc0ee43f4a3533700d6eef2412f5381a'
    '0002-minimal-v2-fail-closed.patch' = '47d57f86685e3adf00cf73866c1e27779b5195357c14eeda5fa441ce0e1934a0'
    '0004-minimal-v3-no-interop.patch' = 'e68611ecc12ac556b8a8ffd84e7af9045ef552bf58cb6ddac2fe78a44825b981'
    '0006-minimal-v4-zero-initial-config.patch' = '5efe32be0185c6d080458e4a768959d7e5bd5ebdb2138626f60c0555fc7555e5'
    '0007-minimal-v5-mount-pid-ns.patch' = '1658ae9c7a8c90d502f12963a593f6c93fbaaeb87b8c59290221db8df0fea02a'
    '0008-minimal-v6-excluded-initialize.patch' = '5b2f5dcc3c0ca2e8e24c19b6a6a1bee05c1140cf8e3561f7d0fb23edd63eeda0'
}
$ExpectedOutputs = @(
    'bin/x64/Release/wsl.msi',
    'bin/x64/Release/wsl.exe',
    'bin/x64/Release/wslg.exe',
    'bin/x64/Release/wslhost.exe',
    'bin/x64/Release/wslrelay.exe',
    'bin/x64/Release/wslservice.exe',
    'bin/x64/Release/wslserviceproxystub.dll',
    'bin/x64/Release/wslinstall.dll',
    'bin/x64/Release/wsldeps.dll',
    'bin/x64/Release/WSLDVCPlugin.dll',
    'bin/x64/Release/gluepackage.msix',
    'bin/x64/Release/init',
    'bin/x64/Release/initrd.img'
)

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-Hash([string]$Path, [string]$Expected) {
    $actual = Get-Sha256 $Path
    if ($actual -ne $Expected) { throw "SHA-256 mismatch for ${Path}: $actual" }
}
function Invoke-Native([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File exited with code $LASTEXITCODE." }
}
function Write-JsonAtomic([object]$Value, [string]$Path) {
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$plan = [ordered]@{
    schema = 1
    action = 'controlled-package-build'
    candidate = $Candidate
    execute = [bool]$Execute
    executable = $false
    sourceRoot = $SourceRoot
    buildRoot = $BuildRoot
    toolchainRoot = $ToolchainRoot
    expectedCompleteSourceDiffSha256 = $ExpectedCompleteDiffSha256
    expectedOutputs = $ExpectedOutputs
    authorizationBoundary = 'Standing-authorized only inside the dedicated disposable fixture with pinned offline inputs; no physical-host or shared-WSL effects.'
}
$plan | ConvertTo-Json -Depth 8
if (-not $Execute) { exit 0 }

foreach ($path in @($SourceRoot, $BuildRoot, $DepsRoot)) {
    if (Test-Path -LiteralPath $path) { throw "Refusing to reuse existing directory: $path" }
}
foreach ($tool in @($Cmake, $Git, $Tar)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Required tool is missing: $tool" }
}
Assert-Hash $SourceArchive $ExpectedSourceArchiveSha256
$nugetManifest = Join-Path $NugetRoot 'CONTROLLED-SHA256SUMS'
Assert-Hash $nugetManifest $ExpectedNugetManifestSha256
foreach ($line in Get-Content -LiteralPath $nugetManifest) {
    if (-not $line) { continue }
    $parts = $line -split '  ', 2
    if ($parts.Count -ne 2) { throw 'Malformed controlled NuGet manifest.' }
    Assert-Hash (Join-Path $NugetRoot $parts[1]) $parts[0]
}
$gslArchive = Join-Path $FetchRoot 'GSL-4.0.0.tar.gz'
$jsonArchive = Join-Path $FetchRoot 'nlohmann-json-3.12.0.tar.xz'
Assert-Hash $gslArchive $ExpectedGslSha256
Assert-Hash $jsonArchive $ExpectedJsonSha256
Assert-Hash (Join-Path $ProcedureRoot 'FindNUGET.cmake') $ExpectedOverlaySha256
foreach ($patch in $Patches.GetEnumerator()) { Assert-Hash (Join-Path $PatchRoot $patch.Key) $patch.Value }

[IO.Directory]::CreateDirectory($SourceRoot) | Out-Null
[IO.Directory]::CreateDirectory($BuildRoot) | Out-Null
[IO.Directory]::CreateDirectory($GslRoot) | Out-Null
[IO.Directory]::CreateDirectory($JsonRoot) | Out-Null
Invoke-Native $Tar @('-xzf', $SourceArchive, '-C', $SourceRoot, '--strip-components=1')
Invoke-Native $Tar @('-xzf', $gslArchive, '-C', $GslRoot, '--strip-components=1')
Invoke-Native $Tar @('-xJf', $jsonArchive, '-C', $JsonRoot, '--strip-components=1')
Invoke-Native $Git @('-C', $SourceRoot, 'init', '--quiet')
Invoke-Native $Git @('-C', $SourceRoot, 'config', 'core.autocrlf', 'false')
Invoke-Native $Git @('-C', $SourceRoot, 'add', '-A')
foreach ($patch in $Patches.Keys) { Invoke-Native $Git @('-C', $SourceRoot, 'apply', '--unsafe-paths', (Join-Path $PatchRoot $patch)) }
Invoke-Native $Git @('-C', $SourceRoot, 'add', '--intent-to-add', '-A')
$diffPath = Join-Path $BuildRoot 'controlled-source.diff'
$diffOutput = & $Git -C $SourceRoot diff --binary --no-ext-diff
if ($LASTEXITCODE -ne 0) { throw 'Failed to generate the complete source diff.' }
[IO.File]::WriteAllText($diffPath, (($diffOutput -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
Assert-Hash $diffPath $ExpectedCompleteDiffSha256

$cmakeNugetRoot = $NugetRoot.Replace('\', '/')
$cmakeProcedureRoot = $ProcedureRoot.Replace('\', '/')
$cmakeSourceRoot = $SourceRoot.Replace('\', '/')
$cmakeGslRoot = $GslRoot.Replace('\', '/')
$cmakeJsonRoot = $JsonRoot.Replace('\', '/')
$configure = @(
    '-S', $SourceRoot, '-B', $BuildRoot,
    '-G', 'Visual Studio 17 2022', '-A', 'x64',
    '-DCMAKE_SYSTEM_VERSION=10.0.26100.0', '-DCMAKE_BUILD_TYPE=Release',
    '-DPACKAGE_VERSION=2.7.12.0', '-DWSL_NUGET_PACKAGE_VERSION=2.7.12',
    '-DWSL_BUILD_WSL_SETTINGS=FALSE', '-DOFFICIAL_BUILD=FALSE', '-DSKIP_PACKAGE_SIGNING=TRUE',
    "-DCONTROLLED_NUGET_CACHE=$cmakeNugetRoot",
    "-DCMAKE_MODULE_PATH=$cmakeProcedureRoot;$cmakeSourceRoot/cmake",
    '-DFETCHCONTENT_FULLY_DISCONNECTED=ON',
    "-DFETCHCONTENT_SOURCE_DIR_GSL=$cmakeGslRoot",
    "-DFETCHCONTENT_SOURCE_DIR_NLOHMANNJSON=$cmakeJsonRoot"
)
Invoke-Native $Cmake $configure
Invoke-Native $Cmake @('--build', $BuildRoot, '--config', 'Release', '--target', 'msipackage', '--', '/m:2')

$manifestLines = foreach ($relative in ($ExpectedOutputs | Sort-Object)) {
    $path = Join-Path $BuildRoot ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Expected output is missing: $relative" }
    "$(Get-Sha256 $path)  $relative"
}
$manifestPath = Join-Path $BuildRoot 'controlled-output-SHA256SUMS'
[IO.File]::WriteAllLines($manifestPath, [string[]]$manifestLines, [Text.UTF8Encoding]::new($false))
Write-JsonAtomic ([ordered]@{
    schema = 1
    candidate = $Candidate
    completedUtc = [DateTime]::UtcNow.ToString('o')
    completeSourceDiffSha256 = Get-Sha256 $diffPath
    outputManifestSha256 = Get-Sha256 $manifestPath
    packagePath = Join-Path $BuildRoot 'bin\x64\Release\wsl.msi'
    packageSha256 = Get-Sha256 (Join-Path $BuildRoot 'bin\x64\Release\wsl.msi')
    outputs = $ExpectedOutputs.Count
}) (Join-Path $BuildRoot 'controlled-build-result.json')
