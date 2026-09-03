#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Validate,
    [switch]$Execute,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TrialId = 'CP-MINIMAL-V8-K-PIDNS-DEBIAN-001'
$InputRoot = 'C:\controlled-inputs\ultra-minimal-wsl'
$EvidenceParent = 'C:\controlled-wsl-trials'
$CandidatePackage = Join-Path $InputRoot 'candidate-packages\minimal-v8-no-binfmt-mount\wsl.msi'
$CandidateManifest = Join-Path $InputRoot 'trial-manifests\minimal-v8-k-pidns-001.json'
$CandidateKernel = Join-Path $InputRoot 'candidate-kernels\K-PIDNS-001\linux-kernel'
$CandidateKernelConfig = Join-Path $InputRoot 'candidate-kernels\K-PIDNS-001\linux-fullconfig'
$WslConfig = Join-Path $env:USERPROFILE '.wslconfig'
$StockPackage = Join-Path $InputRoot 'stock-wsl\wsl.2.7.12.0.x64.msi'
$CandidateProbe = Join-Path $InputRoot 'procedure\Invoke-WslDebianProbe.ps1'
$RecoveryProbe = Join-Path $InputRoot 'procedure\Invoke-WslCandidateProbe.ps1'
$CandidateRootfs = Join-Path $InputRoot 'debian-13.5-amd64-wsl-rootfs.tar.gz'
$RecoveryRootfs = Join-Path $InputRoot 'toybox-minimal-wsl-rootfs.tar.gz'
$WprProfile = Join-Path $InputRoot 'diagnostics\wsl.wprp'
$CandidateProductCode = '{65E3A12F-0AF8-4D54-A19A-29A07D5186E3}'
$StockProductCode = '{020F8AC8-A788-4E39-8E9B-8FECFA843632}'
$UpgradeCode = '{6D5B792B-1EDC-4DE9-8EAD-201B820F8E82}'
$ExpectedVersion = '2.7.12.0'
$CandidatePackageBytes = 174403584
$CandidatePackageSha256 = '8207049ae7a6f8a0e7da14bf4becbed438297e5a8b52c215d0d9011cdc3a5765'
$CandidateManifestSha256 = 'f31ccc299f57b0c7a8c5c96c9d239a90b8ebd6f4c9874bc8377ca528deec98a4'
$CompleteSourceDiffSha256 = '57c0b56e38685b03f4a4c6f32c0019a0665df6abf04187c2c9fa4cd48a5642f1'
$CandidateKernelSha256 = '24c768730ba2b66e0afde5a53cbbc95e92440bb90510552ad9b9bf4ddf73c959'
$CandidateKernelConfigSha256 = 'e7e10f27f0b802142a2ecbb52763ba49523da61f42efc23d61bab0046d9ad563'
$CandidateKernelBytes = 3720192
$StockPackageSha256 = 'a460d4560215f2efe003c136244b78ea3415d773824d7a688ea9ded36dbe9145'
$CandidateProbeSha256 = '8ccaaed1324a05d9eb83f970ca89ab7bd56902c66260cb3efd4ce60057548f50'
$RecoveryProbeSha256 = '424b0d4f26cef5c717a4805b2577feebf6973de4656778d7800474aad1bf4ebb'
$CandidateRootfsSha256 = '5ec7dc68216e75d1d4d4761474e99d8461a98d316537110314b137122a879e0f'
$RecoveryRootfsSha256 = 'a8e81e6d29eac6afa7b9438916df3db00de6f833faf8ab8dfaed482bb9a16fa4'
$WprProfileSha256 = '3f829a9af733d6dce9454a1df2e2aa07096acaaed5b6865ffb5c202d089479f2'

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Hash([string]$Path, [string]$Expected) {
    $actual = Get-Sha256 $Path
    if ($actual -ne $Expected) { throw "SHA-256 mismatch for '$Path': expected $Expected, got $actual." }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Controlled package execution requires fixture-local elevated PowerShell.'
    }
}

