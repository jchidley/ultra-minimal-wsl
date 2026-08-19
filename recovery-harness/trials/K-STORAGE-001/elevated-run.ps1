#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = 'C:\Users\jackc\git\ultra-minimal-wsl'
$trialExit = 1
$safeExit = 1

try {
    & "$project\tools\Invoke-WslDiagnosticKernelTrial.ps1" `
        -TrialId K-STORAGE-001 `
        -CandidateKernel "$project\candidates\K-STORAGE-001\linux-kernel" `
        -TestDistribution Toybox-Minimal `
        -RecoveryDistribution Debian `
        -SourceCommit 14794180686c2fb6307fbe359c359bec765249f3 `
        -Toolchain 'x86_64-linux-musl-gcc 15.1.0; GNU binutils 2.44' `
        -KernelConfigPath "$project\candidates\K-STORAGE-001\linux-fullconfig" `
        -AllowCustomKernel `
        -Execute
    $trialExit = $LASTEXITCODE
}
catch {
    Write-Output ("TRIAL_EXCEPTION: " + $_.Exception.ToString())
    $trialExit = 1
}
finally {
    try {
        & "$project\tools\Test-WslSafeState.ps1"
        $safeExit = $LASTEXITCODE
    }
    catch {
        Write-Output ("SAFE_STATE_EXCEPTION: " + $_.Exception.ToString())
        $safeExit = 1
    }
}

[pscustomobject]@{
    trialExit = $trialExit
    safeStateExit = $safeExit
} | ConvertTo-Json -Compress

if (($trialExit -ne 0) -or ($safeExit -ne 0)) { exit 1 }
exit 0
