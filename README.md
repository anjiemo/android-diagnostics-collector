# Android Diagnostics Collector

English | [简体中文](docs/zh-CN/README.md)

![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS-blue.svg) ![ADB](https://img.shields.io/badge/ADB-Android%20Platform%20Tools-3DDC84.svg) ![Version](https://img.shields.io/badge/version-1.1.0-orange.svg)

A cross-platform Android diagnostics collector for ordinary runtime logs, crashes, blank screens,
freezes, ANR investigations, full bugreports, and optional screen recording.

## Features

- Continuous all-buffer Logcat collection, including `main`, `system`, `crash`, and `events`.
- Activity, Window, Input, CPU, memory, battery, connectivity, process, and thread snapshots.
- ANR/crash evidence from `lastanr`, Dropbox, app exit history, `/data/anr` when permitted, and
  Java/native thread snapshots.
- Full `adb bugreport` export.
- Optional Android-native screen recording, started together with Logcat and pulled when the problem
  scene is confirmed.
- Bottom-line progress for long operations and automatic ZIP packaging.
- Chinese prompts and summaries; raw Android diagnostic output remains unchanged.

## Choose A Platform

| Platform | Entry point | Documentation |
| --- | --- | --- |
| Windows | `platforms/windows/开始采集Android日志.bat` | [Windows guide](docs/en/windows.md) |
| macOS | `platforms/macos/collect-android-logs.command` | [macOS guide](docs/en/macos.md) |

Linux is not included in this release. The macOS collector is a Bash script and requires macOS with
Android platform-tools installed or available through Homebrew.

## Requirements

- Android device with USB debugging enabled and an authorized connection.
- Android Debug Bridge (`adb`). Android Studio is optional.
- Windows: Windows PowerShell 5.1+ or PowerShell 7.
- macOS: Bash, `awk`, `sed`, `tar`, and `ditto`; Homebrew is only needed when choosing automatic ADB installation.

## Output

Each run creates a platform-specific directory under `results/`:

```text
results/
  windows/AndroidLogs_yyyyMMdd_HHmmss_SERIAL/
  macos/AndroidLogs_yyyyMMdd_HHmmss_SERIAL/
```

The directory contains continuous Logcat, a problem screenshot, system snapshots, `bugreport.zip`,
`采集摘要.txt`, and an optional `screen-recording.mp4`. A ZIP archive is created beside each result
directory.

Generated results, ADB runtimes, local configuration overrides, IDE state, and temporary files are
ignored by Git. Do not commit device logs, bugreports, recordings, credentials, or personal ADB paths.

## Repository Layout

```text
platforms/
  windows/       PowerShell collector, BAT launcher, Windows ADB config
  macos/         Bash collector, .command launcher, macOS ADB config
docs/
  en/            English platform guides
  zh-CN/         Chinese README and user guide
```

## Version

Current release: `1.1.0`.
