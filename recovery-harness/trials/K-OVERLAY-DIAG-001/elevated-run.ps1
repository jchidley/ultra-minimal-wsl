#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = 'C:\Users\jackc\git\ultra-minimal-wsl'
$trialSucceeded = $false
$safe = $false

try {
    & "$project\tools\Invoke-WslDiagnosticKernelTrial.ps1" `
        -TrialId K-OVERLAY-DIAG-001 `
        -CandidateKernel "$project\candidates\K-OVERLAY-001\linux-kernel" `
        -TestDistribution Toybox-Minimal `
        -RecoveryDistribution Debian `
        -TimeoutSeconds 45 `
        -SourceCommit 14794180686c2fb6307fbe359c359bec765249f3 `
        -Toolchain 'x86_64-linux-musl-gcc (GCC) 15.1.0; GNU ld (GNU Binutils) 2.44' `
        -KernelConfigPath "$project\candidates\K-OVERLAY-001\linux-fullconfig" `
        -AllowCustomKernel `
        -Execute
    $trialSucceeded = $true
}
catch {
    Write-Output ("TRIAL_EXCEPTION: " + $_.Exception.ToString())
}
finally {
    try {
        $safeState = & "$project\tools\Test-WslSafeState.ps1" | Out-String | ConvertFrom-Json
        $safe = [bool]$safeState.safe
        Write-Output ($safeState | ConvertTo-Json -Depth 8 -Compress)
    }
    catch {
        Write-Output ("SAFE_STATE_EXCEPTION: " + $_.Exception.ToString())
    }
}

[pscustomobject]@{
    trialSucceeded = $trialSucceeded
    safe = $safe
} | ConvertTo-Json -Compress

if (-not $safe) { exit 2 }
if (-not $trialSucceeded) { exit 1 }
exit 0
