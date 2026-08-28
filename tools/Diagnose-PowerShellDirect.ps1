#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$plan = [ordered]@{
    schema = 1
    action = 'retired-powershell-direct-diagnostic'
    executable = $false
    approvalCarriedForward = $false
    vmName = 'ultra-minimal-wsl-dev'
    status = 'blocked-disposable-credential-unavailable'
    reason = 'The original random guest credential is unavailable, and prompting or manual VMConnect login is not acceptable for disposable testing.'
    replacementBoundary = 'Plan a zero-touch disposable-VM rebuild that generates and machine-consumes its guest credential; if automated guest control later fails, discard/rebuild rather than request human guest credentials or repair through VMConnect.'
    prohibited = @(
        'guest credential prompt',
        'manual VMConnect login',
        'password discovery or recovery',
        'VM query or operation from this retired artifact',
        'host WSL operation'
    )
}

if ($Execute) {
    throw 'This diagnostic artifact is retired and non-executable. Do not prompt for guest credentials or operate the VM.'
}

[pscustomobject]$plan | ConvertTo-Json -Depth 5
