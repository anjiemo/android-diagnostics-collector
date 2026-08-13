# Android Log Collector

English | [简体中文](docs/zh-CN/README.md)

![Platform](https://img.shields.io/badge/采集端-Windows-blue.svg) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg) ![ADB](https://img.shields.io/badge/ADB-Android%20Platform%20Tools-3DDC84.svg) ![Version](https://img.shields.io/badge/version-1.1.0-orange.svg)

A general-purpose Android diagnostics collector for QA and developers. It captures ordinary runtime
logs as well as crash, blank-screen, freeze, and ANR evidence from a selected Android device. The
tool is distributed as a small Windows launcher and does not require Android Studio or an Android
project.

## Features

- Continuous Logcat collection from all buffers, including `main`, `system`, `crash`, and `events`.
- On-demand snapshots for Activity, Window, Input, CPU, memory, battery, connectivity, process, and
  thread state.
- ANR and crash evidence from `lastanr`, Dropbox, app exit history, `/data/anr` (when ADB permissions
  allow), and Java/native thread snapshots.
- Full `adb bugreport` export.
- Optional device screen recording with Android `screenrecord`; it starts with Logcat and is stopped
  and pulled when the operator confirms the problem scene.
- One-line bottom progress updates for long-running operations. The progress line is cleared before
  the next message, so the console does not rapidly scroll or blink at the top.
- Automatic ZIP packaging of each collection.
- Chinese prompts and summaries; raw Android diagnostic output remains unchanged.

## Requirements

- Windows 10 or later with Windows PowerShell 5.1 or PowerShell 7.
- An Android device with USB debugging enabled and an authorized USB connection.
- Android Debug Bridge (`adb.exe`). Android Studio is optional.

The repository contains a Windows launcher. The repository itself can be downloaded and inspected on
macOS or Linux, but the included collector is not a native macOS/Linux launcher.

## Quick start

1. Enable **USB debugging** on the Android device and authorize the computer.
2. Double-click `开始采集Android日志.bat`.
3. If multiple devices are connected, select the target serial number.
4. Keep the target app in the foreground. Press Enter and accept the detected package name, or type
   it manually.
5. Choose whether to record the device screen. Press Enter or enter `N` to disable recording; enter
   `Y` to enable it.
6. Reproduce the normal workflow or problem while Logcat is running.
7. Leave the app on the problem screen and press Enter in the collector window.
8. Wait for the scene snapshot, optional recording export, and full bugreport to finish. Send the
   generated ZIP together with reproduction steps and the approximate problem time.

The same flow can be started from a terminal:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\capture-android-logs.ps1
```

## ADB configuration

`adb.config` is a separate, human-editable configuration file. `ADB_PATH` is empty by default, so
the tool first reads `adb.exe` from the system `PATH`. A non-empty value overrides `PATH` and may be an
absolute path or a path relative to the tool directory:

```ini
# Absolute path
ADB_PATH=C:\Users\tester\AppData\Local\Android\Sdk\platform-tools\adb.exe

# Or a platform-tools directory relative to this tool
# ADB_PATH=platform-tools
```

When ADB is not found, the tool asks before downloading the official Google `platform-tools` package.
The downloaded runtime is stored under `_runtime/` and is ignored by Git.

## Screen recording

Recording is optional and disabled by default. It uses the Android-native command below:

```text
adb -s SERIAL shell screenrecord --bit-rate 6000000 --time-limit 180 /sdcard/android_log_record_TIMESTAMP.mp4
```

Android commonly limits `screenrecord` to 180 seconds and does not include device audio. Reaching the
limit stops only the recording; Logcat continues. If recording cannot start or the MP4 cannot be
pulled, the collector reports the reason and continues collecting other evidence.

## Output

Each run creates an independent directory under `results/` and a ZIP beside it:

```text
results/
  AndroidLogs_yyyyMMdd_HHmmss_SERIAL/
  AndroidLogs_yyyyMMdd_HHmmss_SERIAL.zip
```

Important files include:

- `logcat-all.txt`: continuous all-buffer Logcat.
- `logcat-snapshot.txt`: Logcat snapshot captured at confirmation time.
- `screen-at-problem.png`: problem-scene screenshot.
- `screen-recording.mp4`: optional device recording.
- `bugreport.zip`: complete Android system report.
- `采集摘要.txt`: device, package, timestamps, PIDs, and recording result.
- `日志文件说明.txt`: file-by-file description.

The `results/` directory, generated ZIPs, `_runtime/`, and local temporary files are intentionally
ignored by Git. Existing collection data is never removed by Git initialization.

## Troubleshooting

### No device found

Check USB debugging, the authorization prompt on the device, the USB cable/data mode, and the device
vendor USB driver. Unlock the device when its state is `unauthorized`, then retry.

### `/data/anr` permission denied

This is normal on production devices. The collector also captures `lastanr`, Dropbox entries, thread
snapshots, and the full bugreport. Root access is not required.

### No ANR dialog appeared

Collect the logs anyway. Blank screens and input freezes do not always trigger a system ANR. Continuous
Logcat, Window/Input state, thread snapshots, and bugreport are still useful.

### Recording failed or has no sound

This reflects device support and the Android-native `screenrecord` limits. The failure is recorded in
`采集摘要.txt` and does not cancel the rest of the collection.

## Repository safety

Do not commit credentials, personal ADB paths, device collection results, bugreports, MP4 recordings,
or downloaded platform-tools. Use `adb.config` only for the shareable template; machine-specific
overrides can be kept in `adb.config.local`, which is ignored.
