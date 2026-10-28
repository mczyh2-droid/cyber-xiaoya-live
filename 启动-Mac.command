#!/bin/bash
# 双击启动；也可在终端传入 --no-browser、--port 等 src.main 参数。
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$PROJECT_DIR"

finish() {
    local result=$?
    if [[ $result -ne 0 ]]; then
        printf '\n启动未完成（退出码 %s），请查看上方报错。\n' "$result"
        if [[ -t 0 ]]; then
            read -r -p '按回车键关闭窗口…' _ || true
        fi
    fi
    exit "$result"
}
trap finish EXIT

require_uv() {
    if ! command -v uv >/dev/null 2>&1; then
        printf '缺少 uv，请先在终端执行：brew install uv\n'
        printf '安装后重新双击此文件。\n'
        exit 1
    fi
}

printf '项目目录：%s\n' "$PROJECT_DIR"
if ! command -v ffmpeg >/dev/null 2>&1; then
    printf '\n缺少 ffmpeg，语音合成和音频点播暂不可用。\n'
    printf '请在终端执行：brew install ffmpeg\n\n'
fi

if [[ ! -d .venv ]]; then
    require_uv
    printf '首次启动：创建 Python 3.12 环境（需要网络）…\n'
    uv venv --python 3.12 .venv
fi
PYTHON="$PROJECT_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    printf '现有 .venv 中找不到可用的 Mac Python。请先检查或移走该目录后重试。\n'
    exit 1
fi
if ! "$PYTHON" -c 'import sys; sys.exit(sys.version_info[:2] != (3, 12))'; then
    printf '现有 .venv 需要使用 Python 3.12；启动器不会覆盖已有环境。\n'
    exit 1
fi

# 检查 requirements.txt 的实际安装版本；已满足时不重复安装。
if ! "$PYTHON" - <<'PY' >/dev/null 2>&1
from importlib.metadata import version
from pathlib import Path
from packaging.requirements import Requirement

for line in Path("requirements.txt").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    requirement = Requirement(line)
    if requirement.marker and not requirement.marker.evaluate():
        continue
    installed = version(requirement.name)
    if requirement.specifier and installed not in requirement.specifier:
        raise RuntimeError(f"{requirement.name} 版本不符合要求")

# 同时发现安装中断等情况下缺失的间接依赖。
import fastapi, uvicorn, httpx, websockets, certifi, multipart, numpy, gradio_client
PY
then
    require_uv
    printf '安装缺少或版本不符的运行依赖（需要网络）…\n'
    uv pip install --python "$PYTHON" -r requirements.txt
fi

if [[ ! -e config.json ]]; then
    "$PYTHON" - <<'PY'
import json
from pathlib import Path

config = json.loads(Path("config.example.json").read_text(encoding="utf-8"))
llm = config.setdefault("llm", {})
if llm.get("max_tokens") in (None, ""):
    llm["max_tokens"] = 300
voices = Path("assets/local/voices").resolve()
preset = voices / "mac-demo" / "design.json"
preset.parent.mkdir(parents=True, exist_ok=True)
if not preset.exists():
    preset.write_text(json.dumps({"label": "Mac 测试女声", "gender": "Female / 女",
                                  "age": "Young Adult / 青年", "ns": 16},
                                 ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
config.setdefault("tts", {}).update({"voices_dir": str(voices), "voice": "mac-demo"})
with Path("config.json").open("x", encoding="utf-8") as output:
    json.dump(config, output, ensure_ascii=False, indent=2)
    output.write("\n")
Path("config.json").chmod(0o600)
print("已生成 config.json，请在舞台页设置中填写自己的凭据和形象。")
PY
fi

if [[ "${1:-}" == "--prepare-only" ]]; then
    exit 0
fi

printf '\n启动本地桥；按 Control+C 停止。\n'
"$PYTHON" -m src.main "$@"
