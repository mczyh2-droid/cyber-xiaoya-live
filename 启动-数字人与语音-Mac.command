#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$PROJECT_DIR"
./启动-Mac.command --prepare-only
PYTHON="$PROJECT_DIR/.venv/bin/python"
mkdir -p logs
VOICE_PID=""
BRIDGE_PID=""
cleanup() {
    "$PYTHON" - "$VOICE_PID" "$BRIDGE_PID" <<'PY'
import os, signal, sys
for value in filter(None, sys.argv[1:]):
    pid = int(value)
    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
PY
    for pid in "$VOICE_PID" "$BRIDGE_PID"; do
        [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

voice_ready() {
    curl --silent --fail --max-time 2 http://127.0.0.1:9877/config >/dev/null
}
if ! voice_ready; then
    "$PYTHON" - "$PROJECT_DIR/启动-语音-Mac.command" >logs/omnivoice.log 2>&1 <<'PY' &
import os, sys
os.setsid()
os.execv("/bin/bash", ["bash", sys.argv[1]])
PY
    VOICE_PID=$!
    printf '正在启动语音服务，日志：%s/logs/omnivoice.log\n' "$PROJECT_DIR"
    READY=0
    for ((i=0; i<600; i++)); do
        if voice_ready; then
            READY=1
            break
        fi
        if ! kill -0 "$VOICE_PID" 2>/dev/null; then
            printf '语音启动失败：\n'
            tail -n 35 logs/omnivoice.log
            exit 1
        fi
        sleep 1
    done
    if [[ "$READY" != 1 ]]; then
        printf '语音尚未就绪，请检查 logs/omnivoice.log 后重试。\n'
        exit 1
    fi
fi
printf '语音已就绪，启动数字人操作页。\n'
printf '抖音弹幕请另开“启动-抖音弹幕-Mac.command”。\n'
printf '在直播伴侣中采集舞台窗口；账号和形象配置完成后再连线。\n'
"$PYTHON" - "$PROJECT_DIR/启动-Mac.command" "$@" <<'PY' &
import os, sys
os.setsid()
os.execv("/bin/bash", ["bash", *sys.argv[1:]])
PY
BRIDGE_PID=$!
wait "$BRIDGE_PID"
