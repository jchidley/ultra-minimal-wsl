[CmdletBinding(DefaultParameterSetName = 'Trial')]
param(
    [Parameter(ParameterSetName = 'Trial', Mandatory = $true)]
    [ValidateSet('StockValidation', 'KernelTrial')]
    [string]$Mode,

    [Parameter(ParameterSetName = 'Trial', Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$TrialId,

    [Parameter(ParameterSetName = 'Trial', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CandidateKernel,

    [Parameter(ParameterSetName = 'Trial', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TestDistribution,

    [Parameter(ParameterSetName = 'Trial')]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryDistribution = 'Debian',

    [Parameter(ParameterSetName = 'Trial')]
    [ValidateRange(5, 600)]
    [int]$TimeoutSeconds = 45,

    [Parameter(ParameterSetName = 'Trial')]
    [ValidateNotNullOrEmpty()]
    [string]$TestCommand = 'test -r /proc/self/status && test -d /sys && test -c /dev/null && printf toybox-ok',

    [Parameter(ParameterSetName = 'Trial')]
    [string]$SourceCommit = '',

    [Parameter(ParameterSetName = 'Trial')]
    [string]$Toolchain = '',

    [Parameter(ParameterSetName = 'Trial')]
    [string]$KernelConfigPath = '',

    [Parameter(ParameterSetName = 'Trial')]
    [switch]$AllowCustomKernel,

    [Parameter(ParameterSetName = 'Trial')]
    [switch]$Execute,

    [Parameter(ParameterSetName = 'Trial')]
    [switch]$EnableDebugConsole,

    [Parameter(ParameterSetName = 'Recover', Mandatory = $true)]
    [switch]$Recover,

    [Parameter(ParameterSetName = 'SelfTest', Mandatory = $true)]
    [switch]$SelfTest,

    [string]$StateRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'recovery-harness'),
    [string]$WslRoot = 'C:\Program Files\WSL',
    [string]$TrialLedger = (Join-Path (Split-Path -Parent $PSScriptRoot) 'inventory\trials.v1.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (($Execute -or $Recover) -and [IO.Path]::GetFileName($TrialLedger) -eq 'trials.v1.csv') {
    throw 'The legacy CSV trial harness is read-only after the experiment-database migration; prepare new trials through tools/experiment.py and the controlled runner.'
}

$packagedKernel = Join-Path $WslRoot 'tools\kernel'
$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
$journalPath = Join-Path $StateRoot 'active-kernel-trial.json'
$mutex = $null

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FileEvidence([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    [ordered]@{ path = $item.FullName; length = $item.Length; lastWriteUtc = $item.LastWriteTimeUtc.ToString('o'); sha256 = (Get-Sha256 $Path) }
}

function Write-JsonFileAtomic([string]$Path, $Value) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Enter-TrialMutex {
    $script:mutex = [Threading.Mutex]::new($false, 'Local\UltraMinimalWslKernelTrial')
    if (-not $script:mutex.WaitOne(0)) { throw 'Another WSL kernel trial or recovery process is active.' }
}

function Exit-TrialMutex {
    if ($script:mutex) {
        try { $script:mutex.ReleaseMutex() } catch {}
        $script:mutex.Dispose()
        $script:mutex = $null
    }
}

function Get-WslText([string[]]$Arguments) {
    $output = & wsl.exe @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "wsl.exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE`: $output" }
    $output.Replace("`0", '').Trim()
}

function Assert-DistributionExists([string]$Name) {
    $names = @((Get-WslText @('--list', '--quiet')) -split "`r?`n" | Where-Object { -not [String]::IsNullOrWhiteSpace($_) })
    if ($names -notcontains $Name) { throw "WSL distribution is not registered: $Name" }
}

function Get-BlockingWslManagementProcesses {
    @(
        Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match '(?i)\s--(export|import|unregister|manage|set-version|install|uninstall)(\s|$)' } |
            Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine
    )
}

function Assert-NoWslManagementOperation {
    $blocking = @(Get-BlockingWslManagementProcesses)
    if ($blocking.Count -gt 0) {
        $summary = ($blocking | ForEach-Object { "PID $($_.ProcessId): $($_.CommandLine)" }) -join '; '
        throw "A WSL management operation is active; refusing to change .wslconfig or shut WSL down. $summary"
    }
}

function Test-LinuxBootKernel([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 0x210) { throw "Candidate is too small to be an x86 Linux boot kernel: $Path" }
        $buffer = New-Object byte[] 0x210
        if ($stream.Read($buffer, 0, $buffer.Length) -ne $buffer.Length) { throw "Could not read candidate kernel header: $Path" }
    }
    finally { $stream.Dispose() }
    if ($buffer[0x1fe] -ne 0x55 -or $buffer[0x1ff] -ne 0xaa) { throw 'Candidate kernel lacks the x86 boot signature at offset 0x1fe.' }
    $header = [Text.Encoding]::ASCII.GetString($buffer, 0x202, 4)
    if ($header -ne 'HdrS') { throw 'Candidate kernel lacks the Linux HdrS signature at offset 0x202.' }
    $item = Get-Item -LiteralPath $Path
    [ordered]@{ path = $item.FullName; length = $item.Length; sha256 = (Get-Sha256 $Path); bootProtocol = ('{0}.{1:D2}' -f $buffer[0x207], $buffer[0x206]) }
}

function Assert-ExternalCandidate([string]$CandidatePath) {
    $candidateFull = [IO.Path]::GetFullPath($CandidatePath).TrimEnd('\')
    $wslFull = [IO.Path]::GetFullPath($WslRoot).TrimEnd('\')
    if ($candidateFull.StartsWith($wslFull + '\', [StringComparison]::OrdinalIgnoreCase) -or $candidateFull -ieq $wslFull) {
        throw 'Candidate kernel must remain outside the installed WSL directory.'
    }
}

function Read-ConfigDocument([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ exists = $false; bytes = [byte[]]@(); text = ''; encoding = [Text.UTF8Encoding]::new($false); preambleLength = 0; newline = "`r`n" }
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $encoding = $null
    $preambleLength = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        $encoding = [Text.UTF8Encoding]::new($true); $preambleLength = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xff -and $bytes[1] -eq 0xfe) {
        $encoding = [Text.UnicodeEncoding]::new($false, $true); $preambleLength = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xfe -and $bytes[1] -eq 0xff) {
        $encoding = [Text.UnicodeEncoding]::new($true, $true); $preambleLength = 2
    }
    else { $encoding = [Text.UTF8Encoding]::new($false, $true) }
    try { $text = $encoding.GetString($bytes, $preambleLength, $bytes.Length - $preambleLength) }
    catch { throw ".wslconfig is not valid in its detected encoding: $($_.Exception.Message)" }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    [pscustomobject]@{ exists = $true; bytes = $bytes; text = $text; encoding = $encoding; preambleLength = $preambleLength; newline = $newline }
}

function New-KernelConfigBytes($Document, [string]$KernelPath, [bool]$WithDebugConsole = $false) {
    $lines = @($Document.text -split '\r?\n', -1)
    $section = ''
    $wsl2Index = -1
    $kernelIndexes = @()
    $debugIndexes = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\[([^]]+)\]$') {
            $section = $Matches[1]
            if ($section -ieq 'wsl2') {
                if ($wsl2Index -ge 0) { throw '.wslconfig contains duplicate [wsl2] sections.' }
                $wsl2Index = $i
            }
            continue
        }
        if ($section -ieq 'wsl2' -and $lines[$i] -match '^\s*kernel\s*=') { $kernelIndexes += $i }
        if ($section -ieq 'wsl2' -and $lines[$i] -match '^\s*debugConsole\s*=') { $debugIndexes += $i }
    }
    if ($kernelIndexes.Count -gt 1) { throw '.wslconfig contains duplicate kernel= settings.' }
    if ($debugIndexes.Count -gt 1) { throw '.wslconfig contains duplicate debugConsole= settings.' }
    $kernelSetting = 'kernel=' + $KernelPath.Replace('\', '/')
    $output = [Collections.Generic.List[string]]::new()
    $output.AddRange([string[]]$lines)
    if (-not $Document.exists -or $Document.text.Length -eq 0) { $output.Clear() }
    if ($kernelIndexes.Count -eq 1) { $output[$kernelIndexes[0]] = $kernelSetting }
    elseif ($wsl2Index -ge 0) { $output.Insert($wsl2Index + 1, $kernelSetting) }
    else {
        if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne '') { $output.Add('') }
        $output.Add('[wsl2]')
        $wsl2Index = $output.Count - 1
        $output.Add($kernelSetting)
    }
    if ($WithDebugConsole) {
        if ($debugIndexes.Count -eq 1) {
            $adjustedIndex = $debugIndexes[0]
            if ($kernelIndexes.Count -eq 0 -and $wsl2Index -ge 0 -and $debugIndexes[0] -gt $wsl2Index) { $adjustedIndex++ }
            $output[$adjustedIndex] = 'debugConsole=true'
        }
        else { $output.Insert($wsl2Index + 2, 'debugConsole=true') }
    }
    $text = [String]::Join($Document.newline, $output)
    $body = $Document.encoding.GetBytes($text)
    $preamble = $Document.encoding.GetPreamble()
    if ($Document.preambleLength -eq 0) { return $body }
    $result = New-Object byte[] ($preamble.Length + $body.Length)
    [Array]::Copy($preamble, 0, $result, 0, $preamble.Length)
    [Array]::Copy($body, 0, $result, $preamble.Length, $body.Length)
    $result
}

function Set-FileBytesAtomic([string]$Path, [byte[]]$Bytes) {
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.wslconfig.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $replaced = Join-Path $directory ('.wslconfig.' + [Guid]::NewGuid().ToString('N') + '.replaced')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temporary, $Path, $replaced, $true)
            if (Test-Path -LiteralPath $replaced) { Remove-Item -LiteralPath $replaced -Force }
        }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $replaced) { Remove-Item -LiteralPath $replaced -Force }
    }
}

