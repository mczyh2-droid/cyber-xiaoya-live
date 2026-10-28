# 在 Apple 芯片的 Mac 上运行

本分支增加了 Mac 启动入口。本地舞台页、OmniVoice 语音、抖音弹幕转发和官方直播伴侣可以分别准备；真实数字人连线仍需要自己的 Vidu 账号和形象，大模型回复需要自己的 API Key。

## 启动

这台 Mac 已有 `uv`、Python 3.12 和 `ffmpeg`，项目依赖与官方 OmniVoice 模型已在本地安装。

- 双击 `启动-数字人与语音-Mac.command`：启动本地语音，等待就绪后启动舞台页。关闭时按 Control+C；它只停止自己启动的语音进程。
- 双击 `启动-Mac.command`：只启动舞台页和 Python 桥。
- 双击 `启动-语音-Mac.command`：只启动 OmniVoice。
- 配好抖音房间后，另开 `启动-抖音弹幕-Mac.command`，详见 [抖音接入说明](docs/抖音接入-macOS.md)。

舞台页：<http://127.0.0.1:8795/stage>。语音服务：<http://127.0.0.1:9877>。终端窗口需要保持运行；在终端也可执行 `bash ./启动-数字人与语音-Mac.command --no-browser`。

从 GitHub 新下载到另一台 Mac 时，先按 [Homebrew 官网](https://brew.sh/) 安装 Homebrew，再运行 `brew install uv ffmpeg`。启动器会在环境缺失时用 uv 安装 Python 和依赖。语音首次启动会下载官方模型，需要联网；后续从本地模型启动。Mac 入口面向 Apple 芯片，不适用于 Intel Mac。

## 需要自己准备的账号和内容

1. 在 [Vidu 平台](https://platform.vidu.cn/) 注册账号、创建自己的数字人形象，取得 API Key 和 `avatar_id`。连线前确认平台当前计费和余额，仓库中的旧价格不作为当前报价。
2. 准备一个 OpenAI 兼容的大模型接口账号。原项目默认使用 [DeepSeek](https://platform.deepseek.com/)，也可换自己的供应商和模型名称。
3. 在舞台页“设置”填写 Vidu Key 和形象 ID。大模型 Key 放在本地文本文件中，将其绝对路径填入 `llm.key_file`；也可使用 `DEEPSEEK_API_KEY` 环境变量。Finder 双击通常不继承终端变量，文件方式更方便。
4. 启动已安装的 [抖音直播伴侣 Mac 版](https://streamingtool.douyin.com/)，自己扫码登录并确认开播权限。添加浏览器舞台所在的程序窗口，裁剪到数字人区域；按客户端提示配置音频采集和系统权限，再做本地预览。详情见 [直播伴侣说明](docs/抖音直播伴侣-Mac.md)。
5. 提供自己的直播间房间号，按 [弹幕接入说明](docs/抖音接入-macOS.md)配置本地采集器。Cookie 如确实需要，仅在本地填写，不发到聊天或上传仓库。

`config.json` 会在首次启动时生成，不覆盖已有配置。大模型 `max_tokens` 应为正整数，样例设为 300。音色预设默认在 `assets/local/voices/mac-demo/design.json`，是设计生成的测试女声，未使用原作者的克隆音色或人物素材。

## Mac 本地语音

沿用原项目的 OmniVoice 接口，使用官方 PyTorch MPS 后端；音频编解码器由上游自动放在 CPU。独立环境在 `runtime/omnivoice/.venv`，与桥服务 `.venv` 分开。顶层安装版本固定为 `omnivoice==0.2.1`、`torch==2.8.0`、`torchaudio==2.8.0`。

官方模型在 `runtime/models/OmniVoice`，下载版本为 `c5fdb5ccb189668d56333f77ba2629f4cd7535f4`。启动时仅监听 `127.0.0.1:9877`，不启用 Gradio 公网分享；关闭自动转写，避免额外下载 Whisper。设计音色不需要参考录音；改用克隆音色时，提供自己有权使用的录音和对应原文。

默认测试预设为 16 步推理；可在 `design.json` 里将 `ns` 调为官方默认的 32，再试听速度和效果。MPS 支持不等于已验证连续直播，仍要在自己的文本长度、音色和推流条件下测试延迟。

来源：[官方 Mac 安装说明](https://github.com/k2-fsa/OmniVoice#installation)、[官方 demo 源码](https://github.com/k2-fsa/OmniVoice/blob/master/omnivoice/cli/demo.py)、[官方模型页](https://huggingface.co/k2-fsa/OmniVoice)。模型页对代码和模型权重分别列出 Apache-2.0、CC-BY-NC 许可；商业直播使用模型前需确认相应授权。

## 本机验证记录

2026-10-28，在 Apple M5、16 GB 内存、macOS 27.0.1 上完成以下本地验证：

- 合并入口启动后，舞台页、桥健康接口和 OmniVoice 服务均正常响应；按 Control+C 或只向合并入口发 TERM，两个本地服务都退出并释放端口。
- 通过桥的 `/api/tts/preview` 实际合成中文，输出为 24 kHz、单声道、16 位 WAV。首次短句用时 7.46 秒，音频长 3.23 秒；预热后“欢迎来到直播间。”用时 2.02 秒，音频长 1.79 秒。仅为两次短句测试，不能代表长时间直播表现。
- 缺少 Vidu Key 时在本地返回明确提示，不创建云端会话。LLM 的空 `max_tokens` 配置已修复为有效默认值。
- `tools/verify_macos_support.py` 的三项离线验证通过，其中弹幕使用本地模拟采集器，将 WebSocket 消息转为桥 HTTP 请求；没有接入真实抖音房间。
- 官方抖音直播伴侣已安装并启动到扫码登录页；弹幕采集器已下载、核对官方摘要并查看命令帮助，尚未启动真实采集。

语音样本与测量记录保存在本机 `runtime/verification/`，不随 Git 提交。真实 Vidu 会话、LLM 回复、抖音采集、声音回传与推流尚未验证，需要自己的账号、形象和直播间。

## 本地文件与排错

- `runtime/`：模型、语音环境、弹幕采集器、本地配置、安装包和验证输出；已被 Git 忽略。
- `config.json`、`assets/local/`、`logs/`：同样不会被正常 Git 提交。密钥文件放在 `runtime/secrets/` 或使用 `.key` 扩展名。
- `/api/health`、`/api/live/status` 可检查桥状态。没有账号时应处于 `idle`；这只能证明本地服务运行。
- `logs/bridge.log`：桥日志；通过合并入口启动语音时查看 `logs/omnivoice.log`。
- 已有配置若未选择测试音色，把 `tts.voices_dir` 指向自己的预设目录，`tts.voice` 填对应文件夹名，随后重载设置。

缺 Vidu 账号/形象和大模型 Key 时，不算真实数字人对话跑通；缺抖音登录、房间号和开播权限时，不算真实弹幕和推流跑通。
