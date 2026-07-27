# 项目状态

[文档首页](../README.md)

这份文档记录当前的实现和验证状态。README 讲产品和用法，docs 里的各篇文档负责细节规格和决定。

## 基本信息

| 项目 | 当前值 |
|---|---|
| 版本 | `1.0.1` |
| 构建 | `1` |
| 操作系统 | macOS 14 以上 |
| 工作流程 | 导入・扫描 → 显影 → 导出 |
| 默认显影 | `main`，手动校正 |
| 原件 | 不修改原件文件和第三方附属文件 |

> [!WARNING]
> 只凭 `1.0.1` 这个标注和构建成功，不代表已确认真实扫描仪兼容性、最终画质、外部签名或公证。
> 实机与发布批准另外记在下面的检查表里。

## 已实现且有自动检查的范围

- 非破坏性目录、附属文件、虚拟副本、收藏、胶卷、星级、选取与排除
- 重复导入、原件重新链接、从图库移除、把原件移到废纸篓
- 目录健康检查、进程锁、恢复阻断、备份世代、还原演练、选中画面的重新显影
- 显影与导出的公共路径、元数据、处理历史、编辑记录、多文件输出
- 跟随显影完成与重处理状态刷新导出按钮的低频观察边界
- 扫描仪插件的发现与批准、功能检查、协议 v1/v2、取消、时间限制、输出上限
- 插件的属主与权限检查，以及临时输出的校验
- CLI 扫描仪 JSON 与应用界面功能的一致性检查
- 辅助功能、选择状态、字号、窗口尺寸适配、界面状态恢复
- 比较与浏览视图、照片堆叠、重复候选确认
- 收纳原件与 IR、GrainMend 记录、虚拟副本关系的 BagIt 保存归档
- 渲染记录 v3 用 SHA-256 连接原件与输出
- IR 对齐诊断与胶片兼容性限制
- 扫描仪噪声的重复测量与独立验证规格
- 内存紧张时的画面缓存清理
- CI 中严格的 Swift 并发诊断

## 目录

主存储是 `library.sqlite`。
已有的 `library.json` 以只读方式打开，检查健康状态并备份后，迁到临时 SQLite。
只有两份目录的内容和 SQLite 完整性都对得上，才切换主存储。

续做中断的工作时，若证据对不上就以关闭状态失败。
JSON 仍作为可迁移的备份与归档交换格式保留，但不会同时使用两个主存储。

细节见[目录存储结构](../architecture/CATALOG_STORAGE.md)。

## 扫描仪

本仓库里只有与设备无关的外部进程宿主和 JSON 规格。SANE 的实现、依赖、配置和分发文件都不放。
那部分代码在独立的 GPL 项目
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) 里。

应用只显示已安装插件报告的功能，不会靠型号名去猜功能。
除非用户选择演示，否则不会用假的扫描仪顶替。

详细规格：

- [扫描仪插件结构](../architecture/SCANNER_PLUGINS.md)
- [扫描仪 CLI JSON](../reference/CLI_JSON.md)

## 构建与发布

<details>
<summary>本地检查与发布命令</summary>

本地检查：

```bash
bash scripts/ci-gate.sh
bash scripts/run-app.sh build
bash scripts/run-gui-e2e.sh  # 需要 macOS 的 Automation Mode
```

生成发布文件：

```bash
bash scripts/build-release.sh
```

</details>

跑一次 `build-release.sh`，会分别构建 Apple Silicon（`arm64`）和 Universal（`arm64`、`x86_64`）
应用，并生成 ZIP、PKG、DMG、dSYM 和 SHA-256 清单。
本地用临时签名；真正分发需要 Developer ID Application 和 Developer ID Installer 两种签名。

手动的 `Distribution` workflow 使用受保护的 Developer ID 和 App Store Connect API 密钥。
它把应用归档、DMG 和 PKG 送给 Apple，贴上公证票据后，再次核对校验和与 Gatekeeper。
没有真实的 workflow 运行和 Apple 的回应，就不会说外部签名和公证已经成功。