function Restore-OriginalConfig($Journal) {
    if ([bool]$Journal.originalConfig.exists) {
        $backup = [string]$Journal.originalConfig.backupPath
        if ((Get-Sha256 $backup) -ne [string]$Journal.originalConfig.sha256) { throw 'Saved .wslconfig backup hash mismatch.' }
        Set-FileBytesAtomic $wslConfigPath ([IO.File]::ReadAllBytes($backup))
        if ((Get-Sha256 $wslConfigPath) -ne [string]$Journal.originalConfig.sha256) { throw '.wslconfig restoration hash mismatch.' }
    }
    elseif (Test-Path -LiteralPath $wslConfigPath) { Remove-Item -LiteralPath $wslConfigPath -Force }
}

function Join-WindowsCommandLine([string[]]$Arguments) {
    $quoted = foreach ($value in $Arguments) {
        if ($value.Length -gt 0 -and $value -notmatch '[\s"]') { $value; continue }
        $escaped = [regex]::Replace($value, '(\\*)"', '$1$1\"')
        $trailing = [regex]::Match($escaped, '(\\+)$')
        if ($trailing.Success) { $escaped += $trailing.Value }
        '"' + $escaped + '"'
    }
    $quoted -join ' '
}

function Invoke-WslProcess([string]$Distribution, [string]$Command, [int]$Timeout, [string]$LogPrefix) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Join-Path $env:SystemRoot 'System32\wsl.exe')
    $start.Arguments = Join-WindowsCommandLine @('--distribution', $Distribution, '--exec', '/bin/sh', '-c', $Command)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Failed to start wsl.exe.' }
    $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($Timeout * 1000)
    if ($timedOut) {
        & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-File -LiteralPath "$LogPrefix.taskkill.log" -Encoding utf8
        $process.WaitForExit()
    }
    [IO.File]::WriteAllText("$LogPrefix.stdout.log", $outTask.Result, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText("$LogPrefix.stderr.log", $errTask.Result, [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ exitCode = if ($timedOut) { $null } else { $process.ExitCode }; timedOut = $timedOut; stdout = "$LogPrefix.stdout.log"; stderr = "$LogPrefix.stderr.log" }
}

function Stop-WslAndConfirm([int]$Timeout = 30) {
    & wsl.exe --shutdown | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "wsl.exe --shutdown failed with exit code $LASTEXITCODE" }
    $deadline = (Get-Date).AddSeconds($Timeout)
    do {
        $vm = @(Get-Process -Name 'vmmemWSL' -ErrorAction SilentlyContinue)
        $hosts = @(Get-Process -Name 'wslhost' -ErrorAction SilentlyContinue)
        $running = (& wsl.exe --list --running --quiet 2>&1 | Out-String).Replace("`0", '')
        if ($LASTEXITCODE -ne 0) { throw "wsl.exe --list --running --quiet failed with exit code $LASTEXITCODE" }
        $names = @($running -split "`r?`n" | Where-Object { -not [String]::IsNullOrWhiteSpace($_) })
        if ($vm.Count -eq 0 -and $hosts.Count -eq 0 -and $names.Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw 'WSL did not reach a fully stopped state within the shutdown timeout.'
}

function Assert-Restored($Journal) {
    if ((Get-Sha256 $packagedKernel) -ne [string]$Journal.packagedKernel.sha256) { throw 'Packaged Microsoft kernel hash changed.' }
    $exists = Test-Path -LiteralPath $wslConfigPath -PathType Leaf
    if ($exists -ne [bool]$Journal.originalConfig.exists) { throw '.wslconfig existence changed.' }
    if ($exists -and (Get-Sha256 $wslConfigPath) -ne [string]$Journal.originalConfig.sha256) { throw '.wslconfig hash mismatch.' }
}

function Save-NewCrashFiles([string]$Destination, [datetime]$SinceUtc) {
    $source = Join-Path $env:TEMP 'wsl-crashes'
    if (-not (Test-Path -LiteralPath $source)) { return }
    $target = Join-Path $Destination 'wsl-crashes'
    foreach ($file in Get-ChildItem -LiteralPath $source -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -ge $SinceUtc }) {
        [IO.Directory]::CreateDirectory($target) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $target $file.Name)
    }
}

