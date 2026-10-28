# 抖音直播伴侣 Mac 版

本页核实日期：2026-10-28。官方已提供 Mac 版；本项目可以先在浏览器显示数字人，再通过直播伴侣的程序窗口采集接入。实际画面、声音和弹幕联动仍需本机验收。

## 官方入口

- [抖音直播伴侣官网](https://streamingtool.douyin.com/)
- [官方 Mac 版上线通知](https://streamingtool.douyin.com/docs/8uxkey2t_mac)
- [官网 Mac 下载入口](https://streamingtool.douyin.com/api/invoke/download-mac?arch=universal&isAutoUpdate=1)

官方通知写明：支持 Intel 和 Apple 芯片，要求 macOS 13 及以上；当前支持摄像头、桌面、程序窗口和图片素材采集及推流。不能据 Windows 版说明认定 Mac 版具有全部同名功能。

官网公开页面脚本使用 `arch=universal` 下载入口，没有向 Apple Silicon 单独提供 arm64 按钮。该入口可能按最新版本跳转，固定版本下载链接只代表本次实际收到的文件。

## 本次下载

安装包下载到 `runtime/downloads/`。该目录已被项目 `.gitignore` 忽略，不应将安装包提交到 GitHub。经过只读签名与架构检查后，将官方应用复制到用户应用目录；随后启动检查已到扫码登录页，没有登录或开始直播。

实际 GET 下载响应：

- 文件：`douyin-webcast-mate-v10.0.5-master-3a3a2f62-darwin-universal.dmg`
- 字节数：455,179,371（约 455 MB；约 434 MiB）
- [本次官方 CDN 下载链接](https://lf3-cdn-tos.bytegoofy.com/obj/tron-demo/7637411201357453594/533515925/10.0.5/darwin-universal/douyin-webcast-mate-v10.0.5-master-3a3a2f62-darwin-universal.dmg)
- 下载元数据保存在同目录同名 `.dmg.json` 文件中，记录入口、最终 URL、字节数及 SHA-256。

文件已下载完成。SHA-256：

```text
c458f305952838e872a24e5dd95df1ceadeffcd451ac05a8c1c43f4ed44de91b
```

本机只读检查结果：

- DMG 内包含 `Douyin Webcast Mate.app` 和指向 `/Applications` 的快捷方式。
- 主程序为 Mach-O universal，已用 `lipo -archs` 确认同时包含 `x86_64 arm64`，可用于 Apple Silicon。
- Bundle ID：`com.bytedance.webcastmate.mac`；版本：`10.0.5`；最低系统：`13.0`。
- DMG 与应用签名主体：`Developer ID Application: Beijing Douyin Technology Co., Ltd. (3JTPEA4UU7)`。
- `spctl` 检查 DMG 返回 `accepted` / `Notarized Developer ID`；应用 `codesign --verify --deep --strict` 通过，带已装订的公证票据。
- 只读挂载时镜像 CRC 校验通过；完成结构检查后已卸载镜像。

签名与架构检查说明下载文件完整且签名可验证；不代表本机登录、采集、音频或推流已测试通过。

本次 HEAD 和 GET 请求曾返回不同版本，获取最新版时优先从官网入口重新下载。

## 本机安装位置

已先检查目标不存在，再复制官方应用到：

```text
/Users/mac-zyh/Applications/Douyin Webcast Mate.app
```

本次安装版本：`10.0.5`。安装后的应用再次通过 `codesign --verify --deep --strict` 和 Gatekeeper `spctl` 检查，后者返回 `accepted` / `Notarized Developer ID`。启动检查已显示扫码登录及验证码登录页，尚未输入手机号、扫码或接受登录协议；Gatekeeper 设置没有改动。

## 需要用户亲自完成

1. 从上述用户应用目录启动客户端，使用自己的抖音账号扫码或按客户端提供的方式登录。不要将二维码授权、验证码或账号密码写入项目。
2. 在客户端核实账号是否具备电脑开播权限，并按官方提示完成申请。是否需要实名认证、手机端前置操作或其他条件，以该账号在官方客户端显示的要求为准。
3. 按 macOS 提示允许所需的屏幕与系统音频录制、麦克风等权限。
4. 先添加数字人浏览器窗口作为采集来源，在预览中检查画面、语音和字幕，再由用户决定正式开播。

[官方开播问题说明](https://streamingtool.douyin.com/docs/qna_start_error)要求查看软件内公告确认开播条件。不同官方历史页面中粉丝门槛描述存在差异，本页不据此承诺账号一定能开播。

本次只启动到登录页，没有扫码登录、实名认证、申请开播权限或开播操作。
