[CmdletBinding()]
param(
    [string]$VmName = 'ultra-minimal-wsl-dev',
    [string]$CheckpointName = 'controlled-package-baseline',
    [string]$StatePath = "$env:LOCALAPPDATA\ultra-minimal-wsl\hyper-v-vm.json",
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$plan = [ordered]@{
    schema = 1
    action = if ($Execute) { 'checkpoint' } else { 'plan-checkpoint' }
    vmName = $VmName
    checkpoint = $CheckpointName
    requiredVmState = 'Off'
    statePath = $StatePath
    requiresElevation = $true
}
if (-not $Execute) {
    [pscustomobject]$plan | ConvertTo-Json
    exit 0
}
if (-not (Test-IsAdministrator)) {
    throw 'Checkpoint creation requires an elevated PowerShell process and an explicit -Execute invocation.'
}

Import-Module Hyper-V -ErrorAction Stop
$vm = Get-VM -Name $VmName -ErrorAction Stop
if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
    throw "VM '$VmName' must be Off; current state is $($vm.State). The script will not stop it automatically."
}
if (Get-VMSnapshot -VM $vm -Name $CheckpointName -ErrorAction SilentlyContinue) {
    throw "Checkpoint '$CheckpointName' already exists; refusing to replace it."
}

Checkpoint-VM -VM $vm -SnapshotName $CheckpointName | Out-Null
$snapshot = Get-VMSnapshot -VM $vm -Name $CheckpointName
$result = [ordered]@{}
foreach ($entry in $plan.GetEnumerator()) { $result[$entry.Key] = $entry.Value }
$result.action = 'checkpoint-created'
$result.vmId = $vm.Id.Guid
$result.checkpointId = $snapshot.Id.Guid
$result.checkpointCreationTimeUtc = $snapshot.CreationTime.ToUniversalTime().ToString('o')
$result.createdUtc = [DateTime]::UtcNow.ToString('o')

if (Test-Path -LiteralPath $StatePath) {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    $state | Add-Member -NotePropertyName controlledPackageCheckpoint -NotePropertyValue ([pscustomobject]$result) -Force
    $temporaryState = "$StatePath.tmp"
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryState -Encoding utf8
    Move-Item -LiteralPath $temporaryState -Destination $StatePath -Force
}

[pscustomobject]$result | ConvertTo-Json -Depth 4
