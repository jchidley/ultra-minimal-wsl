#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$WslRoot = 'C:\Program Files\WSL',
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.wslconfig'),
    [string]$BaselinePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'recovery-harness\expected-safe-state.json'),
    [string]$ExpectedWslVersion = '',
    [string]$ExpectedConfigSha256 = '',
    [string]$ExpectedKernelSha256 = '',
    [string]$ExpectedInitrdSha256 = '',
    [string[]]$ExpectedTrialId = @('G-001', 'K-RECOVERY-001', 'K-MKROOT-001', 'K-HVCORE-001', 'K-HVCORE-DIAG-001'),
    [string[]]$OptionalVisualStudioComponent = @(
        'Microsoft.VisualStudio.Component.Windows11SDK.26100',
        'Microsoft.VisualStudio.Component.VC.ATL',
        'Microsoft.VisualStudio.Component.VC.Llvm.Clang',
        'Microsoft.VisualStudio.ComponentGroup.UWP.VC.v143',
        'Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools'
    ),
    [switch]$AllowRunningDistributions,
    [switch]$SkipRuntimeChecks,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-NativeBytes([byte[]]$Bytes) {
    if ($Bytes.Length -eq 0) { return '' }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe) {
        return [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2).Replace("`0", '')
    }
    $nulCount = @($Bytes | Where-Object { $_ -eq 0 }).Count
    if ($nulCount -gt 0 -and $nulCount -ge [Math]::Floor($Bytes.Length / 4)) {
        return [Text.Encoding]::Unicode.GetString($Bytes).Replace("`0", '')
    }
    [Text.Encoding]::UTF8.GetString($Bytes).Replace("`0", '')
}