## 性能测量

性能检查覆盖目录、图库检索、高分辨率调整、GrainMend 区域处理，以及真实像素的整卷。

某台 Mac 上最近的 Release 测量：

| 操作 | 结果 |
|---|---:|
| 50,000 画面 JSON 读取 p95 | 约 7.4 秒 |
| 50,000 画面 SQLite 读取 p95 | 约 7.4 秒 |
| 50,000 画面 SQLite 提交 p95 | 约 3.7 秒 |
| 无变更的 SQLite 提交 p95 | 约 3.9 秒 |
| 50,000 画面过滤与名称排序 | 约 158 ms |
| 48 张快速预览 | 约 10.6 秒，最大 RSS 约 504 MiB |
| 48 张显影 | 约 20.9 秒，最大 RSS 约 1,012 MiB |

这些数值不保证别的 Mac 的性能。新的测量用下面的命令生成。

```bash
bash scripts/run-performance-suite.sh
```

`Config/performance-budget-v1.json` 里 macOS 26 arm64 的限制，是为了抓大幅回退而设的宽上限。
通过并不等于所有延迟都称得上好体验。

## GrainMend 测量

FILM-R v2 素材用 DOI、44 对、437,570,872 字节和 Figshare 的 MD5 信息固定下来。

发布用的自动路径采用灵敏度 0.7 加过检安全线。下面是与此前回归基准 3.0 的对比。

| 指标 | 此前基准 3.0 | 安全自动 0.7 |
|---|---:|---:|
| 加权变差像素 | 0.792% | 0.017% |
| 加权改变像素 | 0.794% | 0.043% |
| 平均 PSNR 变化 | -1.688 dB | +0.466 dB |
| 最差 PSNR 变化 | -18.952 dB | -1.338 dB |
| 改善 / 变差 / 持平 | 11 / 33 / 0 | 34 / 6 / 4 |

除观测值回归检查外，还检查这些绝对下限：平均和中位 PSNR 不低于 0 dB、变差不超过 10 张、最差不低
于 -1.5 dB。
自动安全线在 3 张上停止了修复，这时会引导用户改用引导模式。

FILM-R 只验证 GrainMend RGB 的自动路径。
它不能作为等同硬件 IR，或真实扫描仪 RGB・IR 对齐质量的依据。

手动的 `GrainMend corpus` workflow 会取回 44 对素材，跑 Release 默认路径，然后做回归检查并上传报
告。

## 自动检查解决不了的项目

- 支持的窗口尺寸和辅助功能设置下的最终界面确认
- 真实插件和扫描仪
- 真实负片与 IR 的画质
- Developer ID、公证、Gatekeeper、在干净 Mac 上安装
- 所有受支持 Mac 上的性能

最终画面和实机确认由用户负责。
不拿构建成功当替代，结果记在 [实机检查表](../validation/REAL_QA_CHECKLIST.md)里。

## 各项内容以哪份文档为准

| 内容 | 基准文档 |
|---|---|
| 当前实现与验证 | 本文档 |
| 扫描仪宿主规格 | [扫描仪插件结构](../architecture/SCANNER_PLUGINS.md) |
| 扫描仪 CLI JSON | [扫描仪 CLI JSON](../reference/CLI_JSON.md) |
| 目录的保存方式 | [目录存储结构](../architecture/CATALOG_STORAGE.md) |
| 扫描仪配置文件的发布标准 | [扫描仪配置文件质量判定](../reference/PROFILE_QUALITY_GATE.md) |
| GrainMend 的实现与限制 | [GrainMend](GRAINMEND.md) |
| 最终画面与实机批准 | [实机检查表](../validation/REAL_QA_CHECKLIST.md) |
| 安装与用法 | 仓库根目录的 README 文件 |