function Save-WindowsEvents([string]$Path, [datetime]$SinceUtc) {
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = @('System', 'Application'); StartTime = $SinceUtc } -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'WSL|Hyper-V|Host Compute|Service Control Manager' } |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, LogName, Message
        [IO.File]::WriteAllText($Path, ($events | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    }
    catch { [IO.File]::WriteAllText($Path + '.error.txt', $_.Exception.ToString(), [Text.UTF8Encoding]::new($false)) }
}

function Add-TrialLedgerRow($Values) {
    $maximumAttempts = 20
    for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
        try {
            if (-not (Test-Path -LiteralPath $TrialLedger)) { throw "Trial ledger is missing: $TrialLedger" }
            $lines = [IO.File]::ReadAllLines($TrialLedger)
            if ($lines.Count -eq 0) { throw "Trial ledger has no header: $TrialLedger" }
            $columns = @($lines[0] -split ',')
            $row = [ordered]@{}
            foreach ($column in $columns) { $row[$column] = if ($Values.Contains($column)) { $Values[$column] } else { '' } }
            $trialId = [string]$row['trial_id']
            $existing = @((Import-Csv -LiteralPath $TrialLedger) | Where-Object { $_.trial_id -eq $trialId })
            if ($existing.Count -gt 0) {
                $same = @($existing | Where-Object {
                    $_.status -eq [string]$row['status'] -and
                    $_.classification -eq [string]$row['classification'] -and
                    $_.stock_restore_verified -eq [string]$row['stock_restore_verified']
                })
                if ($same.Count -gt 0) { return }
                throw "Trial ledger already contains a conflicting row for '$trialId'."
            }
            $csv = @([pscustomobject]$row | ConvertTo-Csv -NoTypeInformation)[1]
            [IO.File]::AppendAllText($TrialLedger, $csv + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
            return
        }
        catch {
            $exception = $_.Exception
            $isIoFailure = $false
            while ($exception) {
                if ($exception -is [IO.IOException]) { $isIoFailure = $true; break }
                $exception = $exception.InnerException
            }
            if (-not $isIoFailure -or $attempt -eq $maximumAttempts) { throw }
            Start-Sleep -Milliseconds ([Math]::Min(1000, 100 + (100 * $attempt)))
        }
    }
}