function Initialize-MsiApi {
    if (-not ('ControlledMsi.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace ControlledMsi {
    public static class NativeMethods {
        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        public static extern int MsiQueryProductState(string product);
        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        public static extern uint MsiGetProductInfo(string product, string property, StringBuilder value, ref uint length);
    }
}
'@
    }
}

function Get-InstalledProduct([string]$ProductCode) {
    if ($script:TestState) {
        return [pscustomobject]@{ Installed = [bool]$script:TestState[$ProductCode]; Version = if ($script:TestState[$ProductCode]) { $ExpectedVersion } else { $null } }
    }
    Initialize-MsiApi
    $state = [ControlledMsi.NativeMethods]::MsiQueryProductState($ProductCode)
    if ($state -ne 5) { return [pscustomobject]@{ Installed = $false; Version = $null; State = $state } }
    $length = [uint32]64
    $value = [Text.StringBuilder]::new([int]$length)
    $result = [ControlledMsi.NativeMethods]::MsiGetProductInfo($ProductCode, 'VersionString', $value, [ref]$length)
    if ($result -ne 0) { throw "MsiGetProductInfo failed for $ProductCode with error $result." }
    [pscustomobject]@{ Installed = $true; Version = $value.ToString(); State = $state }
}

function Assert-ProductState([string]$ProductCode, [bool]$Installed, [string]$Version = '') {
    $product = Get-InstalledProduct $ProductCode
    if ($product.Installed -ne $Installed) { throw "Unexpected installed state for product $ProductCode." }
    if ($Installed -and $Version -and $product.Version -ne $Version) {
        throw "Unexpected version for product ${ProductCode}: expected $Version, got $($product.Version)."
    }
}

function Invoke-Fault([string]$Point) {
    if ($script:FailAt -eq $Point) {
        $script:FailAt = $null
        throw "Injected runner validation failure at $Point."
    }
}

function Invoke-Msi([string]$Action, [string]$Target, [string]$LogPath) {
    Invoke-Fault "msi-$Action"
    if ($script:TestState) {
        if ($Action -eq 'remove-stock') { $script:TestState[$StockProductCode] = $false }
        elseif ($Action -eq 'install-candidate') { $script:TestState[$CandidateProductCode] = $true }
        elseif ($Action -eq 'remove-candidate') { $script:TestState[$CandidateProductCode] = $false }
        elseif ($Action -eq 'restore-stock') {
            $script:TestState[$CandidateProductCode] = $false
            $script:TestState[$StockProductCode] = $true
        }
        $script:Actions.Add($Action) | Out-Null
        Invoke-Fault "msi-$Action-after"
        return
    }
    $verb = if ($Action -in @('remove-stock', 'remove-candidate')) { '/x' } else { '/i' }
    $process = Start-Process -FilePath 'C:\Windows\System32\msiexec.exe' -ArgumentList @($verb, $Target, '/qn', '/norestart', '/L*v', $LogPath) -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) { throw "MSI action '$Action' failed with exit $($process.ExitCode)." }
}

function Test-CandidateKernelConfig {
    if ($script:TestState) { return [bool]$script:TestState.WslConfig }
    Test-Path -LiteralPath $WslConfig
}

function Set-CandidateKernelConfig {
    Invoke-Fault 'kernel-config-write'
    if ($script:TestState) {
        $script:TestState.WslConfig = $true
        $script:TestState.WslDebugConsole = $true
        $script:Actions.Add('kernel-config-write') | Out-Null
        Invoke-Fault 'kernel-config-write-after'
        return
    }
    if (Test-CandidateKernelConfig) { throw 'Fixture .wslconfig must be absent before candidate kernel selection.' }
    $text = "[wsl2]`r`nkernel=$($CandidateKernel.Replace('\', '/'))`r`ndebugConsole=true`r`n"
    [IO.File]::WriteAllText($WslConfig, $text, [Text.UTF8Encoding]::new($false))
    Invoke-Fault 'kernel-config-write-after'
}

