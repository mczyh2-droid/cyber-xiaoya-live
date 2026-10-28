#!/bin/bash
# OmniVoice 官方 MPS 后端；仅监听本机，不创建公网分享链接。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$PROJECT_DIR"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf '此入口需要 Apple 芯片的 Mac。\n'
    exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
    printf '请先安装音频工具：brew install ffmpeg\n'
    exit 1
fi
VOICE_ENV="$PROJECT_DIR/runtime/omnivoice/.venv"
if [[ ! -x "$VOICE_ENV/bin/omnivoice-demo" ]] || ! "$VOICE_ENV/bin/python" - <<'PY' >/dev/null 2>&1
from importlib.metadata import version
from pathlib import Path
from packaging.requirements import Requirement
for line in Path("requirements-omnivoice-macos.txt").read_text().splitlines():
    if line.strip() and not line.lstrip().startswith("#"):
        requirement = Requirement(line)
        assert version(requirement.name) in requirement.specifier
import torch, torchaudio, omnivoice, gradio, transformers, soundfile
PY
then
    if ! command -v uv >/dev/null 2>&1; then
        printf '请先安装 uv：brew install uv\n'
        exit 1
    fi
    if [[ ! -d "$VOICE_ENV" ]]; then
        uv venv --python 3.12 "$VOICE_ENV"
    fi
    uv pip install --python "$VOICE_ENV/bin/python" -r requirements-omnivoice-macos.txt
fi

MODEL_DIR="$PROJECT_DIR/runtime/models/OmniVoice"
if ! "$VOICE_ENV/bin/python" - <<'PY'
import json
from pathlib import Path
root = Path("runtime/models/OmniVoice")
required = ["model.safetensors", "config.json", "tokenizer.json", "tokenizer_config.json",
            "chat_template.jinja", "audio_tokenizer/model.safetensors",
            "audio_tokenizer/config.json", "audio_tokenizer/preprocessor_config.json"]
try:
    for name in required:
        path = root / name
        assert path.is_file() and path.stat().st_size > 0
        if name.endswith(".json"):
            json.loads(path.read_text())
except (AssertionError, OSError, ValueError):
    raise SystemExit(1)
PY
then
    printf '首次下载 OmniVoice 官方模型，请保持联网。\n'
    "$VOICE_ENV/bin/python" - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="k2-fsa/OmniVoice",
    revision="c5fdb5ccb189668d56333f77ba2629f4cd7535f4",
    local_dir="runtime/models/OmniVoice",
    ignore_patterns=["*.md", ".gitattributes"],
)
PY
fi

export GRADIO_ANALYTICS_ENABLED=False
export HF_HUB_OFFLINE=1
export PYTORCH_ENABLE_MPS_FALLBACK=1
printf '启动 Mac 本机语音：MPS，http://127.0.0.1:9877\n'
printf '首次合成需要预热；按 Control+C 停止。\n'
exec "$VOICE_ENV/bin/omnivoice-demo" --model "$MODEL_DIR" --device mps \
    --ip 127.0.0.1 --port 9877 --no-asr "$@"
