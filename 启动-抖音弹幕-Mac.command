#!/bin/bash
# 使用本地 douyinLive 采集器和现有 Python relay；不负责开播或账号登录。
set -euo pipefail
umask 077
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$PROJECT_DIR"
COLLECTOR_DIR="$PROJECT_DIR/runtime/douyinLive"
COLLECTOR_PID=""
RELAY_PID=""

finish() {
    local result=$?
    local child_pid
    for child_pid in "$RELAY_PID" "$COLLECTOR_PID"; do
        if [[ -n "$child_pid" ]]; then
            kill "$child_pid" 2>/dev/null || true
        fi
    done
    for child_pid in "$RELAY_PID" "$COLLECTOR_PID"; do
        if [[ -n "$child_pid" ]]; then
            wait "$child_pid" 2>/dev/null || true
        fi
    done
    if [[ $result -ne 0 && $result -ne 129 && $result -ne 130 && $result -ne 143 ]]; then
        printf '\n启动未完成。请查看上方报错和 docs/抖音接入-macOS.md。\n'
        if [[ -t 0 ]]; then
            read -r -p '按回车键关闭窗口…' _ || true
        fi
    fi
    exit "$result"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${1:-}" == "--help" ]]; then
    printf '用法：./启动-抖音弹幕-Mac.command [房间标识或 https://live.douyin.com/房间标识]\n'
    printf '不传参数时读取 runtime/douyinLive/room.txt，未保存时在本地询问。\n'
    exit 0
fi

PYTHON="$PROJECT_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    printf '请先运行“启动-Mac.command”，准备 Python 环境并启动舞台桥。\n'
    exit 1
fi
if [[ ! -x "$COLLECTOR_DIR/douyinLive" ]]; then
    printf '缺少 runtime/douyinLive/douyinLive。请按接入文档下载官方 Mac 对应架构发布包。\n'
    exit 1
fi
if [[ ! -e "$COLLECTOR_DIR/config.yaml" ]]; then
    cp "$COLLECTOR_DIR/config.example.yaml" "$COLLECTOR_DIR/config.yaml"
    printf '已创建本地采集配置 runtime/douyinLive/config.yaml；Cookie 可按需在本地填写。\n'
fi

ROOM_INPUT="${1:-}"
if [[ -z "$ROOM_INPUT" && -f "$COLLECTOR_DIR/room.txt" ]]; then
    ROOM_INPUT="$(cat "$COLLECTOR_DIR/room.txt")"
fi
if [[ -z "$ROOM_INPUT" ]]; then
    read -r -p '填写自己的直播间链接或房间标识（不会提交到 GitHub）：' ROOM_INPUT
fi
ROOM="$("$PYTHON" - "$ROOM_INPUT" <<'PY'
import re
import sys
from urllib.parse import urlparse

value = sys.argv[1].strip()
if value.startswith(("https://", "http://")):
    url = urlparse(value)
    if url.hostname != "live.douyin.com":
        sys.exit("请填写 live.douyin.com 的直播间链接，不是分享短链接或昵称。")
    value = url.path.strip("/")
if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", value):
    sys.exit("房间标识无效，请使用直播间链接中 live.douyin.com/ 后面的部分。")
print(value)
PY
)"
printf '%s\n' "$ROOM" > "$COLLECTOR_DIR/room.txt"

BRIDGE="$("$PYTHON" - <<'PY'
import json
import os
from pathlib import Path

config = json.loads(Path(os.environ.get("VIDU_CONF") or "config.json").read_text(encoding="utf-8"))
port = int((config.get("bridge") or {}).get("port") or 8795)
print(f"http://127.0.0.1:{port}")
PY
)"
"$PYTHON" - "$BRIDGE" <<'PY'
import json
import socket
import sys
from urllib.request import urlopen

try:
    with urlopen(sys.argv[1] + "/api/health", timeout=3) as response:
        health = json.load(response)
    if health.get("ok") is not True:
        raise ValueError("舞台桥健康检查未通过")
except Exception:
    sys.exit("舞台桥未就绪，请先运行“启动-Mac.command”。")
if health.get("phase") != "live":
    print("提示：舞台桥尚未连线。先配置 Vidu/LLM 并开始连线，数字人才会回应弹幕。")
with socket.socket() as probe:
    if probe.connect_ex(("127.0.0.1", 1089)) == 0:
        sys.exit("1089 端口已被占用，请先停止已有采集器；本入口不会替你关闭其他进程。")
PY

printf '启动抖音采集器 :1089；日志：runtime/douyinLive/collector.log\n'
"$COLLECTOR_DIR/douyinLive" --config "$COLLECTOR_DIR/config.yaml" --port 1089 --sign-provider local \
    >> "$COLLECTOR_DIR/collector.log" 2>&1 &
COLLECTOR_PID=$!

"$PYTHON" - <<'PY'
import json
import sys
import time
from urllib.request import urlopen

for _ in range(40):
    try:
        with urlopen("http://127.0.0.1:1089/health", timeout=1) as response:
            health = json.load(response)
        if health.get("data", health).get("status") == "ok":
            break
    except Exception:
        pass
    time.sleep(0.25)
else:
    sys.exit("采集器未就绪，请查看 runtime/douyinLive/collector.log；macOS 安全提示需自行检查。")
PY

printf '转发房间 %s → %s；按 Control+C 停止本入口启动的采集器和转发器。\n' "$ROOM" "$BRIDGE"
"$PYTHON" tools/douyin_relay.py --room "$ROOM" --ws-base ws://127.0.0.1:1089 --bridge "$BRIDGE" --verbose &
RELAY_PID=$!
wait "$RELAY_PID"