function Clear-CandidateKernelConfig {
    Invoke-Fault 'kernel-config-clear'
    if ($script:TestState) {
        $script:TestState.WslConfig = $false
        $script:TestState.WslDebugConsole = $false
        $script:Actions.Add('kernel-config-clear') | Out-Null
        Invoke-Fault 'kernel-config-clear-after'
        return
    }
    if (Test-Path -LiteralPath $WslConfig) { Remove-Item -LiteralPath $WslConfig -Force }
    Invoke-Fault 'kernel-config-clear-after'
}

function Clear-DiagnosticRelays {
    Invoke-Fault 'diagnostic-relay-cleanup'
    if ($script:TestState) {
        $script:TestState.WslDebugConsole = $false
        $script:Actions.Add('diagnostic-relay-cleanup') | Out-Null
        Invoke-Fault 'diagnostic-relay-cleanup-after'
        return
    }
    @(Get-Process -Name 'wslrelay' -ErrorAction SilentlyContinue) |
        Stop-Process -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 250
    if (Get-Process -Name 'wslrelay' -ErrorAction SilentlyContinue) {
        throw 'Diagnostic wslrelay process remained after cleanup.'
    }
    Invoke-Fault 'diagnostic-relay-cleanup-after'
}

function Invoke-WslShutdown {
    Invoke-Fault 'pre-install-shutdown'
    if ($script:TestState) { $script:Actions.Add('shutdown') | Out-Null; return }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $env:SystemRoot 'System32\wsl.exe'
    $info.Arguments = '--shutdown'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Failed to start pre-install WSL shutdown.' }
    if (-not $process.WaitForExit(30000)) {
        $killer = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\taskkill.exe') -ArgumentList @('/PID', [string]$process.Id, '/T', '/F') -Wait -PassThru -WindowStyle Hidden
        $null = $process.WaitForExit(10000)
        throw "Pre-install WSL shutdown timed out; taskkill exit $($killer.ExitCode), process stopped $($process.HasExited)."
    }
    if ($process.ExitCode -ne 0) { throw "WSL shutdown failed with exit $($process.ExitCode)." }
}

function Invoke-FixedProbe([bool]$Recovery) {
    $id = if ($Recovery) { "$TrialId-RECOVERY" } else { $TrialId }
    $candidateId = if ($Recovery) { 'stock-wsl-2.7.12-recovery' } else { 'minimal-v8-k-pidns-001' }
    $manifest = if ($Recovery) { Join-Path $InputRoot 'trial-manifests\stock-wsl-2.7.12-calibration.json' } else { $CandidateManifest }
    $manifestHash = if ($Recovery) { 'a7e6b7899d97797e6e5d9b4f5e7de22f6e8aef4c338405530f93004fc30075d7' } else { $CandidateManifestSha256 }
    $package = if ($Recovery) { $StockPackage } else { $CandidatePackage }
    $packageHash = if ($Recovery) { $StockPackageSha256 } else { $CandidatePackageSha256 }
    $probe = if ($Recovery) { $RecoveryProbe } else { $CandidateProbe }
    $probeHash = if ($Recovery) { $RecoveryProbeSha256 } else { $CandidateProbeSha256 }
    $distribution = if ($Recovery) { 'Toybox-Minimal' } else { 'Debian-Minimal' }
    $rootfs = if ($Recovery) { $RecoveryRootfs } else { $CandidateRootfs }
    $rootfsHash = if ($Recovery) { $RecoveryRootfsSha256 } else { $CandidateRootfsSha256 }
    Invoke-Fault $(if ($Recovery) { 'recovery-probe' } else { 'candidate-probe' })
    if ($script:TestState) { $script:Actions.Add($(if ($Recovery) { 'recovery-probe' } else { 'candidate-probe' })) | Out-Null; return }
    & $probe -TrialId $id -CandidateId $candidateId -CandidateManifestPath $manifest `
        -ExpectedCandidateManifestSha256 $manifestHash -PackagePath $package `
        -ExpectedPackageSha256 $packageHash -ExpectedProbeSha256 $probeHash `
        -Distribution $distribution -ExpectedWslVersion $ExpectedVersion -RootfsPath $rootfs `
        -ExpectedRootfsSha256 $rootfsHash -WprProfilePath $WprProfile `
        -ExpectedWprProfileSha256 $WprProfileSha256 -EvidenceParent $EvidenceParent `
        -TimeoutSeconds 45 -Execute
}

