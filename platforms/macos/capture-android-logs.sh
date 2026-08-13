#!/usr/bin/env bash
set -u

TOOL_VERSION="1.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_ROOT="${SCRIPT_DIR}/../../results/macos"
CONFIG_PATH="${SCRIPT_DIR}/adb.config"
ADB_PATH=""
SERIAL=""
PACKAGE_NAME=""
LOGCAT_PID=""
SCREEN_RECORD_PID=""
SCREEN_RECORD_REMOTE_PID=""
SCREEN_RECORD_ENABLED="false"
SCREEN_RECORD_REMOTE=""
SCREEN_RECORD_RESULT="未启用"
SCREEN_RECORD_FILE="无"
SCREEN_RECORD_STARTED_AT=""
SCREEN_RECORD_STOPPED="false"
RESULT_DIR=""
PROGRESS_ACTIVE="false"

print_step() {
    clear_progress
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$1"
}

clear_progress() {
    if [[ "$PROGRESS_ACTIVE" == "true" ]]; then
        printf '\r%-120s\r' "" >&2
        PROGRESS_ACTIVE="false"
    fi
}

progress_line() {
    local activity="$1"
    local operation="$2"
    local elapsed="$3"
    printf '\r[%-20s] 正在执行：%-24s 已耗时 %ss' "####################" "$activity / $operation" "$elapsed" >&2
    PROGRESS_ACTIVE="true"
}

run_with_progress() {
    local activity="$1"
    local operation="$2"
    shift 2
    local started_at="$(date +%s)"
    "$@" &
    local pid=$!
    local shown="false"
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - started_at ))
        if (( elapsed >= 1 )); then
            progress_line "$activity" "$operation" "$elapsed"
            shown="true"
        fi
        sleep 0.25
    done
    wait "$pid"
    local code=$?
    if [[ "$shown" == "true" ]]; then clear_progress; fi
    return "$code"
}

