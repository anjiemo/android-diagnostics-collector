[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $OutputEncoding
$script:ToolVersion = "1.1.0"
$script:ToolRoot = $PSScriptRoot
$script:RuntimeRoot = Join-Path $script:ToolRoot "_runtime"
$script:ResultsRoot = Join-Path $script:ToolRoot "results"
$script:ConfigPath = Join-Path $script:ToolRoot "adb.config"
$script:AdbPath = $null
$script:Serial = $null
$script:LogcatProcess = $null
$script:ScreenRecordingEnabled = $false
$script:ScreenRecordProcess = $null
$script:ScreenRecordDevicePath = ""
$script:ScreenRecordExistingPids = @()
$script:ScreenRecordPids = @()
$script:ScreenRecordDirectory = ""
$script:ScreenRecordStarted = $false
$script:ScreenRecordFinalized = $false
$script:ScreenRecordResult = "未采集"
$script:ScreenRecordFileName = "无"
$script:ScreenRecordStartTime = $null
$script:ScreenRecordStopTime = $null
$script:ScreenRecordSummaryWritten = $false
$script:InlineProgressActive = $false
$script:InlineProgressLastLength = 0
$script:InlineProgressLastUpdate = [DateTime]::MinValue

function Write-Step {
    param([string]$Message)
    Clear-InlineProgress
    Write-Host ""
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message) -ForegroundColor Cyan
}

function Get-ProgressConsoleWidth {
    try {
        return [Math]::Max(40, [Console]::WindowWidth - 1)
    }
    catch {
        return 100
    }
}

function Get-TextDisplayWidth {
    param([string]$Text)

    $width = 0
    foreach ($character in $Text.ToCharArray()) {
        if ([int]$character -gt 255) {
            $width += 2
        }
        else {
            $width++
        }
    }
    return $width
}

function Limit-TextToDisplayWidth {
    param(
        [string]$Text,
        [int]$MaxWidth
    )

    if ((Get-TextDisplayWidth -Text $Text) -le $MaxWidth) {
        return $Text
    }

    $targetWidth = [Math]::Max(1, $MaxWidth - 3)
    $builder = New-Object System.Text.StringBuilder
    $currentWidth = 0
    foreach ($character in $Text.ToCharArray()) {
        $characterWidth = if ([int]$character -gt 255) { 2 } else { 1 }
        if (($currentWidth + $characterWidth) -gt $targetWidth) {
            break
        }
        [void]$builder.Append($character)
        $currentWidth += $characterWidth
    }
    return $builder.ToString() + "..."
}

function Write-InlineProgress {
    param(
        [string]$Activity,
        [string]$Status = "",
        [string]$CurrentOperation = "",
        [int]$PercentComplete = 0,
        [switch]$Force
    )

    $now = Get-Date
    if (-not $Force -and (($now - $script:InlineProgressLastUpdate).TotalMilliseconds -lt 500)) {
        return
    }

    $percent = [Math]::Max(0, [Math]::Min(100, $PercentComplete))
    $consoleWidth = Get-ProgressConsoleWidth
    $barWidth = [Math]::Min(20, [Math]::Max(8, [int]($consoleWidth / 4)))
    $filledWidth = [Math]::Min($barWidth, [int][Math]::Floor(($percent * $barWidth) / 100))
    $bar = ("#" * $filledWidth) + ("-" * ($barWidth - $filledWidth))
    $line = "[{0}] {1,3}% {2}" -f $bar, $percent, $Activity

    if (-not [string]::IsNullOrWhiteSpace($CurrentOperation)) {
        $line += " | " + ($CurrentOperation -replace "[\r\n]+", " ")
    }
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $line += " | " + ($Status -replace "[\r\n]+", " ")
    }

    $line = Limit-TextToDisplayWidth -Text $line -MaxWidth ([Math]::Max(20, $consoleWidth - 2))

    $paddingLength = [Math]::Max(0, $script:InlineProgressLastLength - $line.Length)
    try {
        [Console]::Write("`r" + $line + (" " * $paddingLength))
    }
    catch {
        Write-Host -NoNewline ("`r" + $line + (" " * $paddingLength))
    }

    $script:InlineProgressActive = $true
    $script:InlineProgressLastLength = $line.Length
    $script:InlineProgressLastUpdate = $now
}

function Clear-InlineProgress {
    if (-not $script:InlineProgressActive) {
        return
    }

    $clearWidth = Get-ProgressConsoleWidth
    try {
        [Console]::Write("`r" + (" " * $clearWidth) + "`r")
    }
    catch {
        Write-Host -NoNewline ("`r" + (" " * $clearWidth) + "`r")
    }

    $script:InlineProgressActive = $false
    $script:InlineProgressLastLength = 0
    $script:InlineProgressLastUpdate = [DateTime]::MinValue
}

function Wait-ProcessWithProgress {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Activity,
        [string]$CurrentOperation,
        [int]$ProgressId = 1
    )

    $startedAt = Get-Date
    $progressWasShown = $false
    try {
        while (-not $Process.WaitForExit(250)) {
            $elapsed = (Get-Date) - $startedAt
            if ($elapsed.TotalSeconds -lt 1) {
                continue
            }
            $pulse = [Math]::Min(95, 5 + [int]($elapsed.TotalSeconds * 2))
            $status = "正在执行，已耗时 {0} 秒" -f [int]$elapsed.TotalSeconds
            Write-InlineProgress -Activity $Activity -Status $status -CurrentOperation $CurrentOperation -PercentComplete $pulse -Force:(-not $progressWasShown)
            $progressWasShown = $true
        }
        $Process.WaitForExit()
        return $Process.ExitCode
    }
    finally {
        if ($progressWasShown) {
            Clear-InlineProgress
        }
    }
}

function Invoke-TaskSequence {
    param(
        [object[]]$Tasks,
        [string]$Activity,
        [int]$ProgressId = 1
    )

    try {
        for ($index = 0; $index -lt $Tasks.Count; $index++) {
            $task = $Tasks[$index]
            $percent = if ($Tasks.Count -eq 0) { 100 } else { [int](($index * 100) / $Tasks.Count) }
            $status = "第 {0}/{1} 项" -f ($index + 1), $Tasks.Count
            Write-InlineProgress -Activity $Activity -Status $status -CurrentOperation $task.Name -PercentComplete $percent
            $action = $task.Action
            & $action
        }
    }
    finally {
        Clear-InlineProgress
    }
}