function Assert-FixedInputs {
    Assert-Hash $CandidatePackage $CandidatePackageSha256
    if ((Get-Item -LiteralPath $CandidatePackage).Length -ne $CandidatePackageBytes) { throw 'Candidate package size mismatch.' }
    Assert-Hash $CandidateManifest $CandidateManifestSha256
    Assert-Hash $CandidateKernel $CandidateKernelSha256
    if ((Get-Item -LiteralPath $CandidateKernel).Length -ne $CandidateKernelBytes) { throw 'Candidate kernel size mismatch.' }
    Assert-Hash $CandidateKernelConfig $CandidateKernelConfigSha256
    Assert-Hash $StockPackage $StockPackageSha256
    Assert-Hash $CandidateProbe $CandidateProbeSha256
    Assert-Hash $RecoveryProbe $RecoveryProbeSha256
    Assert-Hash $CandidateRootfs $CandidateRootfsSha256
    if ((Get-Item -LiteralPath $CandidateRootfs).Length -ne 89228801) { throw 'Debian rootfs size mismatch.' }
    Assert-Hash $RecoveryRootfs $RecoveryRootfsSha256
    Assert-Hash $WprProfile $WprProfileSha256
    $stockManifest = Join-Path $InputRoot 'trial-manifests\stock-wsl-2.7.12-calibration.json'
    Assert-Hash $stockManifest 'a7e6b7899d97797e6e5d9b4f5e7de22f6e8aef4c338405530f93004fc30075d7'
    $manifest = Get-Content -LiteralPath $CandidateManifest -Raw | ConvertFrom-Json
    if ($manifest.candidate_id -ne 'minimal-v8-k-pidns-001' -or
        $manifest.wsl_version -ne $ExpectedVersion -or
        $manifest.control_plane_parent -ne 'minimal-v8-no-binfmt-mount' -or
        $manifest.control_plane_complete_source_diff_sha256 -ne $CompleteSourceDiffSha256 -or
        $manifest.package_path -ne $CandidatePackage -or
        $manifest.package_bytes -ne $CandidatePackageBytes -or
        $manifest.package_sha256 -ne $CandidatePackageSha256 -or
        $manifest.package_product_code -ne $CandidateProductCode -or
        $manifest.package_upgrade_code -ne $UpgradeCode -or
        $manifest.kernel_candidate -ne 'K-PIDNS-001' -or
        $manifest.kernel_config_parent -ne 'k-storage-001' -or
        $manifest.kernel_config_path -ne $CandidateKernelConfig -or
        $manifest.kernel_config_sha256 -ne $CandidateKernelConfigSha256 -or
        $manifest.kernel_path -ne $CandidateKernel -or
        $manifest.kernel_bytes -ne $CandidateKernelBytes -or
        $manifest.kernel_sha256 -ne $CandidateKernelSha256 -or
        @($manifest.explicit_symbols).Count -ne 1 -or $manifest.explicit_symbols[0] -ne 'CONFIG_PID_NS' -or
        @($manifest.autoselected_symbols).Count -ne 0 -or
        $manifest.recovery_package_sha256 -ne $StockPackageSha256 -or
        $manifest.recovery_product_code -ne $StockProductCode) { throw 'Candidate manifest content does not match the fixed runner contract.' }
    if ((Get-AuthenticodeSignature -LiteralPath $CandidatePackage).Status -ne 'NotSigned') { throw 'Candidate MSI signature state is not NotSigned as recorded.' }
    if ((Get-AuthenticodeSignature -LiteralPath $StockPackage).Status -ne 'Valid') { throw 'Pinned stock MSI signature is not valid.' }
    if (Test-Path -LiteralPath $WslConfig) { throw 'Fixture .wslconfig must remain absent.' }
    if (Get-Process -Name 'wslrelay' -ErrorAction SilentlyContinue) { throw 'Fixture must not have a pre-existing diagnostic relay.' }
}

