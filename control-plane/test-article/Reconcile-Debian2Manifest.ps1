#Requires -Version 7.0
# FixtureBroker-SecureWorkload: 1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vmName = 'ultra-minimal-wsl-dev'
$vmId = 'dcbf722c-0702-444e-9496-04a4623c3198'
$checkpoint = 'clean-shell'
$root = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_RUN_ROOT')
$credentialPath = [Environment]::GetEnvironmentVariable('ULTRAMINIMALWSL_SECURE_CREDENTIAL')
if (-not $root -or -not $credentialPath) { throw 'Protected broker environment is required.' }
$root = [IO.Path]::GetFullPath($root).TrimEnd('\')
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'UltraMinimalWslFixtureBroker\Runs')).TrimEnd('\')
if (-not $root.StartsWith($expectedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Protected run root mismatch.' }
$operationId = Split-Path $root -Leaf
if ($operationId -notmatch '^debian2-article-manifest-reconciliation-[0-9]{3}$') { throw 'Protected run ID is not a Debian2 manifest reconciliation operation.' }
$resultDirectory = Join-Path $root 'results\debian2'
$resultPath = Join-Path $root 'results\workload-operation-result.json'
$credential = Import-Clixml -LiteralPath $credentialPath
function Save([object]$Value) { [IO.File]::WriteAllText($resultPath, ($Value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false)) }

$vm = Get-VM -Name $vmName -ErrorAction Stop
if ($vm.Id.Guid -ne $vmId -or $vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Disposable fixture identity/state mismatch.' }
$snapshots = @(Get-VMSnapshot -VM $vm | Select-Object -ExpandProperty Name)
if ($snapshots.Count -ne 1 -or $snapshots[0] -ne $checkpoint) { throw 'Disposable fixture checkpoint mismatch.' }
if (@(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop).Count -ne 0) { throw 'Fixture must begin with zero network adapters.' }

$session = $null
$started = $false
$remote = $null
$failure = $null
try {
    Start-VM -VM $vm | Out-Null
    $started = $true
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    do {
        try { $session = New-PSSession -VMName $vmName -Credential $credential -ErrorAction Stop }
        catch { Start-Sleep -Seconds 5 }
    } while (-not $session -and [DateTime]::UtcNow -lt $deadline)
    if (-not $session) { throw 'PowerShell Direct unavailable.' }
    $remote = Invoke-Command -Session $session -ScriptBlock {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $wsl = 'C:\Windows\System32\wsl.exe'
        $name = 'Debian2'
        $install = 'C:\controlled-inputs\ultra-minimal-wsl\registered-distros\Debian2'
        $evidence = 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-MANIFEST-RECONCILIATION-001'
        function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
        function Join-WindowsCommandLine([string[]]$Arguments) {
            @($Arguments | ForEach-Object { if ($_ -notmatch '[\s"]') { $_ } else { '"' + ([regex]::Replace($_, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' } }) -join ' '
        }
        function Invoke-Captured([string]$Label, [string[]]$Arguments) {
            $info = [Diagnostics.ProcessStartInfo]::new()
            $info.FileName = $wsl
            $info.Arguments = Join-WindowsCommandLine $Arguments
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $info
            if (-not $process.Start()) { throw "Failed to start $Label." }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $timedOut = -not $process.WaitForExit(120000)
            if ($timedOut) {
                $killer = Start-Process 'C:\Windows\System32\taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -Wait -PassThru -WindowStyle Hidden
                $null = $process.WaitForExit(10000)
            }
            $streams = [Threading.Tasks.Task]::WaitAll(@($stdoutTask,$stderrTask),10000)
            $stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.GetAwaiter().GetResult() } else { '<timeout>' }
            $stderr = if ($stderrTask.IsCompleted) { $stderrTask.GetAwaiter().GetResult() } else { '<timeout>' }
            [IO.File]::WriteAllText((Join-Path $evidence "$Label.stdout.log"), $stdout, [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $evidence "$Label.stderr.log"), $stderr, [Text.UTF8Encoding]::new($false))
            [pscustomobject]@{ stdout=$stdout; stderr=$stderr; exitCode=$process.ExitCode; timedOut=$timedOut; streamsComplete=$streams }
        }
        if (Test-Path $evidence) { Remove-Item $evidence -Recurse -Force }
        [IO.Directory]::CreateDirectory($evidence) | Out-Null
        $listed = (& $wsl --list --quiet).Replace("`0", '') -split "`r?`n"
        if ($LASTEXITCODE -ne 0 -or $listed -notcontains $name) { throw 'Debian2 is not registered.' }
        $config = Join-Path $env:USERPROFILE '.wslconfig'
        if (Test-Path $config) { throw 'Fixture .wslconfig must be absent.' }
        $vhdx = Join-Path $install 'ext4.vhdx'
        $manifestText = (& $wsl --distribution $name --user root --exec /bin/cat /var/lib/debian2-article/manifest.json).Replace("`0", '')
        if ($LASTEXITCODE -ne 0) { throw 'Could not read the Debian2 article manifest.' }
        $manifest = $manifestText | ConvertFrom-Json
        if ($manifest.articleId -ne 'debian2-stock-bootstrap-v10' -or $manifest.defaultUser -ne 'jack' -or $manifest.node -ne 'v22.19.0' -or $manifest.npm -notmatch '^[0-9]+\.' -or $manifest.pi -ne '0.84.4' -or $manifest.secrets -ne 'none' -or -not $manifest.manifestCorrectedUtc) {
            throw 'The operation 047 manifest mutation is not present and valid.'
        }
        $interactiveResult = Invoke-Captured 'interactive-pi' @('--distribution',$name,'--user','jack','--exec','/bin/bash','-lic','set -e; test "$(pi --version)" = 0.84.4; pi list | tr -d "\r" | grep -F "$HOME/git/agent-skills"')
        $interactive = $interactiveResult.stdout.Replace("`0", '')
        if ($interactiveResult.timedOut -or -not $interactiveResult.streamsComplete -or $interactiveResult.exitCode -ne 0 -or $interactive -notmatch '/home/jack/git/agent-skills') { throw 'Interactive Pi or agent-skills package verification failed.' }
        [IO.File]::WriteAllText((Join-Path $evidence 'article-manifest.json'), $manifestText, [Text.UTF8Encoding]::new($false))
        & $wsl --shutdown
        if ($LASTEXITCODE -ne 0) { throw 'WSL shutdown failed after reconciliation.' }
        $afterHash = Hash $vhdx
        [pscustomobject]@{
            distribution = $name
            articleId = $manifest.articleId
            defaultUser = $manifest.defaultUser
            node = $manifest.node
            npm = $manifest.npm
            pi = $manifest.pi
            manifestCorrectedUtc = $manifest.manifestCorrectedUtc
            vhdxBytes = (Get-Item $vhdx).Length
            vhdxSha256 = $afterHash
            wslconfigAbsent = -not (Test-Path $config)
            interactivePi = $interactive
        }
    }
    [IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
    foreach ($name in @('article-manifest.json','interactive-pi.stdout.log','interactive-pi.stderr.log')) {
        Copy-Item -FromSession $session -LiteralPath (Join-Path 'C:\controlled-wsl-trials\DEBIAN2-ARTICLE-MANIFEST-RECONCILIATION-001' $name) -Destination (Join-Path $resultDirectory $name)
    }
    Save ([ordered]@{schema=1;operation=$operationId;reconciliation=$remote;completedUtc=[DateTime]::UtcNow.ToString('o')})
}
catch { $failure = $_; Save ([ordered]@{schema=1;operation=$operationId;failure=$_.Exception.Message;completedUtc=[DateTime]::UtcNow.ToString('o')}) }
finally {
    if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    if ($started) {
        $current = Get-VM -Name $vmName
        if ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { Stop-VM -VM $current -Confirm:$false | Out-Null }
        $deadline = [DateTime]::UtcNow.AddMinutes(5)
        do { Start-Sleep 2; $current = Get-VM -Name $vmName } while ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off -and [DateTime]::UtcNow -lt $deadline)
        if ($current.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { throw 'Fixture did not return Off.' }
    }
}
if ($failure) { throw $failure }
$final = Get-VM -Name $vmName
if ($final.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off -or @(Get-VMNetworkAdapter -VM $final).Count -ne 0) { throw 'Fixture final state mismatch.' }
if (-not $remote -or $remote.pi -ne '0.84.4' -or -not $remote.wslconfigAbsent) { throw 'Manifest reconciliation acceptance failed.' }
