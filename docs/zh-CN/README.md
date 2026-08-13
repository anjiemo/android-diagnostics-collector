# Android 日志采集工具

[English](../../README.md) | 简体中文

![采集端](https://img.shields.io/badge/采集端-Windows-blue.svg) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg) ![ADB](https://img.shields.io/badge/ADB-Android%20Platform%20Tools-3DDC84.svg) ![版本](https://img.shields.io/badge/version-1.1.0-orange.svg)

面向 QA 和开发人员的通用 Android 诊断采集工具。工具从指定 Android 设备采集普通运行日志，也采集闪退、
白屏、卡死和 ANR 等问题的现场信息。工具以 Windows 启动器形式分发，不依赖 Android Studio 或 Android 工程。

## 功能

- 持续采集所有 Logcat 缓冲区，包括 `main`、`system`、`crash` 和 `events`。
- 按需导出 Activity、Window、Input、CPU、内存、电池、网络、进程和线程状态。
- 采集 `lastanr`、Dropbox、应用退出历史、`/data/anr`（设备权限允许时）以及 Java/native 线程快照。
- 导出完整的 `adb bugreport`。
- 可选设备录屏：与 Logcat 同时启动，在操作者确认问题现场后停止并拉取。
- 耗时操作在窗口底部同一行显示进度；进入下一步前会清理进度行，不会在窗口顶部快速闪烁。
- 每次采集自动生成 ZIP 压缩包。
- 工具提示和采集摘要使用中文；Android 原始诊断输出保持原文。

## 使用要求

- Windows 10 或更高版本，支持 Windows PowerShell 5.1 或 PowerShell 7。
- 已开启 USB 调试并授权当前电脑的 Android 设备。
- Android Debug Bridge（`adb.exe`），不要求安装 Android Studio。

仓库可以在 macOS 或 Linux 上下载、查看和维护，但当前采集脚本只提供 Windows 启动方式，并非原生 macOS/Linux
采集器。

## 快速开始

1. 在 Android 设备上开启 **USB 调试**，并允许当前电脑调试。
2. 双击 `开始采集Android日志.bat`。
3. 如果连接了多台设备，按提示选择目标设备序列号。
4. 让目标 App 保持在前台。按回车接受自动识别的包名，或手动输入包名。
5. 选择是否录制设备屏幕。直接按回车或输入 `N` 表示关闭；输入 `Y` 表示启用。
6. 在 Logcat 持续采集期间操作 App，完成普通流程或复现问题。
7. 保持问题现场，回到工具窗口按回车。
8. 等待现场快照、可选录屏导出和完整 bugreport 完成。将生成的 ZIP 与复现步骤、问题大致时间一起提供给开发人员。

也可以在终端启动：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\capture-android-logs.ps1
```

## ADB 配置

`adb.config` 是单独的可编辑配置文件。`ADB_PATH` 默认留空，工具会先从系统 `PATH` 查找 `adb.exe`。填写非空值后，
该值会覆盖 `PATH`，支持绝对路径或相对于工具目录的路径：

```ini
# 绝对路径
ADB_PATH=C:\Users\tester\AppData\Local\Android\Sdk\platform-tools\adb.exe

# 或使用相对于工具目录的 platform-tools 文件夹
# ADB_PATH=platform-tools
```

找不到 ADB 时，工具会先询问是否从 Google 官方地址下载 `platform-tools`。下载的运行时放在 `_runtime/`，该目录已被
Git 忽略。

## 可选录屏

录屏默认关闭，只有明确输入 `Y` 才会启用。工具调用 Android 原生命令：

```text
adb -s SERIAL shell screenrecord --bit-rate 6000000 --time-limit 180 /sdcard/android_log_record_TIMESTAMP.mp4
```

Android 通常将 `screenrecord` 时长限制为 180 秒，且不包含设备音频。达到上限只会结束录屏，Logcat 会继续采集。
如果录屏无法启动或 MP4 拉取失败，工具会记录原因并继续采集其他信息。

## 输出内容

每次运行都会在 `results/` 下生成独立目录，并在旁边生成 ZIP：

```text
results/
  AndroidLogs_yyyyMMdd_HHmmss_SERIAL/
  AndroidLogs_yyyyMMdd_HHmmss_SERIAL.zip
```

主要文件包括：

- `logcat-all.txt`：持续采集的全量 Logcat。
- `logcat-snapshot.txt`：按回车确认现场时导出的 Logcat 快照。
- `screen-at-problem.png`：问题现场截图。
- `screen-recording.mp4`：可选设备录屏。
- `bugreport.zip`：完整 Android 系统诊断包。
- `采集摘要.txt`：设备、包名、时间、PID 和录屏结果。
- `日志文件说明.txt`：逐文件说明。

`results/`、生成的 ZIP、`_runtime/` 和本地临时文件已加入 Git 忽略规则。初始化 Git 不会删除已有采集数据。

## 常见问题

### 找不到设备

检查 USB 调试、设备授权提示、USB 数据线和连接模式，以及设备厂商 USB 驱动。设备显示 `unauthorized` 时，解锁手机
并允许调试，然后重试。

### `/data/anr` 提示 Permission denied

量产设备上这是正常现象。工具还会采集 `lastanr`、Dropbox、线程快照和完整 bugreport，不需要 root。

### 没有弹出 ANR 对话框

仍然需要采集。白屏和输入无响应不一定触发系统 ANR，持续 Logcat、Window/Input 状态、线程快照和 bugreport 仍然有价值。

### 录屏失败或没有声音

这通常是设备支持情况或 Android 原生 `screenrecord` 的限制。失败信息会写入 `采集摘要.txt`，不会取消其他日志采集。

## 仓库安全

不要提交密码、个人 ADB 路径、设备采集结果、bugreport、MP4 录屏或下载的 platform-tools。`adb.config` 只用于共享配置
模板；机器专用覆盖可写入已被忽略的 `adb.config.local`。