function Invoke-Recovery([System.Collections.Generic.List[string]]$Failures) {
    try { Invoke-WslShutdown } catch { $Failures.Add("shutdown: $($_.Exception.Message)") | Out-Null }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try { Clear-CandidateKernelConfig; break }
        catch { $Failures.Add("kernel config removal attempt ${attempt}: $($_.Exception.Message)") | Out-Null }
    }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try { Clear-DiagnosticRelays; break }
        catch { $Failures.Add("diagnostic relay cleanup attempt ${attempt}: $($_.Exception.Message)") | Out-Null }
    }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            $candidate = Get-InstalledProduct $CandidateProductCode
            if ($candidate.Installed) { Invoke-Msi 'remove-candidate' $CandidateProductCode (Join-Path $EvidenceParent "$TrialId-candidate-remove.log") }
            break
        }
        catch { $Failures.Add("candidate removal attempt ${attempt}: $($_.Exception.Message)") | Out-Null }
    }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            Invoke-Msi 'restore-stock' $StockPackage (Join-Path $EvidenceParent "$TrialId-stock-restore.log")
            Assert-ProductState $CandidateProductCode $false
            Assert-ProductState $StockProductCode $true $ExpectedVersion
            break
        }
        catch { $Failures.Add("stock restoration attempt ${attempt}: $($_.Exception.Message)") | Out-Null }
    }
    try {
        Assert-ProductState $CandidateProductCode $false
        Assert-ProductState $StockProductCode $true $ExpectedVersion
        if (Test-CandidateKernelConfig) { throw 'Candidate kernel selection remained configured before stock recovery.' }
        Invoke-FixedProbe $true
    }
    catch { $Failures.Add("stock recovery proof: $($_.Exception.Message)") | Out-Null }
}

function Invoke-Transaction {
    $primary = $null
    $recoveryFailures = [Collections.Generic.List[string]]::new()
    $mutationStarted = $false
    Assert-ProductState $StockProductCode $true $ExpectedVersion
    Assert-ProductState $CandidateProductCode $false
    Invoke-WslShutdown
    try {
        $mutationStarted = $true
        Invoke-Msi 'remove-stock' $StockProductCode (Join-Path $EvidenceParent "$TrialId-stock-remove.log")
        Assert-ProductState $StockProductCode $false
        Invoke-Fault 'after-stock-removal'
        Invoke-Msi 'install-candidate' $CandidatePackage (Join-Path $EvidenceParent "$TrialId-candidate-install.log")
        Assert-ProductState $CandidateProductCode $true $ExpectedVersion
        Assert-ProductState $StockProductCode $false
        Invoke-Fault 'after-candidate-install'
        Set-CandidateKernelConfig
        Invoke-FixedProbe $false
    }
    catch { $primary = $_ }
    finally {
        if ($mutationStarted) { Invoke-Recovery $recoveryFailures }
    }
    if ($recoveryFailures.Count -gt 0) { throw "Recovery did not complete cleanly: $($recoveryFailures -join ' | ')" }
    if ($primary) { throw $primary }
}

