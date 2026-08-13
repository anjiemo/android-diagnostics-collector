# macOS Guide

The macOS collector is a Bash script. Configure `platforms/macos/adb.config`, make the launchers
executable once, and start the collector:

```bash
chmod +x platforms/macos/capture-android-logs.sh platforms/macos/collect-android-logs.command
./platforms/macos/capture-android-logs.sh
```

The script checks the configured `ADB_PATH` and the current `PATH`. If ADB is missing, it asks whether
to install Android platform-tools through Homebrew. It never installs without confirmation.

The macOS collector captures continuous all-buffer Logcat, a scene screenshot, Activity/Window/Input,
CPU/memory/network/battery/process snapshots, ANR/Dropbox evidence, app memory and rendering state,
Java/native thread evidence, optional screen recording, and `adb bugreport`.

Screen recording is disabled by default. Android commonly limits native recording to 180 seconds and
does not include device audio. Recording failures are recorded and do not stop the remaining capture.

Results are written to `results/macos/` and compressed with the macOS `ditto` command. The output and
local runtime files are ignored by Git.