function Assert-ReadyForTrial {
    if (Test-Path -LiteralPath $journalPath) {
        $active = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        throw "Unfinished kernel trial '$($active.trialId)' exists. Run this script with -Recover first."
    }
    $rows = @(Import-Csv -LiteralPath $TrialLedger)
    if ($rows.Count -gt 0) {
        $last = $rows[-1]
        if ($last.status -notin @('PASS', 'FAIL', 'RECOVERED') -or $last.stock_restore_verified -notin @('yes', 'NOT_APPLICABLE')) {
            throw "The previous trial is not terminal with verified recovery: $($last.trial_id) / $($last.status)"
        }
    }
}

function Assert-StockValidationPassed {
    $rows = @(Import-Csv -LiteralPath $TrialLedger)
    $passed = @($rows | Where-Object {
        $_.status -eq 'PASS' -and $_.stock_restore_verified -eq 'yes' -and
        ($_.classification -eq 'RECOVERY_VALIDATION' -or $_.change_group -eq 'external-stock-kernel-recovery-validation')
    })
    if ($passed.Count -eq 0) { throw 'KernelTrial is blocked until StockValidation has passed with verified stock restoration.' }
}

try {
    if ($PSCmdlet.ParameterSetName -eq 'SelfTest') {
        $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('wsl-kernel-harness-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
        try {
            $cases = @(
                [pscustomobject]@{ name = 'utf8-lf'; bytes = [Text.UTF8Encoding]::new($false).GetBytes("[wsl2]`nmemory=8GB`n`n[experimental]`ndnsTunneling=true`n"); expected = "[wsl2]`nkernel=C:/candidate/kernel`nmemory=8GB`n`n[experimental]`ndnsTunneling=true`n" },
                [pscustomobject]@{ name = 'utf8-crlf-replace'; bytes = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.UTF8Encoding]::new($true).GetBytes("[wsl2]`r`nkernel=C:/old`r`nswap=4GB`r`n"); expected = "[wsl2]`r`nkernel=C:/candidate/kernel`r`nswap=4GB`r`n" },
                [pscustomobject]@{ name = 'utf16-add-section'; bytes = [Text.UnicodeEncoding]::new($false, $true).GetPreamble() + [Text.UnicodeEncoding]::new($false, $true).GetBytes("[experimental]`r`ndnsTunneling=true`r`n"); expected = "[experimental]`r`ndnsTunneling=true`r`n`r`n[wsl2]`r`nkernel=C:/candidate/kernel" }
            )
            foreach ($case in $cases) {
                $path = Join-Path $temporaryRoot ($case.name + '.wslconfig')
                [IO.File]::WriteAllBytes($path, $case.bytes)
                $document = Read-ConfigDocument $path
                $changed = New-KernelConfigBytes $document 'C:\candidate\kernel'
                Set-FileBytesAtomic $path $changed
                $roundTrip = Read-ConfigDocument $path
                if ($roundTrip.text -ne $case.expected) { throw "Config transform self-test failed: $($case.name)" }
            }
            $absent = Read-ConfigDocument (Join-Path $temporaryRoot 'absent')
            $created = New-KernelConfigBytes $absent 'C:\candidate\kernel'
            if ([Text.Encoding]::UTF8.GetString($created) -ne "[wsl2]`r`nkernel=C:/candidate/kernel") { throw 'Absent-config self-test failed.' }
            $diagnostic = New-KernelConfigBytes $absent 'C:\candidate\kernel' $true
            if ([Text.Encoding]::UTF8.GetString($diagnostic) -ne "[wsl2]`r`nkernel=C:/candidate/kernel`r`ndebugConsole=true") { throw 'Diagnostic-config self-test failed.' }
            $existingDebugPath = Join-Path $temporaryRoot 'existing-debug.wslconfig'
            [IO.File]::WriteAllText($existingDebugPath, "[wsl2]`r`ndebugConsole=false`r`nmemory=8GB`r`n", [Text.UTF8Encoding]::new($false))
            $existingDebug = Read-ConfigDocument $existingDebugPath
            $changedDebug = New-KernelConfigBytes $existingDebug 'C:\candidate\kernel' $true
            if ([Text.Encoding]::UTF8.GetString($changedDebug) -ne "[wsl2]`r`nkernel=C:/candidate/kernel`r`ndebugConsole=true`r`nmemory=8GB`r`n") { throw 'Existing debugConsole transform self-test failed.' }

            $savedTrialLedger = $TrialLedger
            try {
                $script:TrialLedger = Join-Path $temporaryRoot 'ledger.csv'
                [IO.File]::WriteAllText($TrialLedger, "trial_id,status,classification,stock_restore_verified,kernel_image_sha256`r`n", [Text.UTF8Encoding]::new($false))
                $testRow = [ordered]@{ trial_id = 'SELFTEST'; status = 'PASS'; classification = 'TEST'; stock_restore_verified = 'yes'; kernel_image_sha256 = 'abc' }
                Add-TrialLedgerRow $testRow
                Add-TrialLedgerRow $testRow
                if (@(Import-Csv -LiteralPath $TrialLedger).Count -ne 1) { throw 'Ledger idempotence self-test failed.' }

                $script:TrialLedger = Join-Path $temporaryRoot 'locked-ledger.csv'
                $readyPath = Join-Path $temporaryRoot 'ledger-lock-ready'
                [IO.File]::WriteAllText($TrialLedger, "trial_id,status,classification,stock_restore_verified,kernel_image_sha256`r`n", [Text.UTF8Encoding]::new($false))
                $lockJob = Start-Job -ArgumentList $TrialLedger, $readyPath -ScriptBlock {
                    param($Path, $ReadyPath)
                    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                    try {
                        [IO.File]::WriteAllText($ReadyPath, 'ready')
                        Start-Sleep -Milliseconds 1500
                    }
                    finally { $stream.Dispose() }
                }
                try {
                    $deadline = (Get-Date).AddSeconds(10)
                    while (-not (Test-Path -LiteralPath $readyPath) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
                    if (-not (Test-Path -LiteralPath $readyPath)) { throw 'Ledger lock self-test did not acquire its lock.' }
                    Add-TrialLedgerRow $testRow
                    if (@(Import-Csv -LiteralPath $TrialLedger).Count -ne 1) { throw 'Ledger lock-retry self-test failed.' }
                }
                finally {
                    Wait-Job -Job $lockJob -Timeout 5 | Out-Null
                    Remove-Job -Job $lockJob -Force -ErrorAction SilentlyContinue
                }
            }
            finally { $script:TrialLedger = $savedTrialLedger }
            Write-Host 'WslKernelTrial isolated config-transform and ledger tests: PASS'
        }
        finally { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
        exit 0
    }

    if ($PSCmdlet.ParameterSetName -eq 'Recover') {
        Enter-TrialMutex
        if (-not (Test-Path -LiteralPath $journalPath)) { throw "No active kernel-trial journal exists at $journalPath" }
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        Assert-NoWslManagementOperation
        Stop-WslAndConfirm
        Restore-OriginalConfig $journal
        Stop-WslAndConfirm
        Assert-Restored $journal
        $recovery = Invoke-WslProcess ([string]$journal.recoveryDistribution) 'printf __WSL_STOCK_RECOVERY_OK__; uname -r' ([int]$journal.timeoutSeconds) (Join-Path ([string]$journal.trialDirectory) 'manual-stock-recovery')
        if ($recovery.timedOut -or $recovery.exitCode -ne 0) { throw 'Stock recovery distribution did not start successfully.' }
        Stop-WslAndConfirm
        $resultPath = Join-Path ([string]$journal.trialDirectory) 'result.json'
        $completed = if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json } else { $null }
        if ($completed -and $completed.status -eq 'PASS' -and $completed.stockRestoreVerified -eq $true -and $completed.stockBootVerified -eq $true) {
            $isStockValidation = [string]$journal.mode -eq 'StockValidation'
            Add-TrialLedgerRow ([ordered]@{
                trial_id = $journal.trialId; status = 'PASS'; started_utc = $completed.startedUtc; finished_utc = $completed.finishedUtc
                change_group = if ($isStockValidation) { 'external-stock-kernel-recovery-validation' } else { 'external-custom-kernel' }
                kernel_image_path = $journal.candidateKernel.path; kernel_image_sha256 = $journal.candidateKernel.sha256
                classification = if ($isStockValidation) { 'RECOVERY_VALIDATION' } else { 'UNRESOLVED' }
                stock_restore_verified = 'yes'; notes = 'Ledger finalization recovered from completed PASS result; packaged kernel and original .wslconfig reverified; stock distro boot passed again'
            })
            $message = "Finalized completed PASS trial '$($journal.trialId)' and reverified stock startup."
        }
        else {
            Add-TrialLedgerRow ([ordered]@{ trial_id = $journal.trialId; status = 'RECOVERED'; started_utc = $journal.startedUtc; finished_utc = (Get-Date).ToUniversalTime().ToString('o'); kernel_image_path = $journal.candidateKernel.path; kernel_image_sha256 = $journal.candidateKernel.sha256; classification = 'RECOVERY'; stock_restore_verified = 'yes'; notes = 'Manual journal recovery; packaged kernel and original .wslconfig verified; stock distro boot passed' })
            $message = "Recovered '$($journal.trialId)' and verified stock startup."
        }
        Remove-Item -LiteralPath $journalPath -Force
        Write-Host $message
        exit 0
    }

    Assert-ReadyForTrial
    $candidatePath = (Resolve-Path -LiteralPath $CandidateKernel).Path
    Assert-ExternalCandidate $candidatePath
    $candidate = Test-LinuxBootKernel $candidatePath
    $stock = Get-FileEvidence $packagedKernel
    $wslVersion = Get-WslText @('--version')
    Assert-DistributionExists $TestDistribution
    Assert-DistributionExists $RecoveryDistribution
    $config = Read-ConfigDocument $wslConfigPath
    if ($Mode -eq 'StockValidation') {
        if ($AllowCustomKernel) { throw 'StockValidation refuses -AllowCustomKernel.' }
        if ($candidate.sha256 -ne $stock.sha256) { throw 'StockValidation candidate is not byte-identical to the packaged Microsoft kernel.' }
    }
    elseif (-not $AllowCustomKernel) { throw 'KernelTrial requires the explicit -AllowCustomKernel switch.' }
    if ($Mode -eq 'KernelTrial') { Assert-StockValidationPassed }
    if ($Mode -eq 'KernelTrial' -and ([String]::IsNullOrWhiteSpace($SourceCommit) -or [String]::IsNullOrWhiteSpace($Toolchain) -or [String]::IsNullOrWhiteSpace($KernelConfigPath))) {
        throw 'KernelTrial requires SourceCommit, Toolchain, and KernelConfigPath metadata.'
    }
    if ($KernelConfigPath) { $null = Get-FileEvidence ((Resolve-Path -LiteralPath $KernelConfigPath).Path) }

    $plan = [ordered]@{
        mode = $Mode; trialId = $TrialId; execute = [bool]$Execute
        requiresElevation = $false
        candidateKernel = $candidate; packagedKernel = $stock; wslVersion = $wslVersion
        originalWslConfig = [ordered]@{ exists = $config.exists; length = $config.bytes.Length; sha256 = if ($config.exists) { Get-Sha256 $wslConfigPath } else { $null } }
        testDistribution = $TestDistribution; recoveryDistribution = $RecoveryDistribution; timeoutSeconds = $TimeoutSeconds
        debugConsole = [bool]$EnableDebugConsole
        activeWslProcesses = @(Get-Process -Name 'vmmemWSL', 'wslhost' -ErrorAction SilentlyContinue | Select-Object Name, Id)
        blockingWslManagementProcesses = @(Get-BlockingWslManagementProcesses)
        writesUnderInstalledWsl = $false
        operations = @('validate external kernel', 'save exact .wslconfig', $(if ($EnableDebugConsole) { 'atomically select external kernel and debugConsole=true in .wslconfig' } else { 'atomically select external kernel in .wslconfig' }), 'shutdown WSL', 'run designated distro with timeout', 'unconditionally restore exact .wslconfig', 'shutdown and verify packaged-kernel/config hashes', 'boot stock recovery distro', 'shutdown and append terminal trial row')
    }
    $plan | ConvertTo-Json -Depth 10
    if (-not $Execute) { Write-Host 'PLAN ONLY: no shutdown or configuration change was performed.'; exit 0 }

    Enter-TrialMutex
    Assert-ReadyForTrial
    Assert-NoWslManagementOperation
    $trialDirectory = Join-Path $StateRoot ('trials\' + $TrialId)
    if (Test-Path -LiteralPath $trialDirectory) { throw "Trial output already exists: $trialDirectory" }
    [IO.Directory]::CreateDirectory($trialDirectory) | Out-Null
    $started = (Get-Date).ToUniversalTime()
    $configBackup = Join-Path $trialDirectory 'original.wslconfig'
    if ($config.exists) { [IO.File]::WriteAllBytes($configBackup, $config.bytes) }
    $journal = [ordered]@{
        schemaVersion = 1; trialId = $TrialId; mode = $Mode; phase = 'PREPARED'; startedUtc = $started.ToString('o')
        packagedKernel = $stock; candidateKernel = $candidate; wslVersion = $wslVersion; debugConsoleEnabled = [bool]$EnableDebugConsole
        originalConfig = [ordered]@{ exists = $config.exists; backupPath = if ($config.exists) { $configBackup } else { $null }; sha256 = if ($config.exists) { Get-Sha256 $configBackup } else { $null } }
        recoveryDistribution = $RecoveryDistribution; timeoutSeconds = $TimeoutSeconds; trialDirectory = $trialDirectory
    }
    Write-JsonFileAtomic $journalPath $journal
    $testResult = $null; $kernelLogResult = $null; $primaryError = $null; $restoreError = $null; $restored = $false; $stockBoot = $false
    try {
        $candidateBytes = New-KernelConfigBytes $config $candidatePath ([bool]$EnableDebugConsole)
        Set-FileBytesAtomic $wslConfigPath $candidateBytes
        $journal.phase = 'KERNEL_SELECTED'; Write-JsonFileAtomic $journalPath $journal
        Stop-WslAndConfirm
        $testResult = Invoke-WslProcess $TestDistribution $TestCommand $TimeoutSeconds (Join-Path $trialDirectory 'test-boot')
        if ($testResult.timedOut) { throw "Test distro exceeded the $TimeoutSeconds-second timeout." }
        if ($testResult.exitCode -ne 0) { throw "Test distro exited with code $($testResult.exitCode)." }
        # Best-effort kernel-ring capture from the same designated distro. A
        # missing dmesg applet or permission failure is logged but does not
        # redefine an otherwise successful boot checkpoint.
        try {
            $kernelLogResult = Invoke-WslProcess $TestDistribution 'dmesg' ([Math]::Min($TimeoutSeconds, 15)) (Join-Path $trialDirectory 'kernel-dmesg')
        }
        catch {
            [IO.File]::WriteAllText((Join-Path $trialDirectory 'kernel-dmesg.capture-error.txt'), $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
        }
    }
    catch { $primaryError = $_ }
    finally {
        try {
            Stop-WslAndConfirm
            Restore-OriginalConfig $journal
            Stop-WslAndConfirm
            Assert-Restored $journal
            $restored = $true
        }
        catch { $restoreError = $_ }
    }
    Save-NewCrashFiles $trialDirectory $started
    Save-WindowsEvents (Join-Path $trialDirectory 'windows-events.json') $started
    if ($restored) {
        try {
            $recovery = Invoke-WslProcess $RecoveryDistribution 'printf __WSL_STOCK_RECOVERY_OK__; uname -r' $TimeoutSeconds (Join-Path $trialDirectory 'stock-recovery')
            if ($recovery.timedOut -or $recovery.exitCode -ne 0) { throw 'Stock recovery distribution did not start successfully.' }
            $stockBoot = $true
        }
        catch { if (-not $primaryError) { $primaryError = $_ } }
        finally { try { Stop-WslAndConfirm } catch { if (-not $restoreError) { $restoreError = $_ } } }
    }
    $status = if ($restoreError) { 'RESTORE_FAILED' } elseif ($primaryError -or -not $stockBoot) { 'FAIL' } else { 'PASS' }
    $finished = (Get-Date).ToUniversalTime().ToString('o')
    $record = [ordered]@{
        trialId = $TrialId; status = $status; startedUtc = $started.ToString('o'); finishedUtc = $finished
        candidateKernel = $candidate; packagedKernel = $stock; wslVersion = $wslVersion; debugConsoleEnabled = [bool]$EnableDebugConsole; testResult = $testResult; kernelLogResult = $kernelLogResult
        stockRestoreVerified = $restored; stockBootVerified = $stockBoot
        primaryError = if ($primaryError) { $primaryError.Exception.ToString() } else { $null }
        restoreError = if ($restoreError) { $restoreError.Exception.ToString() } else { $null }
    }
    Write-JsonFileAtomic (Join-Path $trialDirectory 'result.json') $record
    Add-TrialLedgerRow ([ordered]@{
        trial_id = $TrialId; status = $status; started_utc = $started.ToString('o'); finished_utc = $finished
        source_commit = $SourceCommit; toolchain = $Toolchain; kernel_config_path = $KernelConfigPath
        kernel_config_sha256 = if ($KernelConfigPath) { Get-Sha256 ((Resolve-Path -LiteralPath $KernelConfigPath).Path) } else { '' }
        change_group = if ($Mode -eq 'StockValidation') { 'external-stock-kernel-recovery-validation' } else { 'external-custom-kernel' }
        kernel_image_path = $candidate.path; kernel_image_sha256 = $candidate.sha256
        boot_level = if (-not $primaryError -and $TestDistribution -eq 'Toybox-Minimal') { 'B6-T' } else { '' }
        toybox_result = if ($TestDistribution -eq 'Toybox-Minimal') { if ($testResult -and -not $testResult.timedOut -and $testResult.exitCode -eq 0) { 'PASS' } else { 'FAIL' } } else { 'NOT_TESTED' }
        alpine_result = 'NOT_TESTED'; failure_signature = if ($primaryError) { $primaryError.Exception.Message } else { '' }
        windows_error = if ($primaryError) { $primaryError.Exception.Message } else { '' }
        kernel_log_path = (Join-Path $trialDirectory 'kernel-dmesg.stdout.log'); crash_log_path = (Join-Path $trialDirectory 'wsl-crashes')
        classification = if ($Mode -eq 'StockValidation') { 'RECOVERY_VALIDATION' } else { 'UNRESOLVED' }
        stock_restore_verified = if ($restored -and $stockBoot) { 'yes' } else { 'no' }
        notes = "Mode=$Mode; debugConsole=$([bool]$EnableDebugConsole); recovery distro=$RecoveryDistribution; logs=$trialDirectory"
    })
    if ($restored -and -not $restoreError) { Remove-Item -LiteralPath $journalPath -Force }
    if ($restoreError) { throw "RESTORATION FAILED. Run -Recover before starting WSL: $($restoreError.Exception.Message)" }
    if ($primaryError) { throw "Trial failed after verified restoration: $($primaryError.Exception.Message)" }
    if (-not $stockBoot) { throw 'Stock startup was not verified.' }
    Write-Host "Trial '$TrialId' passed and stock operation was verified."
}
finally { Exit-TrialMutex }