function Invoke-FileDownloadWithProgress {
    param(
        [string]$Uri,
        [string]$DestinationPath
    )

    $progressId = 10
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        $connectStartedAt = Get-Date
        Write-InlineProgress -Activity "正在下载 ADB" -Status "正在连接下载服务器……" -PercentComplete 0 -Force
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.UserAgent = "Android-Log-Collector/$($script:ToolVersion)"
        $responseTask = $request.GetResponseAsync()
        while (-not $responseTask.Wait(250)) {
            $elapsed = (Get-Date) - $connectStartedAt
            $connectPercent = [Math]::Min(15, [int]$elapsed.TotalSeconds + 1)
            Write-InlineProgress -Activity "正在下载 ADB" -Status ("正在连接下载服务器，已耗时 {0} 秒" -f [int]$elapsed.TotalSeconds) -PercentComplete $connectPercent
        }
        $response = $responseTask.GetAwaiter().GetResult()
        $totalBytes = [long]$response.ContentLength
        $inputStream = $response.GetResponseStream()
        $outputStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 1024)
        $downloadedBytes = [long]0
        $lastUpdate = [DateTime]::MinValue

        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
            $downloadedBytes += $read
            if (((Get-Date) - $lastUpdate).TotalMilliseconds -ge 150) {
                if ($totalBytes -gt 0) {
                    $percent = [Math]::Min(100, [int](($downloadedBytes * 100) / $totalBytes))
                    $status = "已下载 {0:N1} MB / {1:N1} MB" -f ($downloadedBytes / 1MB), ($totalBytes / 1MB)
                }
                else {
                    $percent = 50
                    $status = "已下载 {0:N1} MB" -f ($downloadedBytes / 1MB)
                }
                Write-InlineProgress -Activity "正在下载 ADB" -Status $status -PercentComplete $percent
                $lastUpdate = Get-Date
            }
        }
    }
    finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        Clear-InlineProgress
    }
}

function Expand-ZipWithProgress {
    param(
        [string]$ZipPath,
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    $destinationRoot = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd('\') + '\'
    $archive = $null
    $progressId = 11
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $entries = @($archive.Entries)
        for ($index = 0; $index -lt $entries.Count; $index++) {
            $entry = $entries[$index]
            $targetPath = [System.IO.Path]::GetFullPath((Join-Path $DestinationPath $entry.FullName))
            if (-not $targetPath.StartsWith($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw ("压缩包包含不安全路径：{0}" -f $entry.FullName)
            }

            $percent = if ($entries.Count -eq 0) { 100 } else { [int]((($index + 1) * 100) / $entries.Count) }
            Write-InlineProgress -Activity "正在安装 ADB" -Status ("正在解压：{0}" -f $entry.FullName) -PercentComplete $percent

            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                continue
            }

            $parentPath = [System.IO.Path]::GetDirectoryName($targetPath)
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
            $entryStream = $null
            $fileStream = $null
            try {
                $entryStream = $entry.Open()
                $fileStream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $entryStream.CopyTo($fileStream)
            }
            finally {
                if ($null -ne $fileStream) { $fileStream.Dispose() }
                if ($null -ne $entryStream) { $entryStream.Dispose() }
            }
        }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        Clear-InlineProgress
    }
}

function Write-Utf8Lines {
    param(
        [string]$Path,
        [object[]]$Lines
    )

    $encoding = New-Object System.Text.UTF8Encoding($true)
    $textLines = @($Lines | ForEach-Object { [string]$_ })
    [System.IO.File]::WriteAllLines($Path, $textLines, $encoding)
}

function Write-ResultGuide {
    param([string]$Directory)

    Write-Utf8Lines -Path (Join-Path $Directory "日志文件说明.txt") -Lines @(
        "Android 日志采集结果说明",
        "",
        "采集摘要.txt：设备、应用包名、采集时间、应用 PID 及录屏结果。",
        "logcat-all.txt：从采集开始持续记录的完整 Android 运行日志，普通问题优先查看此文件。",
        "logcat-snapshot.txt：确认问题现场时导出的 Logcat 快照。",
        "screen-at-problem.png：确认问题现场时的设备截图。",
        "screen-recording.mp4：选择启用录屏时保存的设备画面；Android 原生录屏通常最长 180 秒且不含音频。",
        "activity-top.txt：当前前台 Activity 及相关状态。",
        "window.txt：当前窗口、焦点和界面层级状态。",
        "input.txt：输入事件及触摸分发状态。",
        "cpuinfo.txt、top-threads.txt：CPU 和线程占用情况。",
        "meminfo-all.txt、app-meminfo.txt：系统和目标应用的内存信息。",
        "app-exit-info.txt：目标应用的历史退出原因。",
        "activity-lastranr.txt、dropbox-*-anr.txt：系统保存的 ANR 信息。",
        "native-backtrace-*.txt：目标应用进程的 native 线程快照。",
        "bugreport.zip：完整 Android 系统诊断包。",
        "*.stderr.txt：对应采集命令的错误信息；文件不存在通常表示该命令执行正常。",
        "",
        "说明：Android 原始日志和异常堆栈通常使用英文，这是系统和应用直接产生的诊断数据。"
    )
}

function Confirm-ScreenRecording {
    Write-Host ""
    Write-Host "可选功能：录制复现过程中的设备画面。" -ForegroundColor Cyan
    Write-Host "Android 原生录屏通常最长 180 秒，不包含设备音频。"
    Write-Host "录屏达到时长上限后会自动结束，Logcat 仍会继续采集。"

    while ($true) {
        $answer = (Read-Host "是否同时录制设备屏幕？[Y/是，N/否，默认 N]").Trim()
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match "^[Nn否]$") {
            return $false
        }
        if ($answer -match "^[Yy是]$") {
            return $true
        }
        Write-Host "请输入 Y 或 N，直接按回车表示不录屏。" -ForegroundColor Red
    }
}

