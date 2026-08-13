# Windows Guide

Configure `platforms/windows/adb.config`, then double-click `platforms/windows/开始采集Android日志.bat`.
When `ADB_PATH` is empty, the PowerShell collector checks the Windows `PATH`, then asks whether to
download Google's official platform-tools.

The collector supports continuous all-buffer Logcat, scene snapshots, ANR/crash evidence, optional
screen recording, and `adb bugreport`. Press Enter in the collector window after reproducing the issue;
recording is stopped and pulled before the scene snapshots start.

Long operations update one line at the bottom of the console. The line is cleared before the next step.
Results are written to `results/windows/` and are ignored by Git.