function Invoke-RunnerSelfTest {
    $points = @(
        'pre-install-shutdown', 'msi-remove-stock', 'msi-remove-stock-after', 'after-stock-removal',
        'msi-install-candidate', 'msi-install-candidate-after', 'after-candidate-install',
        'kernel-config-write', 'kernel-config-write-after', 'candidate-probe',
        'kernel-config-clear', 'kernel-config-clear-after', 'diagnostic-relay-cleanup', 'diagnostic-relay-cleanup-after',
        'msi-remove-candidate', 'msi-remove-candidate-after', 'msi-restore-stock', 'msi-restore-stock-after', 'recovery-probe'
    )
    $results = @()
    foreach ($point in $points) {
        $script:TestState = @{ $StockProductCode = $true; $CandidateProductCode = $false; WslConfig = $false; WslDebugConsole = $false }
        $script:Actions = [Collections.Generic.List[string]]::new()
        $script:FailAt = $point
        $failed = $false
        try { Invoke-Transaction } catch { $failed = $true }
        if (-not $failed) { throw "Self-test point '$point' did not fail." }
        if (-not $script:TestState[$StockProductCode] -or $script:TestState[$CandidateProductCode] -or $script:TestState.WslConfig -or $script:TestState.WslDebugConsole) { throw "Self-test point '$point' did not restore stock state, kernel selection, and diagnostic console." }
        if ($point -notin @('pre-install-shutdown', 'recovery-probe') -and -not $script:Actions.Contains('recovery-probe')) { throw "Self-test point '$point' did not run independent recovery proof. Actions: $($script:Actions -join ', ')." }
        $results += [ordered]@{ point = $point; stockInstalled = $true; candidateInstalled = $false; recoveryProbe = $script:Actions.Contains('recovery-probe') }
    }
    $script:TestState = $null
    [pscustomobject][ordered]@{ schema = 1; selfTest = $true; passed = $true; failurePaths = $results } | ConvertTo-Json -Depth 6 -Compress
}

if (@(@($Validate, $Execute, $SelfTest) | Where-Object { $_ }).Count -ne 1) { throw 'Specify exactly one of -Validate, -Execute, or -SelfTest.' }
$script:TestState = $null
$script:FailAt = $null
$script:Actions = $null
if ($SelfTest) { Invoke-RunnerSelfTest; exit 0 }

Assert-FixedInputs
Assert-ProductState $StockProductCode $true $ExpectedVersion
Assert-ProductState $CandidateProductCode $false
$plan = [ordered]@{
    schema = 1; trialId = $TrialId; execute = [bool]$Execute; validated = $true
    candidatePackageSha256 = $CandidatePackageSha256; candidateManifestSha256 = $CandidateManifestSha256
    candidateKernelSha256 = $CandidateKernelSha256; candidateKernelConfigSha256 = $CandidateKernelConfigSha256
    stockPackageSha256 = $StockPackageSha256; stockProductCode = $StockProductCode; candidateProductCode = $CandidateProductCode
    processTimeoutSeconds = 45; shutdownTimeoutSeconds = 30; recoveryBaseline = 'CP-STOCK-2.7.12-003'
    candidateGate = 'B6-D'; candidateDistribution = 'Debian-Minimal'; candidateSmoke = '/bin/true plus the plan-defined Debian smoke contract'
    recoveryGate = 'B6-T'; recoveryDistribution = 'Toybox-Minimal'; diagnosticDebugConsole = $true
    note = 'One serial Debian compatibility interval with the frozen minimal-v8 plus K-PIDNS-001 package and kernel. Only the pinned Debian rootfs and plan-defined B6-D probe replace candidate-probe inputs; exact Toybox stock recovery remains mandatory.'
}
$plan | ConvertTo-Json -Depth 4
if ($Validate) { exit 0 }

Assert-Administrator
if (-not (Test-Path -LiteralPath $EvidenceParent -PathType Container)) { [IO.Directory]::CreateDirectory($EvidenceParent) | Out-Null }
if (Test-Path -LiteralPath (Join-Path $EvidenceParent $TrialId)) { throw "Candidate evidence root already exists for $TrialId." }
if (Test-Path -LiteralPath (Join-Path $EvidenceParent "$TrialId-RECOVERY")) { throw "Recovery evidence root already exists for $TrialId." }
Invoke-Transaction
