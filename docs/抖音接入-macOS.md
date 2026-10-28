# Mac 上接入抖音直播

本项目需要两条链路：直播伴侣把浏览器中的数字人画面推到抖音；弹幕采集器把观众消息送回数字人。账号、直播间和需要时使用的 Cookie，由你在本机填写。当前没有完成登录、真实开播或真实弹幕验证。

## 已准备和仍需准备的内容

- 抖音弹幕采集器采用 [jwwsjlm/douyinLive 官方 v2.3.2 发布包](https://github.com/jwwsjlm/douyinLive/releases/tag/v2.3.2)。本机已下载 `darwin-arm64` 压缩包，核对官方 SHA-256 后解压到 `runtime/douyinLive/`；文件检查确认为 arm64 Mac 可执行程序，尚未运行。使用发布包不需要安装 Go。
- 本机检查时，PATH 及常见安装位置未找到 Go；Applications 和 Spotlight 中未找到 OBS。没有安装这两个软件。
- 需要先准备自己的 Vidu 形象及 API Key、LLM 接口及 Key，并在舞台页设置中填写。语音服务也需就绪，才能让数字人出声。
- 抖音账号是否能开播、直播伴侣是否允许当前账号开播，应在官方客户端登录后以账号页面的实际结果为准。

如果在另一台 Mac 上使用，`runtime/` 不会随 Git 仓库提供。Apple 芯片应从上面的官方发布页下载 `douyinLive-v2.3.2-3b0c44876c2a-darwin-arm64.tar.gz` 和对应 `checksums.txt`，核对 SHA-256 后解压到 `runtime/douyinLive/`；该目录应直接包含 `douyinLive`、`config.example.yaml` 和 `LICENSE`。此包的官方 SHA-256 是：

```text
7e54371b28f547d94b45d2067689b07b389b291a341b1aa867c2224e989710ff
```

可用 `shasum -a 256 下载的压缩包路径` 检查摘要。Intel Mac 需要下载 `darwin-amd64` 包并使用它自己的摘要，不能使用上面的 arm64 摘要。

## 先用抖音直播伴侣推画面

[抖音官方 Mac 版说明](https://streamingtool.douyin.com/docs/8uxkey2t_mac)确认：支持 Intel 与 Apple 芯片、macOS 13 及以上，已支持桌面、程序窗口等素材采集与开播推流。

1. 安装并打开官方 Mac 版抖音直播伴侣，由你本人登录。
2. 运行项目根目录的 `启动-Mac.command`，配置 Vidu 和 LLM 后，在浏览器舞台页开始连线。
3. 在直播伴侣中添加程序窗口素材，选择数字人舞台页所在的浏览器窗口，并按系统提示授予所需屏幕采集权限。调整裁剪范围，避免把设置区及账号信息播出去。
4. 在客户端预览中确认画面和声音。窗口画面采集本身不能证明数字人声音已送进直播伴侣；具体音频来源与权限要在本机确认。
5. 账号满足客户端要求后，再由你本人操作开播。

这里核实的是官方支持范围；当前还没有验证本机窗口采集、声音回传或正式推流。

## 把弹幕送回数字人

### 填写直播间

浏览器打开自己的直播间，例如 `https://live.douyin.com/你的房间标识`。使用域名后面的房间标识，或把完整的该类链接交给启动器。不要填昵称，也不要直接填分享短链接。标识的含义以 [上游 CLI 文档](https://github.com/jwwsjlm/douyinLive/blob/v2.3.2/docs/cli.md) 为准。

先保持 `启动-Mac.command` 的窗口运行，再双击 `启动-抖音弹幕-Mac.command`。首次会在终端询问直播间；也可以在项目目录运行：

```bash
./启动-抖音弹幕-Mac.command https://live.douyin.com/你的房间标识
```

启动器把标识保存在本地 `runtime/douyinLive/room.txt`。换房间时，可编辑该文件，或通过命令参数传入新标识。

入口会启动采集器，再启动现有的 `tools/douyin_relay.py`。固定使用 `1089` 端口，桥地址从本地 `config.json`（或 `VIDU_CONF`）读取。上游采集器原生默认端口是 `1088`；此入口用命令参数统一为 `1089`，与项目 relay 保持一致。按 `Control+C` 会停止该入口启动的采集器和转发器。

若 1089 已被占用，入口会停止并提示，不会关闭其他进程。采集器日志保存在 `runtime/douyinLive/collector.log`。

### Cookie 由你本人按需填写

上游允许先使用匿名会话，**Cookie 并非所有直播间都必填**。如果遇到匿名访问限制、状态无法确认、验证码或收不到消息，再按 [上游配置说明](https://github.com/jwwsjlm/douyinLive/blob/v2.3.2/docs/configuration.md) 配置自己账号的有效 Cookie。

首次运行弹幕入口时，会从官方示例生成本地 `runtime/douyinLive/config.yaml`，不会写入任何真实 Cookie。需要时：

1. 由你本人在浏览器打开 `https://live.douyin.com` 并登录。
2. 打开开发者工具的 Network 面板，找到发往抖音的请求，在请求头中复制 `Cookie`。
3. 在本机编辑 `runtime/douyinLive/config.yaml`，保留其他配置，只填写：

   ```yaml
   cookie:
     use_stored: true
     douyin: "在这里填写自己的完整 Cookie"
   ```

4. 停止并重新启动弹幕入口。

Cookie 留在本机，不要发到聊天或提交到 GitHub。`runtime/` 用于本地程序、配置和日志，不应入库。上游还有按房间配置 Cookie 的方式，需要时按官方文档设置。

当前 relay 没有实现上游 `api.key` 的握手认证；这条本地链路应保持示例中的 `api.key` 为空。上游程序监听所有网络接口，此入口没有修改它的监听实现，不要把采集端口转发到公网。配置 `websocket.path` 时应保留 `/ws`，与现有 relay 一致。

### 判断到哪一步了

- `/api/health` 正常：只说明本地舞台桥运行。
- 终端出现 `[relay] 已连接`：只说明转发器连上了本地采集器。
- 上游系统状态 `ROOM_ONLINE`：表示已建立抖音上游连接；未开播时应等待，持续 `ROOM_STATUS_UNKNOWN` 则检查网络、Cookie 及访问限制。
- 数字人实际回应一条本直播间弹幕：才证明弹幕进入桥、LLM、语音和数字人会话的实际链路。桥还没开始连线时，即使转发 HTTP 返回 200，也可能是 `reason=idle`，不会播报。

现有 relay 的聊天、普通礼物和嵌套礼物字段与 v2.3.2 源码一致。该版本的 `WebcastLightGiftMessage` 使用 `giftInfo` / `giftStruct`，没有普通礼物的 `user` / `gift` 字段，也没有发送者昵称；现有 relay 会忽略它，不能据此实现可靠的轻礼物点名感谢。字段见[上游锁定的 protobuf 定义](https://github.com/jwwsjlm/douyinlive-proto/blob/v0.1.3/protobuf/new_douyin.proto#L3515-L3540)。

relay 也不转发点赞、进场等所有类型。上游[明确不保证所有业务消息都能收到或完整解析](https://github.com/jwwsjlm/douyinLive/tree/v2.3.2)。

## OBS 可选路线

OBS 在 macOS 支持[浏览器来源](https://obsproject.com/kb/browser-source)，可用于编排网页画面或本地录制。本机尚未安装或验证 OBS，OBS 内嵌浏览器能否订阅本项目的 AliRTC/WebRTC 画面与声音也尚未实测。

抖音实际开播优先使用上面的官方 Mac 直播伴侣路线。是否有其他推流入口，要以你账号的官方页面为准；这里没有获取或验证 OBS 直推抖音的权限或推流地址。

## 当前验证边界

已核实官方 Mac arm64 发布包、配置参数和 relay 消息字段；本地下载并校验采集器后，只执行了 `--help` 查看参数，没有启动采集服务或读取登录凭据。新入口通过 Bash 语法、帮助输出及内嵌 Python 语法检查；relay 通过按上游字段构造的离线消息样例检查。直播伴侣已启动到扫码登录页，尚未登录。真实开播、Cookie 有效性、弹幕与礼物完整性、断线恢复以及音画同步仍需在你的直播间验证。
