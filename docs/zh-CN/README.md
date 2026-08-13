# Android 诊断采集工具

[English](../../README.md) | 简体中文

![平台](https://img.shields.io/badge/platform-Windows%20%7C%20macOS-blue.svg) ![ADB](https://img.shields.io/badge/ADB-Android%20Platform%20Tools-3DDC84.svg) ![版本](https://img.shields.io/badge/version-1.1.0-orange.svg)

用于采集 Android 普通运行日志、闪退、白屏、卡死、ANR、完整 bugreport 以及可选录屏的跨平台诊断工具。

## 功能

- 持续采集全量 Logcat，包括 `main`、`system`、`crash` 和 `events`。
- 导出 Activity、Window、Input、CPU、内存、电池、网络、进程和线程状态。
- 采集 `lastanr`、Dropbox、应用退出历史、设备允许读取时的 `/data/anr`，以及 Java/native 线程快照。
- 导出完整 `adb bugreport`。
- 可选 Android 原生录屏，与 Logcat 同时启动，在确认问题现场后停止并拉取。
- 耗时任务在底部显示进度，并自动生成 ZIP。
- 工具提示和摘要使用中文，Android 原始诊断输出保持原文。

## 选择平台

| 平台 | 启动入口 | 说明 |
| --- | --- | --- |
| Windows | `platforms/windows/开始采集Android日志.bat` | [Windows 使用说明](../en/windows.md) |
| macOS | `platforms/macos/collect-android-logs.command` | [macOS 使用说明](../en/macos.md) |

本版本暂不提供 Linux 采集入口。macOS 版本使用 Bash，需要 macOS 及 Android platform-tools；找不到 ADB 时可选择通过
Homebrew 安装。

## 要求

- Android 设备已开启 USB 调试并授权当前电脑。
- Android Debug Bridge（`adb`），不要求安装 Android Studio。
- Windows：Windows PowerShell 5.1 或 PowerShell 7。
- macOS：Bash、`awk`、`sed`、`tar` 和 `ditto`；只有选择自动安装 ADB 时才需要 Homebrew。

## 输出

每次采集都会在 `results/` 下生成对应平台的独立目录：

```text
results/
  windows/AndroidLogs_yyyyMMdd_HHmmss_SERIAL/
  macos/AndroidLogs_yyyyMMdd_HHmmss_SERIAL/
```

目录中包含持续 Logcat、现场截图、系统状态快照、`bugreport.zip`、`采集摘要.txt` 和可选的
`screen-recording.mp4`，旁边还会生成 ZIP 压缩包。

采集结果、ADB 运行时、本地配置覆盖、IDE 状态和临时文件已加入 Git 忽略规则。不要提交设备日志、bugreport、录屏、
凭据或个人 ADB 路径。

## 目录结构

```text
platforms/
  windows/       PowerShell 采集器、BAT 启动器、Windows ADB 配置
  macos/         Bash 采集器、.command 启动器、macOS ADB 配置
docs/
  en/            英文平台说明
  zh-CN/         中文 README 和使用说明
```

当前版本：`1.1.0`。
