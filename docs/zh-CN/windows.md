# Windows 使用说明

## 环境要求

- Windows 10 或更高版本。
- Windows PowerShell 5.1 或 PowerShell 7。
- 已开启 USB 调试并授权当前电脑的 Android 设备。
- Android Debug Bridge（`adb.exe`）。不要求安装 Android Studio。

## 启动

1. 打开 `platforms/windows/adb.config`，配置 `ADB_PATH`。留空时读取 Windows `PATH`。
2. 双击 `platforms/windows/开始采集Android日志.bat`。
3. 如果找不到 ADB，工具会先询问是否下载 Google 官方 platform-tools，不会未经确认自动下载。
4. 如果连接多台设备，按提示选择目标设备序列号。

## 采集流程

1. 打开目标 App 并保持在前台，按回车继续。
2. 接受自动识别的包名，或手动输入目标应用包名。
3. 选择是否录制设备屏幕：直接按回车或输入 `N` 表示不录屏，输入 `Y` 表示启用。
4. 操作 App，完成普通流程或复现问题。
5. 保持问题现场，回到工具窗口按回车。
6. 工具会先停止并导出录屏，再采集现场截图、Logcat、ANR、线程、系统状态和完整 bugreport。

耗时操作在窗口底部使用同一行显示进度，完成后会清理进度行。录屏失败不会中断其他日志采集。

## ADB 配置

`ADB_PATH` 可以填写 `adb.exe` 的绝对路径，也可以填写相对于 `platforms/windows` 的目录或路径：

```ini
ADB_PATH=C:\Users\tester\AppData\Local\Android\Sdk\platform-tools\adb.exe
# ADB_PATH=platform-tools
```

## 输出

结果写入仓库根目录的 `results/windows/`，每次采集生成独立目录和 ZIP。主要文件包括持续 Logcat、现场截图、
`bugreport.zip`、`采集摘要.txt` 和可选的 `screen-recording.mp4`。