function Get-ConfiguredAdbPath {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        return ""
    }

    foreach ($rawLine in (Get-Content -LiteralPath $script:ConfigPath)) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#") -or $line.StartsWith(";")) {
            continue
        }

        if ($line -match "^ADB_PATH\s*=\s*(.*)$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }

    return ""
}

function Resolve-ConfiguredAdb {
    param([string]$ConfiguredPath)

    if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return ""
    }

    $candidate = [Environment]::ExpandEnvironmentVariables($ConfiguredPath)
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $script:ToolRoot $candidate
    }

    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $candidate = Join-Path $candidate "adb.exe"
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw ("adb.config 中的 ADB_PATH 未指向有效的 adb.exe：{0}" -f $candidate)
    }

    return (Resolve-Path -LiteralPath $candidate).Path
}

function Confirm-AdbDownload {
    Write-Host ""
    Write-Host "未在 adb.config、系统 PATH 环境变量或工具运行目录中找到 ADB。" -ForegroundColor Yellow
    Write-Host "如果电脑中已有 ADB，请关闭工具，并在 adb.config 中设置 ADB_PATH。"
    Write-Host ""

    while ($true) {
        $answer = Read-Host "是否立即下载并安装 Google 官方 Android platform-tools？[Y/是，N/否]"
        if ($answer -match "^[Yy是]$") {
            return $true
        }
        if ($answer -match "^[Nn否]$") {
            return $false
        }
        Write-Host "请输入 Y 或 N。" -ForegroundColor Red
    }
}

function Resolve-Adb {
    $configuredPath = Get-ConfiguredAdbPath
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        return Resolve-ConfiguredAdb -ConfiguredPath $configuredPath
    }

    $pathAdb = Get-Command "adb.exe" -ErrorAction SilentlyContinue
    if ($null -ne $pathAdb) {
        return $pathAdb.Source
    }

    $runtimeAdb = Join-Path $script:RuntimeRoot "platform-tools\adb.exe"
    if (Test-Path -LiteralPath $runtimeAdb -PathType Leaf) {
        return $runtimeAdb
    }

    if (-not (Confirm-AdbDownload)) {
        throw "已取消安装 ADB。请在 adb.config 中设置 ADB_PATH，或将 adb.exe 添加到系统 PATH 环境变量后重新运行。"
    }

    Write-Step "正在下载 Google 官方 Android platform-tools"
    New-Item -ItemType Directory -Path $script:RuntimeRoot -Force | Out-Null

    $downloadUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    $downloadFile = Join-Path $script:RuntimeRoot "platform-tools-latest-windows.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-FileDownloadWithProgress -Uri $downloadUrl -DestinationPath $downloadFile
        Expand-ZipWithProgress -ZipPath $downloadFile -DestinationPath $script:RuntimeRoot
    }
    catch {
        throw ("ADB 下载失败。请检查网络，或将官方 platform-tools 文件夹放到工具目录中。详细错误：{0}" -f $_.Exception.Message)
    }

    $downloadedAdb = Join-Path $script:RuntimeRoot "platform-tools\adb.exe"
    if (-not (Test-Path -LiteralPath $downloadedAdb -PathType Leaf)) {
        throw "platform-tools 已下载，但未找到 adb.exe。"
    }

    return $downloadedAdb
}

function Get-ConnectedDevices {
    $rawLines = @(& $script:AdbPath devices 2>&1)
    $devices = @()

    foreach ($line in $rawLines) {
        if ([string]$line -match "^([^\s]+)\s+device$") {
            $devices += $Matches[1]
        }
    }

    return ,$devices
}

function Select-Device {
    while ($true) {
        & $script:AdbPath start-server | Out-Null
        $rawLines = @(& $script:AdbPath devices 2>&1)
        $devices = @(Get-ConnectedDevices)

        if ($devices.Count -eq 1) {
            return $devices[0]
        }

        if ($devices.Count -gt 1) {
            Write-Host "发现多台已授权设备：" -ForegroundColor Yellow
            for ($index = 0; $index -lt $devices.Count; $index++) {
                Write-Host ("  {0}. {1}" -f ($index + 1), $devices[$index])
            }

            $choice = Read-Host "请输入要采集的设备序号"
            $selectedIndex = 0
            if ([int]::TryParse($choice, [ref]$selectedIndex)) {
                $selectedIndex--
                if ($selectedIndex -ge 0 -and $selectedIndex -lt $devices.Count) {
                    return $devices[$selectedIndex]
                }
            }

            Write-Host "输入的设备序号无效。" -ForegroundColor Red
            continue
        }

        Write-Host "未发现已授权的 Android 设备。" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "请检查 USB 数据线、开启 USB 调试，并在手机上允许当前电脑进行调试。"
        Write-Host "如果设备状态为 unauthorized，请解锁手机并确认 USB 调试授权。"
        $retry = Read-Host "按回车重试，输入 Q 退出"
        if ($retry -match "^[Qq]$") {
            throw "未连接已授权设备。"
        }
    }
}

function Invoke-AdbSnapshot {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$Directory,
        [string]$ProgressMessage = ""
    )

    $outputPath = Join-Path $Directory $Name
    $errorPath = Join-Path $Directory ($Name + ".stderr.txt")
    $allArguments = @("-s", $script:Serial) + $Arguments

    try {
        $process = Start-Process `
            -FilePath $script:AdbPath `
            -ArgumentList $allArguments `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $outputPath `
            -RedirectStandardError $errorPath

        $operation = if ([string]::IsNullOrWhiteSpace($ProgressMessage)) { $Name } else { $ProgressMessage }
        $exitCode = Wait-ProcessWithProgress `
            -Process $process `
            -Activity "正在采集诊断信息" `
            -CurrentOperation $operation `
            -ProgressId 2

        if ((Test-Path -LiteralPath $errorPath) -and ((Get-Item -LiteralPath $errorPath).Length -eq 0)) {
            Remove-Item -LiteralPath $errorPath -Force
        }

        return $exitCode
    }
    catch {
        Write-Utf8Lines -Path $errorPath -Lines @($_.Exception.ToString())
        return -1
    }
}

