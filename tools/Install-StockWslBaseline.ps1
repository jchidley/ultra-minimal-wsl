#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$VmName = 'ultra-minimal-wsl-dev',
    [string]$GuestUsername = '4cl8y955frge',
    [string]$StockMsiPath = 'C:\controlled-inputs\ultra-minimal-wsl\controlled-inputs\stock-wsl\wsl.2.7.12.0.x64.msi',
    [string]$EvidenceRoot = "$env:LOCALAPPDATA\ultra-minimal-wsl\approval-state\stock-baseline",
    [string]$BaselinePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'recovery-harness\expected-safe-state.json'),
    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$GuestCredential,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ExpectedVmName = 'ultra-minimal-wsl-dev'
$ExpectedGuestUsername = '4cl8y955frge'
$ExpectedMsiPath = 'C:\controlled-inputs\ultra-minimal-wsl\controlled-inputs\stock-wsl\wsl.2.7.12.0.x64.msi'
$ExpectedMsiSha256 = 'a460d4560215f2efe003c136244b78ea3415d773824d7a688ea9ded36dbe9145'
$ExpectedVersion = '2.7.12.0'
$ExpectedCheckpoint = 'controlled-package-baseline'
$ExpectedCleanShellCheckpoint = 'clean-shell'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$script:Baseline = $null
function Assert-FixedInputs {
    if ($VmName -ne $ExpectedVmName) { throw "Refusing VM other than '$ExpectedVmName'." }
    if ($GuestUsername -ne $ExpectedGuestUsername) { throw "Refusing guest account other than '$ExpectedGuestUsername'." }
    if ($StockMsiPath -ne $ExpectedMsiPath) { throw "Refusing MSI path other than the staged stock path." }
    if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) { throw "Safe-state baseline is missing: $BaselinePath" }
    $script:Baseline = [IO.File]::ReadAllText($BaselinePath) | ConvertFrom-Json
    if ($script:Baseline.wslVersion -ne $ExpectedVersion) { throw 'Safe-state version does not match the pinned stock package.' }
}

function Get-TargetVm([string]$Name) {
    Import-Module Hyper-V -ErrorAction Stop
    Hyper-V\Get-VM -Name $Name -ErrorAction Stop
}

function Assert-Off([object]$Vm) {
    if ($Vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
        throw "VM '$VmName' must be Off; current state is $($Vm.State)."
    }
}

function Assert-NoAttachedVmDisk([string]$Name) {
    $drives = @(Get-VMHardDiskDrive -VMName $Name -ErrorAction Stop)
    $attached = @($drives | ForEach-Object {
        Get-DiskImage -ImagePath $_.Path -ErrorAction SilentlyContinue
    } | Where-Object Attached)
    if ($attached.Count -ne 0) { throw "A VM disk is host-attached; refusing to continue." }
}

function Save-Evidence([object]$Value, [string]$Name) {
    New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
    $path = Join-Path $EvidenceRoot $Name
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
}

function Invoke-Guest([System.Management.Automation.Runspaces.PSSession]$Session, [scriptblock]$Command, [hashtable]$Arguments) {
    Invoke-Command -Session $Session -ScriptBlock $Command -ArgumentList $Arguments -ErrorAction Stop
}

Assert-FixedInputs
$plan = [ordered]@{
    schema = 1
    action = if ($Execute) { 'install-stock-baseline' } else { 'plan-install-stock-baseline' }
    executable = [bool]$Execute
    vmName = $ExpectedVmName
    guestUsername = $ExpectedGuestUsername
    stockMsiPath = $ExpectedMsiPath
    stockMsiSha256 = $ExpectedMsiSha256
    expectedVersion = $ExpectedVersion
    expectedCheckpoint = $ExpectedCheckpoint
    requiredCleanShellCheckpoint = $ExpectedCleanShellCheckpoint
    requiresElevation = $true
    credentialInput = 'PSCredential supplied locally with Get-Credential; password is never serialized or written.'
    network = 'PowerShell Direct only; no network transport or download.'
    acceptedMsiExitCodes = @(0)
}
if (-not $Execute) {
    [pscustomobject]$plan | ConvertTo-Json -Depth 5
    exit 0
}
if (-not (Test-IsAdministrator)) { throw 'Execution requires an elevated PowerShell process and explicit -Execute.' }
if ($null -eq $GuestCredential) { throw 'Execution requires a local PSCredential.' }
if ($GuestCredential.UserName -ne $ExpectedGuestUsername) { throw 'Credential username does not match the fixed disposable account.' }

$vm = Get-TargetVm $ExpectedVmName
Assert-Off $vm
Assert-NoAttachedVmDisk $ExpectedVmName
if (-not (Get-VMSnapshot -VM $vm -Name $ExpectedCleanShellCheckpoint -ErrorAction SilentlyContinue)) {
    throw "Required checkpoint '$ExpectedCleanShellCheckpoint' does not exist; refusing to continue."
}
if (Get-VMSnapshot -VM $vm -Name $ExpectedCheckpoint -ErrorAction SilentlyContinue) {
    throw "Checkpoint '$ExpectedCheckpoint' already exists; refusing to replace it."
}

