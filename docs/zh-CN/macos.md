# macOS 使用说明

## 环境要求

- macOS，已开启 USB 调试并授权当前电脑的 Android 设备。
- Bash、`awk`、`sed`、`tar` 和 `ditto`。
- Android Debug Bridge（`adb`）。不要求安装 Android Studio。

## 启动

1. 打开 `platforms/macos/adb.config`，配置 `ADB_PATH`。留空时读取当前 shell 的 `PATH`。
2. 首次使用执行：

   ```bash
   chmod +x platforms/macos/capture-android-logs.sh platforms/macos/collect-android-logs.command
   ```

3. 双击 `platforms/macos/collect-android-logs.command`，或在终端执行：

   ```bash
   ./platforms/macos/capture-android-logs.sh
   ```

4. 找不到 ADB 时，工具会询问是否使用 Homebrew 安装 Android platform-tools，不会未经确认安装。

## 采集流程

1. 连接并授权设备，按提示选择设备。
2. 打开目标 App 并保持在前台，按回车继续。
3. 接受自动识别的包名，或手动输入目标应用包名。
4. 选择是否录制设备屏幕：直接按回车或输入 `N` 表示不录屏，输入 `Y` 表示启用。
5. 操作 App，完成普通流程或复现问题。
6. 保持问题现场，回到终端按回车。
7. 工具会停止并导出录屏，然后采集现场截图、Logcat、ANR、线程、系统状态和完整 bugreport。

耗时操作会在终端底部同一行显示进度，完成后清理该行。录屏失败不会中断其他日志采集。

## ADB 配置

`ADB_PATH` 可以填写 `adb` 的绝对路径，也可以填写相对于 `platforms/macos` 的路径：

```ini
ADB_PATH=/Users/tester/Library/Android/sdk/platform-tools/adb
# ADB_PATH=platform-tools/adb
```

## 输出与录屏限制

结果写入仓库根目录的 `results/macos/`，每次采集生成独立目录和 ZIP。Android 原生 `screenrecord` 通常最长 180 秒，
且不含设备音频；达到上限只会结束录屏，Logcat 会继续采集。