function Get-FocusedPackage {
    $windowLines = @(& $script:AdbPath -s $script:Serial shell dumpsys window 2>$null)
    foreach ($line in $windowLines) {
        if ([string]$line -match "mCurrentFocus=.*\s([A-Za-z0-9._]+)/[A-Za-z0-9._$]+") {
            return $Matches[1]
        }
    }
    foreach ($line in $windowLines) {
        if ([string]$line -match "mFocusedApp=.*\s([A-Za-z0-9._]+)/[A-Za-z0-9._$]+") {
            return $Matches[1]
        }
    }
    return ""
}

function Get-PackagePids {
    param([string]$PackageName)

    if ([string]::IsNullOrWhiteSpace($PackageName)) {
        return @()
    }

    $pidText = (& $script:AdbPath -s $script:Serial shell pidof $PackageName 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($pidText)) {
        return @()
    }

    return @($pidText -split "\s+" | Where-Object { $_ -match "^\d+$" })
}

function Start-ContinuousLogcat {
    param([string]$Directory)

    $logPath = Join-Path $Directory "logcat-all.txt"
    $errorPath = Join-Path $Directory "logcat-all.stderr.txt"
    $arguments = @("-s", $script:Serial, "logcat", "-b", "all", "-v", "threadtime", "*:V")

    $script:LogcatProcess = Start-Process `
        -FilePath $script:AdbPath `
        -ArgumentList $arguments `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $logPath `
        -RedirectStandardError $errorPath
}

function Stop-ContinuousLogcat {
    if ($null -eq $script:LogcatProcess) {
        return
    }

    try {
        if (-not $script:LogcatProcess.HasExited) {
            Stop-Process -Id $script:LogcatProcess.Id -Force -ErrorAction SilentlyContinue
            $script:LogcatProcess.WaitForExit(5000) | Out-Null
        }
    }
    finally {
        $script:LogcatProcess = $null
    }
}

function Get-ScreenRecordPids {
    $pidText = (& $script:AdbPath -s $script:Serial shell pidof screenrecord 2>$null | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($pidText)) {
        return @($pidText -split "\s+" | Where-Object { $_ -match "^\d+$" })
    }

    $processLines = @(& $script:AdbPath -s $script:Serial shell ps -A 2>$null)
    if ($processLines.Count -eq 0) {
        $processLines = @(& $script:AdbPath -s $script:Serial shell ps 2>$null)
    }
    $pids = @()
    foreach ($line in $processLines) {
        if ([string]$line -match "^\S+\s+(\d+)\s+.*\bscreenrecord\s*$") {
            $pids += $Matches[1]
        }
    }
    return @($pids)
}

