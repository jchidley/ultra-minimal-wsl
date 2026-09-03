#Requires -Version 7.0
# FixtureBroker-SecureWorkload: 1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vmName = 'ultra-minimal-wsl-dev'
$vmId = 'dcbf722c-0702-444e-9496-04a4623c3198'
$checkpoint = 'clean-shell'
$distribution = 'Debian2'
$project = 'C:\Users\jackc\git\ultra-minimal-wsl'
$manifestSource = Join-Path $project 'control-plane\test-article\debian2-inputs.v1.json'
$bootstrapSource = Join-Path $project 'control-plane\test-article\Bootstrap-Debian2V2.sh'
$manifestHash = '1925fe7507897b9ff5f330deef08b1e1a85e737a77055b82cb0f8a29512e3ed3'
$bootstrapHash = '977909d85e46bb9639ff4826788653cab639d0e752623986a88694bbd5414855'
$root = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_RUN_ROOT')
$credentialPath = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_CREDENTIAL')
if (-not $root -or -not $credentialPath) { throw 'Protected broker environment is required.' }
$root = [IO.Path]::GetFullPath($root).TrimEnd('\')
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'UltraMinimalWslFixtureBroker\Runs')).TrimEnd('\')
if (-not $root.StartsWith($expectedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Protected run root mismatch.' }
$resultDirectory = Join-Path $root 'results\debian2'
$resultPath = Join-Path $root 'results\workload-operation-result.json'
$credential = Import-Clixml -LiteralPath $credentialPath

function Get-Hash([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required input is missing: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Save-Result([object] $Value) {
    [IO.File]::WriteAllText($resultPath, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}
function Expand-InputPath([string] $Path) {
    [Environment]::ExpandEnvironmentVariables($Path)
}

if ((Get-Hash $manifestSource) -ne $manifestHash) { throw 'Debian2 input manifest identity mismatch.' }
if ((Get-Hash $bootstrapSource) -ne $bootstrapHash) { throw 'Debian2 bootstrap identity mismatch.' }
$inputManifest = Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
if ($inputManifest.schema -ne 1 -or $inputManifest.articleId -ne 'debian2-stock-bootstrap-v1' -or $inputManifest.secrets -ne 'none') {
    throw 'Unexpected Debian2 input manifest contract.'
}
foreach ($item in @($inputManifest.inputs)) {
    $source = Expand-InputPath ([string]$item.source)
    if ((Get-Item -LiteralPath $source).Length -ne [int64]$item.bytes -or (Get-Hash $source) -ne [string]$item.sha256) {
        throw "Debian2 source identity mismatch: $($item.name)"
    }
}

$vm = Get-VM -Name $vmName -ErrorAction Stop
if ($vm.Id.Guid -ne $vmId -or $vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Disposable fixture identity/state mismatch.' }
$snapshots = @(Get-VMSnapshot -VM $vm | Select-Object -ExpandProperty Name)
if ($snapshots.Count -ne 1 -or $snapshots[0] -ne $checkpoint) { throw 'Disposable fixture checkpoint mismatch.' }

$session = $null
$started = $false
$articleCreationStarted = $false
$remoteResult = $null
$cleanupResult = $null
$outerFailure = $null
try {
    Start-VM -VM $vm | Out-Null
    $started = $true
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    do {
        try { $session = New-PSSession -VMName $vmName -Credential $credential -ErrorAction Stop }
        catch { Start-Sleep -Seconds 5 }
    } while (-not $session -and [DateTime]::UtcNow -lt $deadline)
    if (-not $session) { throw 'PowerShell Direct unavailable.' }

    $preflight = Invoke-Command -Session $session -ScriptBlock {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $wsl = 'C:\Windows\System32\wsl.exe'
        $name = 'Debian2'
        $install = 'C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2'
        $listed = (& $wsl --list --quiet).Replace("`0", '') -split "`r?`n"
        if ($LASTEXITCODE -ne 0) { throw 'Fixture distro enumeration failed.' }
        if ($listed -contains $name -or (Test-Path -LiteralPath $install)) { throw 'Debian2 already exists; refusing to replace the test article.' }
        if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.wslconfig')) { throw 'Fixture .wslconfig must be absent before Debian2 preparation.' }
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class Debian2MsiState {
 [DllImport("msi.dll", CharSet=CharSet.Unicode)] public static extern int MsiQueryProductState(string product);
}
'@
        $stock = [Debian2MsiState]::MsiQueryProductState('{020F8AC8-A788-4E39-8E9B-8FECFA843632}')
        $candidate = [Debian2MsiState]::MsiQueryProductState('{65E3A12F-0AF8-4D54-A19A-29A07D5186E3}')
        if ($stock -ne 5 -or $candidate -eq 5) { throw 'Debian2 preparation requires the exact stock WSL package state.' }
        [pscustomobject]@{ stockProductState=$stock; candidateProductState=$candidate; wslconfigAbsent=$true }
    }

    Invoke-Command -Session $session -ScriptBlock {
        $stage = 'C:\controlled-inputs\ultra-minimal-wsl\debian2\v1'
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        [IO.Directory]::CreateDirectory('C:\controlled-wsl-trials\DEBIAN2-ARTICLE-001') | Out-Null
    }
    Copy-Item -ToSession $session -LiteralPath $manifestSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\debian2\v1\debian2-inputs.v1.json'
    Copy-Item -ToSession $session -LiteralPath $bootstrapSource -Destination 'C:\controlled-inputs\ultra-minimal-wsl\debian2\v1\Bootstrap-Debian2.sh'
    foreach ($item in @($inputManifest.inputs)) {
        Copy-Item -ToSession $session -LiteralPath (Expand-InputPath ([string]$item.source)) `
            -Destination (Join-Path 'C:\controlled-inputs\ultra-minimal-wsl\debian2\v1' ([string]$item.file))
    }

    $articleCreationStarted = $true
    $remoteResult = Invoke-Command -Session $session -ScriptBlock {
        param($ManifestHash,$BootstrapHash)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $wsl = 'C:\Windows\System32\wsl.exe'
        $name = 'Debian2'
        $stage = 'C:\controlled-inputs\ultra-minimal-wsl\debian2\v1'
        $install = 'C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2'
        $logs = 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-001'
        function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
        function Join-WindowsCommandLine([string[]]$Arguments) {
            @($Arguments | ForEach-Object {
                if ($_ -notmatch '[\s"]') { $_ }
                else { '"' + ([regex]::Replace($_, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
            }) -join ' '
        }
        function Invoke-Captured([string]$Label,[string[]]$Arguments,[int]$TimeoutSeconds) {
            $stdout = Join-Path $logs "$Label.stdout.log"
            $stderr = Join-Path $logs "$Label.stderr.log"
            $info = [Diagnostics.ProcessStartInfo]::new()
            $info.FileName = $wsl
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $info.Arguments = Join-WindowsCommandLine $Arguments
            $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
            if (-not $process.Start()) { throw "Failed to start $Label." }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
            $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
            if ($timedOut) {
                $killer = Start-Process -FilePath 'C:\Windows\System32\taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -Wait -PassThru -WindowStyle Hidden
                $null = $process.WaitForExit(10000)
            }
            $streams = [Threading.Tasks.Task]::WaitAll(@($stdoutTask,$stderrTask),10000)
            [IO.File]::WriteAllText($stdout, $(if($stdoutTask.IsCompleted){$stdoutTask.GetAwaiter().GetResult()}else{'<stdout collection timed out>'}), [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($stderr, $(if($stderrTask.IsCompleted){$stderrTask.GetAwaiter().GetResult()}else{'<stderr collection timed out>'}), [Text.UTF8Encoding]::new($false))
            if ($timedOut -or -not $streams -or $process.ExitCode -ne 0) { throw "$Label failed: timeout=$timedOut streams=$streams exit=$($process.ExitCode)." }
            [pscustomobject]@{label=$Label;exitCode=$process.ExitCode;timedOut=$timedOut}
        }
        if ((Hash (Join-Path $stage 'debian2-inputs.v1.json')) -ne $ManifestHash -or (Hash (Join-Path $stage 'Bootstrap-Debian2.sh')) -ne $BootstrapHash) { throw 'Staged Debian2 procedure identity mismatch.' }
        $manifest = Get-Content -LiteralPath (Join-Path $stage 'debian2-inputs.v1.json') -Raw | ConvertFrom-Json
        foreach ($item in @($manifest.inputs)) {
            $path = Join-Path $stage ([string]$item.file)
            if ((Get-Item -LiteralPath $path).Length -ne [int64]$item.bytes -or (Hash $path) -ne [string]$item.sha256) { throw "Staged input mismatch: $($item.name)" }
        }
        [IO.Directory]::CreateDirectory((Split-Path $install)) | Out-Null
        $import = Invoke-Captured 'import' @('--import',$name,$install,(Join-Path $stage 'debian-13.5-amd64-wsl-rootfs.tar.gz'),'--version','2') 180
        $bootstrap = Invoke-Captured 'bootstrap' @('--distribution',$name,'--user','root','--exec','/bin/bash','/mnt/c/controlled-inputs/ultra-minimal-wsl/debian2/v1/Bootstrap-Debian2.sh') 5400
        & $wsl --shutdown
        if ($LASTEXITCODE -ne 0) { throw 'Post-bootstrap WSL shutdown failed.' }
        $hostWslConfig = Join-Path $env:USERPROFILE '.wslconfig'
        if (Test-Path -LiteralPath $hostWslConfig) { Remove-Item -LiteralPath $hostWslConfig -Force }
        $listed = (& $wsl --list --quiet).Replace("`0", '') -split "`r?`n"
        if ($LASTEXITCODE -ne 0 -or $listed -notcontains $name) { throw 'Debian2 is not registered after bootstrap.' }
        $identity = (& $wsl --distribution $name --exec /usr/bin/id -un).Replace("`0", '').Trim()
        if ($LASTEXITCODE -ne 0 -or $identity -ne 'jack') { throw "Debian2 default-user verification failed: $identity" }
        $articleManifest = (& $wsl --distribution $name --user root --exec /bin/cat /var/lib/debian2-article/manifest.json).Replace("`0", '')
        if ($LASTEXITCODE -ne 0) { throw 'Debian2 article manifest extraction failed.' }
        [IO.File]::WriteAllText((Join-Path $logs 'article-manifest.json'), $articleManifest, [Text.UTF8Encoding]::new($false))
        & $wsl --shutdown
        if ($LASTEXITCODE -ne 0) { throw 'Final WSL shutdown failed.' }
        if (Test-Path -LiteralPath $hostWslConfig) { throw 'Fixture .wslconfig remained after Debian2 preparation.' }
        $vhdx = Join-Path $install 'ext4.vhdx'
        if (-not (Test-Path -LiteralPath $vhdx -PathType Leaf)) { throw 'Debian2 VHDX is missing.' }
        [pscustomobject][ordered]@{
            import=$import; bootstrap=$bootstrap; distribution=$name; defaultUser=$identity
            installPath=$install; vhdxBytes=(Get-Item -LiteralPath $vhdx).Length; vhdxSha256=Hash $vhdx
            articleManifest=($articleManifest | ConvertFrom-Json); wslconfigAbsent=$true
        }
    } -ArgumentList $manifestHash,$bootstrapHash

    [IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
    foreach ($name in @('import.stdout.log','import.stderr.log','bootstrap.stdout.log','bootstrap.stderr.log','article-manifest.json')) {
        Copy-Item -FromSession $session -LiteralPath (Join-Path 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-001' $name) -Destination (Join-Path $resultDirectory $name)
    }
    Save-Result ([ordered]@{schema=1;operation='debian2-article-preparation-031';preflight=$preflight;article=$remoteResult;fixtureMutation='Debian2 retained';completedUtc=[DateTime]::UtcNow.ToString('o')})
}
catch { $outerFailure = $_ }
finally {
    if ($session) {
        if ($outerFailure) {
            try {
                $cleanupResult = Invoke-Command -Session $session -ScriptBlock {
                    param($RemoveArticle)
                    $wsl = 'C:\Windows\System32\wsl.exe'; $name='Debian2'; $install='C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2'
                    $listed = (& $wsl --list --quiet).Replace("`0", '') -split "`r?`n"
                    if ($RemoveArticle -and $LASTEXITCODE -eq 0 -and $listed -contains $name) { & $wsl --unregister $name | Out-Null }
                    & $wsl --shutdown | Out-Null
                    if ($RemoveArticle -and (Test-Path -LiteralPath $install)) { Remove-Item -LiteralPath $install -Recurse -Force }
                    $config = Join-Path $env:USERPROFILE '.wslconfig'; if (Test-Path -LiteralPath $config) { Remove-Item -LiteralPath $config -Force }
                    [pscustomobject]@{partialArticleRemoved=$RemoveArticle;wslconfigAbsent=-not (Test-Path -LiteralPath $config)}
                } -ArgumentList $articleCreationStarted
            } catch { $outerFailure = [System.Management.Automation.ErrorRecord]::new([Exception]::new($outerFailure.Exception.Message + '; cleanup: ' + $_.Exception.Message),'Debian2CleanupFailure',[System.Management.Automation.ErrorCategory]::OperationStopped,$null) }
            [IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
            foreach ($name in @('import.stdout.log','import.stderr.log','bootstrap.stdout.log','bootstrap.stderr.log')) {
                $guestPath = Join-Path 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-001' $name
                if (Invoke-Command -Session $session -ScriptBlock { param($Path) Test-Path -LiteralPath $Path -PathType Leaf } -ArgumentList $guestPath) {
                    Copy-Item -FromSession $session -LiteralPath $guestPath -Destination (Join-Path $resultDirectory $name) -Force
                }
            }
            Save-Result ([ordered]@{schema=1;operation='debian2-article-preparation-031';failure=$outerFailure.Exception.Message;cleanup=$cleanupResult;completedUtc=[DateTime]::UtcNow.ToString('o')})
        }
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
    if ($started) {
        $current = Get-VM -Name $vmName -ErrorAction Stop
        if ($current.Id.Guid -ne $vmId) { throw 'Fixture identity changed before shutdown.' }
        if ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { Stop-VM -VM $current -Confirm:$false | Out-Null }
        $deadline = [DateTime]::UtcNow.AddMinutes(5)
        do { Start-Sleep -Seconds 2; $current = Get-VM -Name $vmName } while ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off -and [DateTime]::UtcNow -lt $deadline)
        if ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Disposable fixture did not return Off.' }
    }
}
if ($outerFailure) { throw $outerFailure }
$final = Get-VM -Name $vmName -ErrorAction Stop
if ($final.Id.Guid -ne $vmId -or $final.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Fixture final identity/state mismatch.' }
if (-not $remoteResult -or -not $remoteResult.wslconfigAbsent -or $remoteResult.defaultUser -ne 'jack') { throw 'Debian2 article acceptance failed.' }
