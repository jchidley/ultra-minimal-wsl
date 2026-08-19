[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$WslRoot = 'C:\Program Files\WSL'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$harness = Join-Path $PSScriptRoot 'Invoke-WslKernelTrial.ps1'
$safeStateVerifier = Join-Path $PSScriptRoot 'Test-WslSafeState.ps1'
$stateRoot = Join-Path $ProjectRoot 'recovery-harness'
$candidate = Join-Path $ProjectRoot 'candidates\wsl-2.7.11-stock-kernel'
$stock = Join-Path $WslRoot 'tools\kernel'
$config = Join-Path $env:USERPROFILE '.wslconfig'
$ledger = Join-Path $ProjectRoot 'inventory\trials.csv'

function Get-HashOrNull([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $null
}

function Invoke-ExpectedFailure([scriptblock]$Action, [string]$Pattern) {
    try { & $Action; throw "Expected failure matching '$Pattern' did not occur." }
    catch { if ($_.Exception.Message -notmatch $Pattern) { throw } }
}

foreach ($script in @($harness, $safeStateVerifier)) {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) { throw "$([IO.Path]::GetFileName($script)) parse errors: $($parseErrors -join '; ')" }
}
$safeStateSelfTest = (& $safeStateVerifier -SelfTest | ConvertFrom-Json)
if (-not $safeStateSelfTest.safe) { throw 'Safe-state verifier self-test failed.' }

$safeStateFixture = Join-Path ([IO.Path]::GetTempPath()) ('wsl-safe-state-tests-' + [Guid]::NewGuid().ToString('N'))
try {
    $fixtureWslRoot = Join-Path $safeStateFixture 'WSL'
    $fixtureProject = Join-Path $safeStateFixture 'project'
    [IO.Directory]::CreateDirectory((Join-Path $fixtureWslRoot 'tools')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $fixtureProject 'inventory')) | Out-Null
    $fixtureConfig = Join-Path $safeStateFixture '.wslconfig'
    [IO.File]::WriteAllText((Join-Path $fixtureWslRoot 'tools\kernel'), 'kernel')
    [IO.File]::WriteAllText((Join-Path $fixtureWslRoot 'tools\initrd.img'), 'initrd')
    [IO.File]::WriteAllText($fixtureConfig, "[wsl2]`nkernel=C:/custom")
    [IO.File]::WriteAllText((Join-Path $fixtureProject 'inventory\trials.csv'), "trial_id,status,stock_restore_verified`n")
    $fixtureOutput = & $safeStateVerifier -ProjectRoot $fixtureProject -WslRoot $fixtureWslRoot -ConfigPath $fixtureConfig `
        -ExpectedWslVersion 'fixture' -ExpectedConfigSha256 (Get-HashOrNull $fixtureConfig) `
        -ExpectedKernelSha256 (Get-HashOrNull (Join-Path $fixtureWslRoot 'tools\kernel')) `
        -ExpectedInitrdSha256 (Get-HashOrNull (Join-Path $fixtureWslRoot 'tools\initrd.img')) `
        -ExpectedTrialId @() -SkipRuntimeChecks
    $fixtureExit = $LASTEXITCODE
    $fixtureResult = $fixtureOutput | ConvertFrom-Json
    if ($fixtureExit -ne 1 -or $fixtureResult.safe) { throw 'Unsafe safe-state fixture did not emit JSON and exit 1.' }
    $customCheck = @($fixtureResult.checks | Where-Object name -eq 'no-custom-wsl-settings')
    if ($customCheck.Count -ne 1 -or $customCheck[0].pass) { throw 'Safe-state fixture did not identify the custom kernel setting.' }
}
finally { Remove-Item -LiteralPath $safeStateFixture -Recurse -Force -ErrorAction SilentlyContinue }

[IO.Directory]::CreateDirectory((Split-Path -Parent $candidate)) | Out-Null
Copy-Item -LiteralPath $stock -Destination $candidate -Force
$stockBefore = Get-HashOrNull $stock
$configBefore = Get-HashOrNull $config
$ledgerBefore = Get-HashOrNull $ledger
if ((Get-HashOrNull $candidate) -ne $stockBefore) { throw 'External stock-kernel copy hash mismatch.' }

$planOutput = @(& $harness -Mode StockValidation -TrialId SELFTEST-PLAN -CandidateKernel $candidate `
    -TestDistribution 'Toybox-Minimal' -RecoveryDistribution 'Debian' `
    -StateRoot $stateRoot -WslRoot $WslRoot -TrialLedger $ledger)
$planJson = @($planOutput | Where-Object { $_ -is [string] -and $_.TrimStart().StartsWith('{') })
if ($planJson.Count -ne 1) { throw 'Kernel plan did not emit exactly one JSON object.' }
$plan = $planJson[0] | ConvertFrom-Json
if ($plan.requiresElevation -ne $false) { throw 'Ordinary kernel plan incorrectly requires elevation.' }

Invoke-ExpectedFailure {
    & $harness -Mode KernelTrial -TrialId SELFTEST-GUARD -CandidateKernel $candidate `
        -TestDistribution 'Toybox-Minimal' -StateRoot $stateRoot -WslRoot $WslRoot -TrialLedger $ledger
} 'AllowCustomKernel'

Invoke-ExpectedFailure {
    & $harness -Mode StockValidation -TrialId SELFTEST-INSTALLED-PATH -CandidateKernel $stock `
        -TestDistribution 'Toybox-Minimal' -StateRoot $stateRoot -WslRoot $WslRoot -TrialLedger $ledger
} 'outside the installed WSL directory'

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('wsl-kernel-plan-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
try {
    $emptyLedger = Join-Path $temporaryRoot 'trials.csv'
    $lines = [IO.File]::ReadAllLines($ledger)
    if ($lines.Count -eq 0) { throw 'Trial ledger has no header.' }
    [IO.File]::WriteAllText($emptyLedger, $lines[0] + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Invoke-ExpectedFailure {
        & $harness -Mode KernelTrial -TrialId SELFTEST-FIRST-GATE -CandidateKernel $candidate `
            -TestDistribution 'Toybox-Minimal' -AllowCustomKernel -SourceCommit test -Toolchain test `
            -KernelConfigPath (Join-Path $ProjectRoot 'config-wsl-ultramin-stage1') `
            -StateRoot $stateRoot -WslRoot $WslRoot -TrialLedger $emptyLedger
    } 'blocked until StockValidation'
}
finally { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }

if (Test-Path -LiteralPath (Join-Path $stateRoot 'active-kernel-trial.json')) { throw 'Plan tests created an active journal.' }
if ((Get-HashOrNull $stock) -ne $stockBefore) { throw 'Packaged kernel changed during plan tests.' }
if ((Get-HashOrNull $config) -ne $configBefore) { throw '.wslconfig changed during plan tests.' }
if ((Get-HashOrNull $ledger) -ne $ledgerBefore) { throw 'Trial ledger changed during plan tests.' }
Write-Host 'WslKernelTrial plan-only safety tests: PASS'