function Add-ScreenRecordingSummary {
    if ($script:ScreenRecordSummaryWritten -or [string]::IsNullOrWhiteSpace($script:ScreenRecordDirectory)) {
        return
    }

    $summaryPath = Join-Path $script:ScreenRecordDirectory "采集摘要.txt"
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        return
    }

    try {
        $startText = if ($null -eq $script:ScreenRecordStartTime) { "无" } else { $script:ScreenRecordStartTime.ToString("yyyy-MM-dd HH:mm:ss.fff") }
        $stopText = if ($null -eq $script:ScreenRecordStopTime) { "无" } else { $script:ScreenRecordStopTime.ToString("yyyy-MM-dd HH:mm:ss.fff") }
        Add-Content -LiteralPath $summaryPath -Encoding UTF8 -Value @(
            ("录屏开始时间：{0}" -f $startText),
            ("录屏结束时间：{0}" -f $stopText),
            ("录屏结果：{0}" -f $script:ScreenRecordResult),
            ("录屏文件：{0}" -f $script:ScreenRecordFileName)
        )
        $script:ScreenRecordSummaryWritten = $true
    }
    catch {
        Write-Host ("录屏结果未能写入采集摘要，其他日志采集不受影响。原因：{0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Start-ScreenRecording {
    param([string]$Directory)

    $script:ScreenRecordDirectory = $Directory
    $script:ScreenRecordDevicePath = "/sdcard/android_log_record_{0}.mp4" -f (Get-Date -Format "yyyyMMdd_HHmmss")
    $script:ScreenRecordPids = @()
    $script:ScreenRecordStarted = $false
    $script:ScreenRecordFinalized = $false
    $script:ScreenRecordResult = "正在录制"
    $script:ScreenRecordFileName = "无"
    $script:ScreenRecordStartTime = Get-Date

    $script:ScreenRecordExistingPids = @(Get-ScreenRecordPids)
    $outputPath = Join-Path $Directory "screen-recording-command.txt"
    $errorPath = Join-Path $Directory "screen-recording-command.stderr.txt"
    $arguments = @(
        "-s", $script:Serial,
        "shell", "screenrecord",
        "--bit-rate", "6000000",
        "--time-limit", "180",
        $script:ScreenRecordDevicePath
    )

    try {
        $script:ScreenRecordProcess = Start-Process `
            -FilePath $script:AdbPath `
            -ArgumentList $arguments `
            -WindowStyle Hidden `
            -PassThru `
            -RedirectStandardOutput $outputPath `
            -RedirectStandardError $errorPath

        Start-Sleep -Milliseconds 800
        if ($script:ScreenRecordProcess.HasExited -and $script:ScreenRecordProcess.ExitCode -ne 0) {
            $detail = ""
            if (Test-Path -LiteralPath $errorPath -PathType Leaf) {
                $detail = (Get-Content -LiteralPath $errorPath -Raw -ErrorAction SilentlyContinue).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = "screenrecord 命令退出码：{0}" -f $script:ScreenRecordProcess.ExitCode
            }
            throw $detail
        }

        $currentPids = @(Get-ScreenRecordPids)
        $script:ScreenRecordPids = @($currentPids | Where-Object { $script:ScreenRecordExistingPids -notcontains $_ })
        $script:ScreenRecordStarted = $true
        Write-Host "设备录屏已启动，将在您按回车确认现场时停止。" -ForegroundColor Green
        Write-Host "提示：录屏通常最长 180 秒且不含音频；达到上限后 Logcat 仍会继续采集。"
        return $true
    }
    catch {
        $script:ScreenRecordResult = "启动失败：{0}" -f $_.Exception.Message
        $script:ScreenRecordFinalized = $true
        if ($null -ne $script:ScreenRecordProcess) {
            try {
                if (-not $script:ScreenRecordProcess.HasExited) {
                    Stop-Process -Id $script:ScreenRecordProcess.Id -Force -ErrorAction SilentlyContinue
                }
            }
            catch {}
            $script:ScreenRecordProcess = $null
        }
        Write-Host ("录屏启动失败，日志采集将继续。原因：{0}" -f $_.Exception.Message) -ForegroundColor Yellow
        Add-ScreenRecordingSummary
        return $false
    }
}

function Stop-ScreenRecording {
    if (-not $script:ScreenRecordingEnabled -or $script:ScreenRecordFinalized) {
        return
    }

    if (-not $script:ScreenRecordStarted -or [string]::IsNullOrWhiteSpace($script:ScreenRecordDevicePath)) {
        $script:ScreenRecordFinalized = $true
        $script:ScreenRecordResult = "未启动"
        Add-ScreenRecordingSummary
        return
    }

    $script:ScreenRecordStopTime = Get-Date
    $script:ScreenRecordFinalized = $true
    $outputFileName = "screen-recording.mp4"
    $outputPath = Join-Path $script:ScreenRecordDirectory $outputFileName
    $pullOutputPath = Join-Path $script:ScreenRecordDirectory "screen-recording-pull.txt"
    $pullErrorPath = Join-Path $script:ScreenRecordDirectory "screen-recording-pull.stderr.txt"

    try {
        if ($script:ScreenRecordPids.Count -eq 0) {
            $currentPids = @(Get-ScreenRecordPids)
            $script:ScreenRecordPids = @($currentPids | Where-Object { $script:ScreenRecordExistingPids -notcontains $_ })
        }
        if ($script:ScreenRecordStarted -and $script:ScreenRecordPids.Count -gt 0 -and $null -ne $script:ScreenRecordProcess -and -not $script:ScreenRecordProcess.HasExited) {
            foreach ($recordingPid in $script:ScreenRecordPids) {
                & $script:AdbPath -s $script:Serial shell kill -2 $recordingPid 2>$null | Out-Null
            }
        }

        $waitStartedAt = Get-Date
        $progressWasShown = $false
        while ($null -ne $script:ScreenRecordProcess -and -not $script:ScreenRecordProcess.WaitForExit(250)) {
            $elapsed = (Get-Date) - $waitStartedAt
            if ($elapsed.TotalSeconds -ge 1) {
                $percent = [Math]::Min(90, 10 + [int]($elapsed.TotalSeconds * 8))
                Write-InlineProgress `
                    -Activity "正在结束设备录屏" `
                    -Status ("正在写入视频文件，已等待 {0} 秒" -f [int]$elapsed.TotalSeconds) `
                    -PercentComplete $percent `
                    -Force:(-not $progressWasShown)
                $progressWasShown = $true
            }
            if ($elapsed.TotalSeconds -ge 10) {
                Stop-Process -Id $script:ScreenRecordProcess.Id -Force -ErrorAction SilentlyContinue
                break
            }
        }
        if ($progressWasShown) {
            Clear-InlineProgress
        }
        Start-Sleep -Milliseconds 500

        $pullProcess = Start-Process `
            -FilePath $script:AdbPath `
            -ArgumentList @("-s", $script:Serial, "pull", $script:ScreenRecordDevicePath, ('"{0}"' -f $outputPath)) `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $pullOutputPath `
            -RedirectStandardError $pullErrorPath
        $pullExitCode = Wait-ProcessWithProgress `
            -Process $pullProcess `
            -Activity "正在导出设备录屏" `
            -CurrentOperation "正在将录屏文件保存到结果目录" `
            -ProgressId 4

        if ($pullExitCode -eq 0 -and (Test-Path -LiteralPath $outputPath -PathType Leaf) -and (Get-Item -LiteralPath $outputPath).Length -gt 0) {
            $script:ScreenRecordResult = "成功"
            $script:ScreenRecordFileName = $outputFileName
            & $script:AdbPath -s $script:Serial shell rm -f $script:ScreenRecordDevicePath 2>$null | Out-Null
            if ((Test-Path -LiteralPath $pullErrorPath) -and ((Get-Item -LiteralPath $pullErrorPath).Length -eq 0)) {
                Remove-Item -LiteralPath $pullErrorPath -Force
            }
            Write-Host ("录屏已保存：{0}" -f $outputFileName) -ForegroundColor Green
        }
        else {
            $script:ScreenRecordResult = "导出失败；设备端临时文件未删除"
            Write-Host "录屏导出失败，日志采集将继续。请查看录屏命令错误文件。" -ForegroundColor Yellow
        }
    }
    catch {
        $script:ScreenRecordResult = "停止或导出失败：{0}" -f $_.Exception.Message
        Write-Utf8Lines -Path $pullErrorPath -Lines @($_.Exception.ToString())
        Write-Host ("录屏停止或导出失败，日志采集将继续。原因：{0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
    finally {
        Clear-InlineProgress
        if ($null -ne $script:ScreenRecordProcess) {
            try {
                if (-not $script:ScreenRecordProcess.HasExited) {
                    Stop-Process -Id $script:ScreenRecordProcess.Id -Force -ErrorAction SilentlyContinue
                }
            }
            catch {}
        }
        $script:ScreenRecordProcess = $null
        Add-ScreenRecordingSummary
    }
}

function Capture-Screenshot {
    param([string]$Directory)

    $screenshotPath = Join-Path $Directory "screen-at-problem.png"
    $errorPath = Join-Path $Directory "screen-at-problem.stderr.txt"

    try {
        $process = Start-Process `
            -FilePath $script:AdbPath `
            -ArgumentList @("-s", $script:Serial, "exec-out", "screencap", "-p") `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $screenshotPath `
            -RedirectStandardError $errorPath

        $exitCode = Wait-ProcessWithProgress `
            -Process $process `
            -Activity "正在采集诊断信息" `
            -CurrentOperation "正在截取问题现场画面" `
            -ProgressId 2

        if ($exitCode -ne 0) {
            return
        }
        if ((Test-Path -LiteralPath $errorPath) -and ((Get-Item -LiteralPath $errorPath).Length -eq 0)) {
            Remove-Item -LiteralPath $errorPath -Force
        }
    }
    catch {
        Write-Utf8Lines -Path $errorPath -Lines @($_.Exception.ToString())
    }
}

function Capture-AppThreads {
    param(
        [string]$PackageName,
        [string]$Directory
    )

    $pids = @(Get-PackagePids -PackageName $PackageName)
    Write-Utf8Lines -Path (Join-Path $Directory "app-pids-at-problem.txt") -Lines @($pids)

    foreach ($appPid in $pids) {
        Invoke-AdbSnapshot `
            -Name ("native-backtrace-{0}.txt" -f $appPid) `
            -Arguments @("shell", "debuggerd", "-b", $appPid) `
            -Directory $Directory `
            -ProgressMessage ("正在采集 native 线程快照，PID：{0}" -f $appPid) | Out-Null

        Invoke-AdbSnapshot `
            -Name ("java-sigquit-{0}.txt" -f $appPid) `
            -Arguments @("shell", "kill", "-3", $appPid) `
            -Directory $Directory `
            -ProgressMessage ("正在触发 Java 线程快照，PID：{0}" -f $appPid) | Out-Null
    }

    if ($pids.Count -gt 0) {
        Start-Sleep -Seconds 3
    }
}

function Pull-AnrFiles {
    param([string]$Directory)

    $destination = Join-Path $Directory "anr-files-from-device"
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $pullLog = Join-Path $Directory "pull-data-anr-result.txt"

    $pullError = Join-Path $Directory "pull-data-anr.stderr.txt"
    try {
        $process = Start-Process `
            -FilePath $script:AdbPath `
            -ArgumentList @("-s", $script:Serial, "pull", "/data/anr", ('"{0}"' -f $destination)) `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $pullLog `
            -RedirectStandardError $pullError
        Wait-ProcessWithProgress `
            -Process $process `
            -Activity "正在采集诊断信息" `
            -CurrentOperation "正在读取设备 ANR 文件" `
            -ProgressId 2 | Out-Null

        if ((Test-Path -LiteralPath $pullError) -and ((Get-Item -LiteralPath $pullError).Length -eq 0)) {
            Remove-Item -LiteralPath $pullError -Force
        }
    }
    catch {
        Write-Utf8Lines -Path $pullLog -Lines @($_.Exception.ToString())
    }
}

function Capture-Bugreport {
    param([string]$Directory)

    $outputPath = Join-Path $Directory "bugreport-command.txt"
    $errorPath = Join-Path $Directory "bugreport-command.stderr.txt"
    try {
        $process = Start-Process `
            -FilePath $script:AdbPath `
            -ArgumentList @("-s", $script:Serial, "bugreport", "bugreport.zip") `
            -WorkingDirectory $Directory `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $outputPath `
            -RedirectStandardError $errorPath
        Wait-ProcessWithProgress `
            -Process $process `
            -Activity "正在生成完整 Android bugreport" `
            -CurrentOperation "设备正在整理系统诊断数据，请勿断开连接" `
            -ProgressId 3 | Out-Null

        if ((Test-Path -LiteralPath $errorPath) -and ((Get-Item -LiteralPath $errorPath).Length -eq 0)) {
            Remove-Item -LiteralPath $errorPath -Force
        }
    }
    catch {
        Write-Utf8Lines -Path (Join-Path $Directory "bugreport-command.txt") -Lines @($_.Exception.ToString())
    }
}

function Compress-Result {
    param([string]$Directory)

    $zipPath = $Directory + ".zip"
    $zipStream = $null
    $archive = $null
    $progressId = 20
    try {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
            Remove-Item -LiteralPath $zipPath -Force
        }

        Write-InlineProgress -Activity "正在生成日志压缩包" -Status "正在统计日志文件……" -PercentComplete 0 -Force
        $files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse)
        $totalBytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
        $processedBytes = [long]0
        $directoryPrefix = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\') + '\'
        $zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        $buffer = New-Object byte[] (1024 * 1024)

        foreach ($file in $files) {
            $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
            $entryName = $fullPath.Substring($directoryPrefix.Length).Replace('\', '/')
            $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $inputStream = $null
            $entryStream = $null
            try {
                $inputStream = [System.IO.File]::OpenRead($fullPath)
                $entryStream = $entry.Open()
                while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $entryStream.Write($buffer, 0, $read)
                    $processedBytes += $read
                    $percent = if ($totalBytes -eq 0) { 100 } else { [Math]::Min(100, [int](($processedBytes * 100) / $totalBytes)) }
                    $status = "已处理 {0:N1} MB / {1:N1} MB" -f ($processedBytes / 1MB), ($totalBytes / 1MB)
                    Write-InlineProgress -Activity "正在生成日志压缩包" -Status $status -CurrentOperation $entryName -PercentComplete $percent
                }
            }
            finally {
                if ($null -ne $entryStream) { $entryStream.Dispose() }
                if ($null -ne $inputStream) { $inputStream.Dispose() }
            }
        }

        return $zipPath
    }
    catch {
        Write-Utf8Lines -Path (Join-Path $Directory "zip-error.txt") -Lines @($_.Exception.ToString())
        return ""
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $zipStream) { $zipStream.Dispose() }
        Clear-InlineProgress
    }
}

try {
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "                 Android 日志采集工具" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ("工具版本：{0}" -f $script:ToolVersion)

    $script:AdbPath = Resolve-Adb
    Write-Host ("ADB 路径：{0}" -f $script:AdbPath)

    Write-Step "正在检查 Android 设备"
    $script:Serial = Select-Device
    Write-Host ("已选择设备：{0}" -f $script:Serial) -ForegroundColor Green

    Write-Host ""
    Write-Host "请打开要测试的 App，并让它保持在前台。"
    Read-Host "看到目标 App 页面后按回车继续" | Out-Null

    $detectedPackage = Get-FocusedPackage
    if (-not [string]::IsNullOrWhiteSpace($detectedPackage)) {
        Write-Host ("检测到前台应用包名：{0}" -f $detectedPackage)
    }

    $packageInput = Read-Host ("请输入目标应用包名，直接按回车使用检测结果 [{0}]" -f $detectedPackage)
    $packageName = $packageInput.Trim()
    if ([string]::IsNullOrWhiteSpace($packageName)) {
        $packageName = $detectedPackage
    }
    if (-not [string]::IsNullOrWhiteSpace($packageName) -and $packageName -notmatch "^[A-Za-z0-9._]+$") {
        throw "应用包名包含无效字符，正确格式示例：com.example.app"
    }

    $script:ScreenRecordingEnabled = Confirm-ScreenRecording

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    New-Item -ItemType Directory -Path $script:ResultsRoot -Force | Out-Null
    $resultDirectory = Join-Path $script:ResultsRoot ("AndroidLogs_{0}_{1}" -f $timestamp, $script:Serial.Replace(":", "_"))
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
    $script:ScreenRecordDirectory = $resultDirectory

    $startTime = Get-Date
    $initialPids = @(Get-PackagePids -PackageName $packageName)
    Write-Utf8Lines -Path (Join-Path $resultDirectory "采集摘要.txt") -Lines @(
        ("工具版本：{0}" -f $script:ToolVersion),
        ("电脑名称：{0}" -f $env:COMPUTERNAME),
        ("设备序列号：{0}" -f $script:Serial),
        ("应用包名：{0}" -f $packageName),
        ("是否启用录屏：{0}" -f $(if ($script:ScreenRecordingEnabled) { "是" } else { "否" })),
        ("开始采集时 PID：{0}" -f ($initialPids -join ",")),
        ("采集开始时间：{0}" -f $startTime.ToString("yyyy-MM-dd HH:mm:ss.fff"))
    )
    if (-not $script:ScreenRecordingEnabled) {
        $script:ScreenRecordResult = "未启用"
        Add-ScreenRecordingSummary
    }
    Write-ResultGuide -Directory $resultDirectory

    Invoke-AdbSnapshot -Name "adb-version.txt" -Arguments @("version") -Directory $resultDirectory | Out-Null
    Invoke-AdbSnapshot -Name "device-properties.txt" -Arguments @("shell", "getprop") -Directory $resultDirectory | Out-Null
    Invoke-AdbSnapshot -Name "device-time.txt" -Arguments @("shell", "date") -Directory $resultDirectory | Out-Null

    Write-Step "正在清空旧日志并启动持续 Logcat 采集"
    & $script:AdbPath -s $script:Serial logcat -b all -c 2>$null
    Start-ContinuousLogcat -Directory $resultDirectory
    if ($script:ScreenRecordingEnabled) {
        Start-ScreenRecording -Directory $resultDirectory | Out-Null
    }
    Start-Sleep -Seconds 1

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "请现在操作 App，完成需要记录的普通操作或复现问题。" -ForegroundColor Yellow
    Write-Host "出现问题后请保持现场页面，不要退出 App。" -ForegroundColor Yellow
    Write-Host "然后回到此窗口按回车，开始导出现场信息。" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Read-Host | Out-Null

    $problemTime = Get-Date
    if ($script:ScreenRecordingEnabled -and -not $script:ScreenRecordFinalized) {
        Write-Step "正在停止并导出设备录屏"
        Stop-ScreenRecording
    }
    Write-Step "正在采集当前现场信息"
    $captureTasks = New-Object System.Collections.ArrayList
    $captureTasks.Add([pscustomobject]@{ Name = "截取问题现场画面"; Action = { Capture-Screenshot -Directory $resultDirectory } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "导出完整 Logcat 快照"; Action = { Invoke-AdbSnapshot -Name "logcat-snapshot.txt" -Arguments @("logcat", "-b", "all", "-d", "-v", "threadtime", "*:V") -Directory $resultDirectory -ProgressMessage "正在导出完整 Logcat 快照" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取最近一次 ANR"; Action = { Invoke-AdbSnapshot -Name "activity-lastranr.txt" -Arguments @("shell", "dumpsys", "activity", "lastanr") -Directory $resultDirectory -ProgressMessage "正在读取最近一次 ANR" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取前台 Activity 状态"; Action = { Invoke-AdbSnapshot -Name "activity-top.txt" -Arguments @("shell", "dumpsys", "activity", "top") -Directory $resultDirectory -ProgressMessage "正在读取前台 Activity 状态" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取 Activity 栈"; Action = { Invoke-AdbSnapshot -Name "activity-activities.txt" -Arguments @("shell", "dumpsys", "activity", "activities") -Directory $resultDirectory -ProgressMessage "正在读取 Activity 栈" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取应用进程状态"; Action = { Invoke-AdbSnapshot -Name "activity-processes.txt" -Arguments @("shell", "dumpsys", "activity", "processes") -Directory $resultDirectory -ProgressMessage "正在读取应用进程状态" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取窗口焦点状态"; Action = { Invoke-AdbSnapshot -Name "window.txt" -Arguments @("shell", "dumpsys", "window") -Directory $resultDirectory -ProgressMessage "正在读取窗口焦点状态" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取输入事件状态"; Action = { Invoke-AdbSnapshot -Name "input.txt" -Arguments @("shell", "dumpsys", "input") -Directory $resultDirectory -ProgressMessage "正在读取输入事件状态" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取 CPU 占用"; Action = { Invoke-AdbSnapshot -Name "cpuinfo.txt" -Arguments @("shell", "dumpsys", "cpuinfo") -Directory $resultDirectory -ProgressMessage "正在读取 CPU 占用" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取系统内存"; Action = { Invoke-AdbSnapshot -Name "meminfo-all.txt" -Arguments @("shell", "dumpsys", "meminfo") -Directory $resultDirectory -ProgressMessage "正在读取系统内存" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取线程占用"; Action = { Invoke-AdbSnapshot -Name "top-threads.txt" -Arguments @("shell", "top", "-b", "-n", "1", "-H") -Directory $resultDirectory -ProgressMessage "正在读取线程占用" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取进程线程列表"; Action = { Invoke-AdbSnapshot -Name "process-threads.txt" -Arguments @("shell", "ps", "-A", "-T") -Directory $resultDirectory -ProgressMessage "正在读取进程线程列表" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取电池状态"; Action = { Invoke-AdbSnapshot -Name "battery.txt" -Arguments @("shell", "dumpsys", "battery") -Directory $resultDirectory -ProgressMessage "正在读取电池状态" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取网络状态"; Action = { Invoke-AdbSnapshot -Name "connectivity.txt" -Arguments @("shell", "dumpsys", "connectivity") -Directory $resultDirectory -ProgressMessage "正在读取网络状态" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取 ANR 文件列表"; Action = { Invoke-AdbSnapshot -Name "data-anr-list.txt" -Arguments @("shell", "ls", "-la", "/data/anr") -Directory $resultDirectory -ProgressMessage "正在读取 ANR 文件列表" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取应用 ANR 历史"; Action = { Invoke-AdbSnapshot -Name "dropbox-data-app-anr.txt" -Arguments @("shell", "dumpsys", "dropbox", "--print", "data_app_anr") -Directory $resultDirectory -ProgressMessage "正在读取应用 ANR 历史" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取系统应用 ANR 历史"; Action = { Invoke-AdbSnapshot -Name "dropbox-system-app-anr.txt" -Arguments @("shell", "dumpsys", "dropbox", "--print", "system_app_anr") -Directory $resultDirectory -ProgressMessage "正在读取系统应用 ANR 历史" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取系统服务 ANR 历史"; Action = { Invoke-AdbSnapshot -Name "dropbox-system-server-anr.txt" -Arguments @("shell", "dumpsys", "dropbox", "--print", "system_server_anr") -Directory $resultDirectory -ProgressMessage "正在读取系统服务 ANR 历史" | Out-Null } }) | Out-Null
    $captureTasks.Add([pscustomobject]@{ Name = "读取应用崩溃历史"; Action = { Invoke-AdbSnapshot -Name "dropbox-data-app-crash.txt" -Arguments @("shell", "dumpsys", "dropbox", "--print", "data_app_crash") -Directory $resultDirectory -ProgressMessage "正在读取应用崩溃历史" | Out-Null } }) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($packageName)) {
        $captureTasks.Add([pscustomobject]@{ Name = "读取应用安装信息"; Action = { Invoke-AdbSnapshot -Name "package-info.txt" -Arguments @("shell", "dumpsys", "package", $packageName) -Directory $resultDirectory -ProgressMessage "正在读取应用安装信息" | Out-Null } }) | Out-Null
        $captureTasks.Add([pscustomobject]@{ Name = "读取应用内存"; Action = { Invoke-AdbSnapshot -Name "app-meminfo.txt" -Arguments @("shell", "dumpsys", "meminfo", $packageName) -Directory $resultDirectory -ProgressMessage "正在读取应用内存" | Out-Null } }) | Out-Null
        $captureTasks.Add([pscustomobject]@{ Name = "读取应用渲染信息"; Action = { Invoke-AdbSnapshot -Name "app-gfxinfo.txt" -Arguments @("shell", "dumpsys", "gfxinfo", $packageName, "framestats") -Directory $resultDirectory -ProgressMessage "正在读取应用渲染信息" | Out-Null } }) | Out-Null
        $captureTasks.Add([pscustomobject]@{ Name = "读取应用退出历史"; Action = { Invoke-AdbSnapshot -Name "app-exit-info.txt" -Arguments @("shell", "dumpsys", "activity", "exit-info", $packageName) -Directory $resultDirectory -ProgressMessage "正在读取应用退出历史" | Out-Null } }) | Out-Null
        $captureTasks.Add([pscustomobject]@{ Name = "采集应用线程快照"; Action = { Capture-AppThreads -PackageName $packageName -Directory $resultDirectory } }) | Out-Null
    }
    else {
        $captureTasks.Add([pscustomobject]@{ Name = "读取应用退出历史"; Action = { Invoke-AdbSnapshot -Name "app-exit-info.txt" -Arguments @("shell", "dumpsys", "activity", "exit-info") -Directory $resultDirectory -ProgressMessage "正在读取应用退出历史" | Out-Null } }) | Out-Null
    }

    $captureTasks.Add([pscustomobject]@{ Name = "读取设备 ANR 文件"; Action = { Pull-AnrFiles -Directory $resultDirectory } }) | Out-Null
    Invoke-TaskSequence -Tasks @($captureTasks) -Activity "正在采集当前现场信息" -ProgressId 1

    Write-Step "正在生成完整 Android bugreport"
    Capture-Bugreport -Directory $resultDirectory

    Stop-ContinuousLogcat
    $finishTime = Get-Date
    $finalPids = @(Get-PackagePids -PackageName $packageName)
    Add-Content -LiteralPath (Join-Path $resultDirectory "采集摘要.txt") -Encoding UTF8 -Value @(
        ("现场确认时间：{0}" -f $problemTime.ToString("yyyy-MM-dd HH:mm:ss.fff")),
        ("结束采集时 PID：{0}" -f ($finalPids -join ",")),
        ("采集完成时间：{0}" -f $finishTime.ToString("yyyy-MM-dd HH:mm:ss.fff"))
    )

    Write-Step "正在生成日志压缩包"
    $resultZip = Compress-Result -Directory $resultDirectory

    Write-Host ""
    Write-Host "日志采集完成。" -ForegroundColor Green
    Write-Host ("结果目录：{0}" -f $resultDirectory)
    if (-not [string]::IsNullOrWhiteSpace($resultZip)) {
        Write-Host ("请将此 ZIP 文件发给开发人员：{0}" -f $resultZip) -ForegroundColor Green
    }
    Write-Host "请同时提供操作步骤和问题发生的大致时间。"
    Read-Host "按回车关闭窗口" | Out-Null
    exit 0
}
catch {
    Stop-ScreenRecording
    Write-Host ""
    Write-Host ("错误：{0}" -f $_.Exception.Message) -ForegroundColor Red
    Read-Host "按回车关闭窗口" | Out-Null
    exit 1
}
finally {
    Clear-InlineProgress
    Stop-ScreenRecording
    Stop-ContinuousLogcat
}