function Invoke-NativeText([string]$FilePath, [string[]]$Arguments) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('wsl-safe-state-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $stdout = Join-Path $root 'stdout'; $stderr = Join-Path $root 'stderr'
    try {
        $argumentLine = ($Arguments | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
        }) -join ' '
        $process = Start-Process -FilePath $FilePath -ArgumentList $argumentLine -NoNewWindow -PassThru -Wait `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        [pscustomobject]@{
            exitCode = $process.ExitCode
            stdout = ConvertFrom-NativeBytes ([IO.File]::ReadAllBytes($stdout))
            stderr = ConvertFrom-NativeBytes ([IO.File]::ReadAllBytes($stderr))
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-Sha256OrNull([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not $SelfTest -and ([String]::IsNullOrWhiteSpace($ExpectedWslVersion) -or [String]::IsNullOrWhiteSpace($ExpectedConfigSha256) -or [String]::IsNullOrWhiteSpace($ExpectedKernelSha256) -or [String]::IsNullOrWhiteSpace($ExpectedInitrdSha256))) {
    if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) { throw "Safe-state baseline is missing: $BaselinePath" }
    $baseline = [IO.File]::ReadAllText($BaselinePath) | ConvertFrom-Json
    if ([String]::IsNullOrWhiteSpace($ExpectedWslVersion)) { $ExpectedWslVersion = [string]$baseline.wslVersion }
    if ([String]::IsNullOrWhiteSpace($ExpectedConfigSha256)) { $ExpectedConfigSha256 = [string]$baseline.wslConfigSha256 }
    if ([String]::IsNullOrWhiteSpace($ExpectedKernelSha256)) { $ExpectedKernelSha256 = [string]$baseline.packagedKernelSha256 }
    if ([String]::IsNullOrWhiteSpace($ExpectedInitrdSha256)) { $ExpectedInitrdSha256 = [string]$baseline.packagedInitrdSha256 }
}

$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [bool]$Pass, $Actual, $Expected) {
    $checks.Add([pscustomobject]@{ name = $Name; pass = $Pass; actual = $Actual; expected = $Expected })
}

if ($SelfTest) {
    $sample = [Text.Encoding]::Unicode.GetBytes("Debian`r`n")
    $decoded = ConvertFrom-NativeBytes $sample
    Add-Check 'decode-utf16-native-output' ($decoded -eq "Debian`r`n" -and -not $decoded.Contains("`0")) $decoded "Debian`r`n"
    Add-Check 'hash-missing-is-null' ((Get-Sha256OrNull (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid()))) -eq $null) $null $null
}
else {
    $kernelPath = Join-Path $WslRoot 'tools\kernel'
    $initrdPath = Join-Path $WslRoot 'tools\initrd.img'
    $journalPath = Join-Path $ProjectRoot 'recovery-harness\active-kernel-trial.json'
    $ledgerPath = Join-Path $ProjectRoot 'inventory\trials.csv'

    $configHash = Get-Sha256OrNull $ConfigPath
    $kernelHash = Get-Sha256OrNull $kernelPath
    $initrdHash = Get-Sha256OrNull $initrdPath
    Add-Check 'wslconfig-sha256' ($configHash -eq $ExpectedConfigSha256) $configHash $ExpectedConfigSha256
    Add-Check 'packaged-kernel-sha256' ($kernelHash -eq $ExpectedKernelSha256) $kernelHash $ExpectedKernelSha256
    Add-Check 'packaged-initrd-sha256' ($initrdHash -eq $ExpectedInitrdSha256) $initrdHash $ExpectedInitrdSha256

    $configText = if (Test-Path -LiteralPath $ConfigPath) { [IO.File]::ReadAllText($ConfigPath) } else { '' }
    $customSettings = @([regex]::Matches($configText, '(?im)^\s*(kernel|kernelModules|debugConsole)\s*=') | ForEach-Object { $_.Value.Trim() })
    Add-Check 'no-custom-wsl-settings' ($customSettings.Count -eq 0) $customSettings @()
    Add-Check 'no-active-recovery-journal' (-not (Test-Path -LiteralPath $journalPath)) (Test-Path -LiteralPath $journalPath) $false

    if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
        $rows = @(Import-Csv -LiteralPath $ledgerPath)
        $missing = @($ExpectedTrialId | Where-Object { $id = $_; @($rows | Where-Object trial_id -eq $id).Count -ne 1 })
        $nonterminal = @($rows | Where-Object { $_.trial_id -in $ExpectedTrialId -and $_.status -notin @('PASS', 'FAIL') } | ForEach-Object trial_id)
        $badRestore = @($rows | Where-Object { $_.trial_id -like 'K-*' -and $_.stock_restore_verified -ne 'yes' } | ForEach-Object trial_id)
        Add-Check 'expected-trial-rows' ($missing.Count -eq 0) $missing @()
        Add-Check 'terminal-trial-rows' ($nonterminal.Count -eq 0) $nonterminal @()
        Add-Check 'host-trials-restored' ($badRestore.Count -eq 0) $badRestore @()
    }
    else { Add-Check 'trial-ledger-present' $false $null $ledgerPath }

    if (-not $SkipRuntimeChecks) {
        $management = @(Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match '(?i)\s--(export|import|unregister|manage|set-version|install|uninstall|update)(\s|$)' } |
            Select-Object ProcessId, Name, CommandLine)
        Add-Check 'no-wsl-management-operation' ($management.Count -eq 0) $management @()

        $versionResult = Invoke-NativeText 'wsl.exe' @('--version')
        $versionMatch = [regex]::Match($versionResult.stdout, '(?im)^WSL version:\s*([^\s]+)')
        $actualWslVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { $null }
        Add-Check 'wsl-version-query' ($versionResult.exitCode -eq 0 -and $versionMatch.Success) @{ exitCode=$versionResult.exitCode; stderr=$versionResult.stderr.Trim() } @{ exitCode=0 }
        Add-Check 'wsl-version' ($actualWslVersion -eq $ExpectedWslVersion) $actualWslVersion $ExpectedWslVersion

        $runningResult = Invoke-NativeText 'wsl.exe' @('--list', '--quiet', '--running')
        $running = @($runningResult.stdout -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Add-Check 'wsl-running-query' ($runningResult.exitCode -eq 0) @{ exitCode=$runningResult.exitCode; stderr=$runningResult.stderr.Trim() } @{ exitCode=0 }
        Add-Check 'no-running-distributions' ($AllowRunningDistributions -or $running.Count -eq 0) $running @()

        $runtime = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('vmmemWSL', 'vmwp.exe') } | Select-Object ProcessId, Name)
        Add-Check 'no-wsl-utility-vm' ($AllowRunningDistributions -or $runtime.Count -eq 0) $runtime @()
        $relays = @(Get-Process -Name 'wslrelay' -ErrorAction SilentlyContinue | Select-Object Id, ProcessName)
        Add-Check 'no-stale-debug-relay' ($relays.Count -eq 0) $relays @()

        if (Get-Command wpr.exe -ErrorAction SilentlyContinue) {
            $wpr = Invoke-NativeText 'wpr.exe' @('-status')
            $wprText = ($wpr.stdout + "`n" + $wpr.stderr).Trim()
            $idle = $wprText -match '(?i)(not recording|no profiles are currently recording)'
            Add-Check 'wpr-idle' $idle $wprText 'WPR is not recording'
        }
        else { Add-Check 'wpr-available' $false $null 'wpr.exe' }

        $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
        $installedOptional = [Collections.Generic.List[string]]::new()
        $vswhereErrors = [Collections.Generic.List[object]]::new()
        if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
            foreach ($component in $OptionalVisualStudioComponent) {
                $query = Invoke-NativeText $vswhere @('-products', '*', '-requires', $component, '-property', 'installationPath')
                if ($query.exitCode -ne 0) { $vswhereErrors.Add(@{ component=$component; exitCode=$query.exitCode; stderr=$query.stderr.Trim() }) }
                elseif (-not [String]::IsNullOrWhiteSpace($query.stdout)) { $installedOptional.Add($component) }
            }
        }
        Add-Check 'optional-visual-studio-query' ($vswhereErrors.Count -eq 0) $vswhereErrors @()
        Add-Check 'no-optional-visual-studio-workload' ($installedOptional.Count -eq 0) $installedOptional @()
    }
}

$safe = @($checks | Where-Object { -not $_.pass }).Count -eq 0
$result = [ordered]@{
    schemaVersion = 1
    checkedUtc = (Get-Date).ToUniversalTime().ToString('o')
    safe = $safe
    checks = $checks
}
$result | ConvertTo-Json -Depth 8 -Compress
if (-not $safe) { exit 1 }