read_configured_adb() {
    [[ -f "$CONFIG_PATH" ]] || return 0
    local line value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        if [[ "$line" =~ ^ADB_PATH[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            value="${value%\"}"; value="${value#\"}"
            value="${value%\'}"; value="${value#\'}"
            printf '%s' "$value"
            return 0
        fi
    done < "$CONFIG_PATH"
}

resolve_adb() {
    local configured="$(read_configured_adb)"
    if [[ -n "$configured" ]]; then
        if [[ "$configured" != /* ]]; then configured="${SCRIPT_DIR}/${configured}"; fi
        if [[ -d "$configured" ]]; then configured="${configured}/adb"; fi
        if [[ -x "$configured" ]]; then printf '%s' "$configured"; return 0; fi
        printf 'adb.config 中的 ADB_PATH 无效：%s\n' "$configured" >&2
        return 1
    fi
    command -v adb 2>/dev/null || true
}

confirm_adb_install() {
    printf '\n未找到 adb。是否使用 Homebrew 安装 Android platform-tools？[Y/是，N/否]\n'
    local answer
    while true; do
        read -r -p '请输入 Y 或 N：' answer
        case "$answer" in
            Y|y|是) return 0 ;;
            N|n|否) return 1 ;;
            *) printf '请输入 Y 或 N。\n' ;;
        esac
    done
}

resolve_or_install_adb() {
    ADB_PATH="$(resolve_adb)"
    [[ -n "$ADB_PATH" ]] && return 0
    if ! confirm_adb_install; then
        printf '已取消安装 ADB，请配置 platforms/macos/adb.config 后重试。\n' >&2
        return 1
    fi
    if ! command -v brew >/dev/null 2>&1; then
        printf '未找到 Homebrew。请先安装 Homebrew，或在 adb.config 中配置 adb 路径。\n' >&2
        return 1
    fi
    print_step '正在通过 Homebrew 安装 Android platform-tools'
    brew install --cask android-platform-tools
    ADB_PATH="$(resolve_adb)"
    [[ -n "$ADB_PATH" ]] || { printf '安装完成但仍未找到 adb。\n' >&2; return 1; }
}

list_devices() {
    "$ADB_PATH" devices | awk '$2 == "device" { print $1 }'
}

select_device() {
    "$ADB_PATH" start-server >/dev/null 2>&1 || true
    local devices=( $(list_devices) )
    if (( ${#devices[@]} == 1 )); then SERIAL="${devices[0]}"; return 0; fi
    if (( ${#devices[@]} > 1 )); then
        printf '发现多台已授权设备：\n'
        local i=1
        for device in "${devices[@]}"; do printf '  %d. %s\n' "$i" "$device"; i=$((i + 1)); done
        local choice
        read -r -p '请输入设备序号：' choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#devices[@]} )); then
            SERIAL="${devices[$((choice - 1))]}"; return 0
        fi
    fi
    printf '未发现已授权的 Android 设备。请检查 USB 调试和设备授权。\n' >&2
    return 1
}

focused_package() {
    "$ADB_PATH" -s "$SERIAL" shell dumpsys window 2>/dev/null | sed -nE 's/.*mCurrentFocus=.* ([A-Za-z0-9._]+)\/.*/\1/p' | head -1
}

package_pids() {
    [[ -n "$1" ]] || return 0
    "$ADB_PATH" -s "$SERIAL" shell pidof "$1" 2>/dev/null | tr -d '\r'
}

snapshot() {
    local name="$1" operation="$2"
    shift 2
    run_with_progress '正在采集诊断信息' "$operation" "$ADB_PATH" -s "$SERIAL" "$@" >"${RESULT_DIR}/${name}" 2>"${RESULT_DIR}/${name}.stderr.txt" || true
    [[ ! -s "${RESULT_DIR}/${name}.stderr.txt" ]] && rm -f "${RESULT_DIR}/${name}.stderr.txt"
}

start_logcat() {
    "$ADB_PATH" -s "$SERIAL" logcat -b all -c >/dev/null 2>&1 || true
    "$ADB_PATH" -s "$SERIAL" logcat -b all -v threadtime '*:V' >"${RESULT_DIR}/logcat-all.txt" 2>"${RESULT_DIR}/logcat-all.stderr.txt" &
    LOGCAT_PID=$!
}

stop_logcat() {
    [[ -n "$LOGCAT_PID" ]] || return 0
    kill "$LOGCAT_PID" 2>/dev/null || true
    wait "$LOGCAT_PID" 2>/dev/null || true
    LOGCAT_PID=""
}

confirm_recording() {
    printf '\n可选功能：录制复现过程中的设备画面。Android 原生录屏通常最长 180 秒，不包含设备音频。\n'
    local answer
    read -r -p '是否同时录制设备屏幕？[Y/是，N/否，默认 N]：' answer
    [[ "$answer" =~ ^(Y|y|是)$ ]]
}

start_recording() {
    SCREEN_RECORD_ENABLED="true"
    SCREEN_RECORD_STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
    SCREEN_RECORD_REMOTE="/sdcard/android_log_record_$(date '+%Y%m%d_%H%M%S').mp4"
    "$ADB_PATH" -s "$SERIAL" shell screenrecord --bit-rate 6000000 --time-limit 180 "$SCREEN_RECORD_REMOTE" >"${RESULT_DIR}/screen-recording-command.txt" 2>"${RESULT_DIR}/screen-recording-command.stderr.txt" &
    SCREEN_RECORD_PID=$!
    sleep 1
    SCREEN_RECORD_REMOTE_PID="$("$ADB_PATH" -s "$SERIAL" shell pidof screenrecord 2>/dev/null | tr -d '\r')"
    if ! kill -0 "$SCREEN_RECORD_PID" 2>/dev/null; then
        SCREEN_RECORD_RESULT="启动失败"
        printf '录屏启动失败，日志采集将继续。\n'
    else
        printf '设备录屏已启动，按回车确认现场后会停止。\n'
    fi
}

stop_recording() {
    [[ "$SCREEN_RECORD_ENABLED" == "true" && "$SCREEN_RECORD_STOPPED" != "true" ]] || return 0
    SCREEN_RECORD_STOPPED="true"
    if [[ -n "$SCREEN_RECORD_REMOTE_PID" ]]; then
        "$ADB_PATH" -s "$SERIAL" shell kill -2 $SCREEN_RECORD_REMOTE_PID >/dev/null 2>&1 || true
    fi
    if [[ -n "$SCREEN_RECORD_PID" ]] && kill -0 "$SCREEN_RECORD_PID" 2>/dev/null; then
        wait "$SCREEN_RECORD_PID" 2>/dev/null || true
    fi
    local output="${RESULT_DIR}/screen-recording.mp4"
    run_with_progress '正在导出设备录屏' '正在保存录屏文件' "$ADB_PATH" -s "$SERIAL" pull "$SCREEN_RECORD_REMOTE" "$output" >"${RESULT_DIR}/screen-recording-pull.txt" 2>"${RESULT_DIR}/screen-recording-pull.stderr.txt" || true
    if [[ -s "$output" ]]; then
        SCREEN_RECORD_RESULT="成功"
        SCREEN_RECORD_FILE="screen-recording.mp4"
        "$ADB_PATH" -s "$SERIAL" shell rm -f "$SCREEN_RECORD_REMOTE" >/dev/null 2>&1 || true
        printf '录屏已保存：screen-recording.mp4\n'
    else
        SCREEN_RECORD_RESULT="导出失败"
        printf '录屏导出失败，日志采集将继续。\n'
    fi
}

write_summary() {
    {
        printf '工具版本：%s\n' "$TOOL_VERSION"
        printf '设备序列号：%s\n' "$SERIAL"
        printf '应用包名：%s\n' "$PACKAGE_NAME"
        printf '是否启用录屏：%s\n' "$SCREEN_RECORD_ENABLED"
        printf '采集开始时间：%s\n' "${COLLECTION_STARTED_AT:-无}"
        printf '采集结束时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '录屏开始时间：%s\n' "${SCREEN_RECORD_STARTED_AT:-无}"
        printf '录屏结果：%s\n' "$SCREEN_RECORD_RESULT"
        printf '录屏文件：%s\n' "$SCREEN_RECORD_FILE"
        printf '采集完成时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    } >"${RESULT_DIR}/采集摘要.txt"
}

cleanup() {
    stop_recording
    stop_logcat
    clear_progress
}
trap cleanup EXIT INT TERM

main() {
    printf '============================================================\n'
    printf '                 Android 日志采集工具（macOS）\n'
    printf '============================================================\n'
    printf '工具版本：%s\n' "$TOOL_VERSION"
    resolve_or_install_adb || exit 1
    printf 'ADB 路径：%s\n' "$ADB_PATH"
    select_device || exit 1
    printf '已选择设备：%s\n' "$SERIAL"
    read -r -p '请打开目标 App 并保持在前台，完成后按回车：' _
    PACKAGE_NAME="$(focused_package)"
    printf '检测到前台应用包名：%s\n' "${PACKAGE_NAME:-未识别}"
    read -r -p "请输入目标应用包名，直接按回车使用检测结果 [${PACKAGE_NAME}]：" input_package
    [[ -n "$input_package" ]] && PACKAGE_NAME="$input_package"
    if confirm_recording; then SCREEN_RECORD_ENABLED="true"; fi

    local timestamp="$(date '+%Y%m%d_%H%M%S')"
    COLLECTION_STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
    RESULT_DIR="${RESULTS_ROOT}/AndroidLogs_${timestamp}_${SERIAL//:/_}"
    mkdir -p "$RESULT_DIR"
    printf '工具版本：%s\n设备序列号：%s\n应用包名：%s\n是否启用录屏：%s\n采集开始时间：%s\n' "$TOOL_VERSION" "$SERIAL" "$PACKAGE_NAME" "$SCREEN_RECORD_ENABLED" "$(date '+%Y-%m-%d %H:%M:%S')" >"${RESULT_DIR}/采集摘要.txt"

    print_step '正在启动持续 Logcat 采集'
    start_logcat
    if [[ "$SCREEN_RECORD_ENABLED" == "true" ]]; then start_recording; fi
    printf '\n请操作 App，完成普通操作或复现问题。问题出现后保持现场，回到此窗口按回车。\n'
    read -r _
    stop_recording

    print_step '正在采集当前现场信息'
    snapshot 'screen-at-problem.png' '正在截取问题现场画面' exec-out screencap -p
    snapshot 'logcat-snapshot.txt' '正在导出完整 Logcat 快照' logcat -b all -d -v threadtime '*:V'
    snapshot 'activity-lastranr.txt' '正在读取最近一次 ANR' shell dumpsys activity lastanr
    snapshot 'activity-top.txt' '正在读取前台 Activity 状态' shell dumpsys activity top
    snapshot 'window.txt' '正在读取窗口焦点状态' shell dumpsys window
    snapshot 'input.txt' '正在读取输入事件状态' shell dumpsys input
    snapshot 'cpuinfo.txt' '正在读取 CPU 占用' shell dumpsys cpuinfo
    snapshot 'meminfo-all.txt' '正在读取系统内存' shell dumpsys meminfo
    snapshot 'battery.txt' '正在读取电池状态' shell dumpsys battery
    snapshot 'connectivity.txt' '正在读取网络状态' shell dumpsys connectivity
    snapshot 'process-threads.txt' '正在读取进程线程列表' shell ps -A -T
    snapshot 'data-anr-list.txt' '正在读取 ANR 文件列表' shell ls -la /data/anr
    snapshot 'dropbox-data-app-anr.txt' '正在读取应用 ANR 历史' shell dumpsys dropbox --print data_app_anr
    snapshot 'dropbox-data-app-crash.txt' '正在读取应用崩溃历史' shell dumpsys dropbox --print data_app_crash
    if [[ -n "$PACKAGE_NAME" ]]; then
        snapshot 'package-info.txt' '正在读取应用安装信息' shell dumpsys package "$PACKAGE_NAME"
        snapshot 'app-meminfo.txt' '正在读取应用内存' shell dumpsys meminfo "$PACKAGE_NAME"
        snapshot 'app-gfxinfo.txt' '正在读取应用渲染信息' shell dumpsys gfxinfo "$PACKAGE_NAME" framestats
        snapshot 'app-exit-info.txt' '正在读取应用退出历史' shell dumpsys activity exit-info "$PACKAGE_NAME"
        local pids="$(package_pids "$PACKAGE_NAME")"
        printf '%s\n' "$pids" >"${RESULT_DIR}/app-pids-at-problem.txt"
        for pid in $pids; do snapshot "native-backtrace-${pid}.txt" "正在采集 native 线程快照，PID：${pid}" shell debuggerd -b "$pid"; done
        for pid in $pids; do "$ADB_PATH" -s "$SERIAL" shell kill -3 "$pid" >/dev/null 2>&1 || true; done
    fi
    print_step '正在生成完整 Android bugreport'
    run_with_progress '正在生成完整 Android bugreport' '设备正在整理系统诊断数据，请勿断开连接' "$ADB_PATH" -s "$SERIAL" bugreport "${RESULT_DIR}/bugreport.zip" >"${RESULT_DIR}/bugreport-command.txt" 2>"${RESULT_DIR}/bugreport-command.stderr.txt" || true
    [[ ! -s "${RESULT_DIR}/bugreport-command.stderr.txt" ]] && rm -f "${RESULT_DIR}/bugreport-command.stderr.txt"
    write_summary
    print_step '正在生成日志压缩包'
    run_with_progress '正在生成日志压缩包' '正在压缩采集结果' ditto -c -k --sequesterRsrc --keepParent "$RESULT_DIR" "${RESULT_DIR}.zip" || true
    printf '\n日志采集完成。\n结果目录：%s\n结果 ZIP：%s.zip\n' "$RESULT_DIR" "$RESULT_DIR"
    read -r -p '按回车关闭窗口：' _
}

main "$@"