$session = $null
$started = $false
$failure = $null
try {
    Start-VM -VM $vm -ErrorAction Stop | Out-Null
    $started = $true
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do {
        Start-Sleep -Seconds 2
        $vm = Get-TargetVm $ExpectedVmName
    } while ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Running -and [DateTime]::UtcNow -lt $deadline)
    if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Running) { throw 'VM did not reach Running before the timeout.' }

    $sessionDeadline = [DateTime]::UtcNow.AddMinutes(10)
    $lastSessionError = $null
    do {
        try {
            $session = New-PSSession -VMName $ExpectedVmName -Credential $GuestCredential -ErrorAction Stop
        }
        catch {
            $session = $null
            $lastSessionError = $_
            if ([DateTime]::UtcNow -lt $sessionDeadline) { Start-Sleep -Seconds 5 }
        }
    } while ($null -eq $session -and [DateTime]::UtcNow -lt $sessionDeadline)
    if ($null -eq $session) { throw "PowerShell Direct session was unavailable after 10 minutes. Last error: $($lastSessionError.Exception.Message)" }
    $guest = Invoke-Guest $session {
        param($a)
        $msi = Get-Item -LiteralPath $a.msiPath -ErrorAction Stop
        $hash = (Get-FileHash -LiteralPath $msi.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $a.msiSha256 -or $msi.Length -ne 258998272) { throw 'Staged MSI hash or size mismatch.' }
        $log = 'C:\controlled-inputs\ultra-minimal-wsl\controlled-inputs\stock-wsl\stock-install.log'
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $msi.FullName, '/qn', '/norestart', '/L*v', $log) -Wait -PassThru
        if ($process.ExitCode -notin @(0)) { throw "Stock MSI exited with unsupported code $($process.ExitCode)." }
        $version = & wsl.exe --version 2>&1 | Out-String
        $versionExit = $LASTEXITCODE
        $status = & wsl.exe --status 2>&1 | Out-String
        $statusExit = $LASTEXITCODE
        $list = & wsl.exe --list --quiet 2>&1 | Out-String
        $listExit = $LASTEXITCODE
        if ($versionExit -ne 0 -or $statusExit -ne 0 -or $listExit -ne 0 -or $version -notmatch [regex]::Escape($a.version)) { throw 'Stock WSL command checks failed.' }
        $kernel = 'C:\Program Files\WSL\tools\kernel'
        $initrd = 'C:\Program Files\WSL\tools\initrd.img'
        $config = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.wslconfig'
        [pscustomobject]@{
            msiSha256 = $hash; msiBytes = $msi.Length; msiExitCode = $process.ExitCode
            version = $version.Trim(); versionExit = $versionExit; status = $status.Trim(); statusExit = $statusExit; list = $list.Trim(); listExit = $listExit
            kernelSha256 = (Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash.ToLowerInvariant()
            initrdSha256 = (Get-FileHash -LiteralPath $initrd -Algorithm SHA256).Hash.ToLowerInvariant()
            configSha256 = if (Test-Path -LiteralPath $config) { (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
            configPath = $config; installLog = $log
        }
    } @{ msiPath = $ExpectedMsiPath; msiSha256 = $ExpectedMsiSha256; version = $ExpectedVersion }
    Save-Evidence $guest 'stock-baseline-guest.json'
    if ($guest.kernelSha256 -ne $script:Baseline.packagedKernelSha256 -or $guest.initrdSha256 -ne $script:Baseline.packagedInitrdSha256) {
        throw 'Packaged kernel or initrd hash differs from expected-safe-state.json.'
    }
    if ($guest.configPath -ne "C:\Users\$ExpectedGuestUsername\.wslconfig") { throw 'Unexpected guest configuration path.' }
    if ($null -ne $guest.configSha256) { throw 'Guest .wslconfig must remain absent for the isolated stock baseline.' }
    Invoke-Guest $session { wsl.exe --shutdown } @{} | Out-Null
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    $session = $null
    Stop-VM -Name $ExpectedVmName -Confirm:$false -ErrorAction Stop | Out-Null
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do { Start-Sleep -Seconds 2; $vm = Get-TargetVm $ExpectedVmName } while ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off -and [DateTime]::UtcNow -lt $deadline)
    if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'VM did not reach Off before the timeout.' }
    Assert-NoAttachedVmDisk $ExpectedVmName
    $checkpoint = & (Join-Path $PSScriptRoot 'Checkpoint-DisposableWslDevVm.ps1') -VmName $ExpectedVmName -CheckpointName $ExpectedCheckpoint -Execute
    Save-Evidence $checkpoint 'checkpoint.json'
}
catch {
    $failure = $_
    throw
}
finally {
    if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    $GuestCredential = $null
    if ($started) {
        $vm = Get-TargetVm $ExpectedVmName
        if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
            Stop-VM -Name $ExpectedVmName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            $deadline = [DateTime]::UtcNow.AddMinutes(5)
            do { Start-Sleep -Seconds 2; $vm = Get-TargetVm $ExpectedVmName } while ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off -and [DateTime]::UtcNow -lt $deadline)
        }
    }
    $final = Get-TargetVm $ExpectedVmName
    if ($final.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Finally could not independently restore VM Off; checkpoint remains absent.' }
    Assert-NoAttachedVmDisk $ExpectedVmName
    Save-Evidence ([ordered]@{ safe = ($final.State -eq [Microsoft.HyperV.PowerShell.VMState]::Off); vmState = [string]$final.State; failed = ($null -ne $failure) }) 'final-state.json'
}
