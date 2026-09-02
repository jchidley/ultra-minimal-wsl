#Requires -Version 7.0
[CmdletBinding()]
param([switch] $SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$Root = Split-Path $PSScriptRoot -Parent

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string] $File,
        [Parameter(Mandatory)][string[]] $Arguments
    )
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File exited with code $LASTEXITCODE."
    }
}

if ($SelfTest) {
    $rejected = $false
    try {
        Invoke-NativeChecked -File (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile', '-Command', 'exit 7')
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) { throw 'Native nonzero self-test was not rejected.' }
    'Native nonzero self-test passed.'
    exit 0
}

Push-Location $Root
try {
    Invoke-NativeChecked -File 'uv' -Arguments @('run', 'python', '-m', 'compileall', '-q', 'tools')
    Invoke-NativeChecked -File 'uv' -Arguments @('run', 'python', '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_*.py')
    Invoke-NativeChecked -File 'uv' -Arguments @('run', 'python', 'tools/inventory_records.py')
    Invoke-NativeChecked -File 'uv' -Arguments @('run', 'python', 'tools/experiment.py', 'validate')
    foreach ($delta in Get-ChildItem 'control-plane/generation' -Filter '*.json' -File) {
        $null = Invoke-NativeChecked -File 'uv' -Arguments @(
            'run', 'python', 'tools/generate_candidate_scripts.py', '--delta', $delta.FullName
        )
    }
    Invoke-NativeChecked -File 'git' -Arguments @('diff', '--check')
    Invoke-NativeChecked -File 'git' -Arguments @('diff', '--cached', '--check')
}
finally {
    Pop-Location
}
