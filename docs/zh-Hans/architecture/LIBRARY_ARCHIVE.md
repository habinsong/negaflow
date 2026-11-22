# 图库保存归档

[文档首页](../README.md)

目录备份用来让应用重新运行，不含原始照片。两个平台都使用 `.negaflowarchive`，但 macOS 和 Windows 的封装格式和包含内容不同。

> [!WARNING]
> 归档生成失败时，原始文件、第三方 XMP、正在运行的目录以及已有归档都不会被改动。

## macOS 归档（BagIt 文件夹）

在 macOS 上，`.negaflowarchive` 是遵循 [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html) 结构的文件夹，把目录状态和被引用的照片一起打包。

| 包含 | 不含 |
|---|---|
| 可移植的目录 JSON | 正在运行的 SQLite 文件 |
| 被引用的原始文件和剩余的 IR 原始文件 | 缩略图和预览 |
| GrainMend 瑕疵配方 | 可以重建的 GrainMend 缓存 |
| 虚拟副本与共享原始文件的关联 | 导出的文件 |

内容文件和标签文件分别生成 SHA-256 清单（`manifest-sha256.txt` 和 `tagmanifest-sha256.txt`）。`negaflow-archive.json` 把画幅 ID 与存储的文件 ID 连起来，同一个原始文件的虚拟副本共用一份存储。

如果目标路径已存在，写入会拒绝覆盖。以下检查全部通过后，临时文件夹才会移到最终路径：

1. 当前应用能安全读取目录。
2. 原始文件和 IR 输入是普通文件，复制期间大小和修改时间不变。
3. 所有需要的 GrainMend 瑕疵配方都能读取。
4. SHA-256 哈希（`manifest-sha256.txt`、`tagmanifest-sha256.txt`）、字节数、文件清单和 `Payload-Oxum` 一致。
5. 画幅与原始文件、IR 文件、GrainMend 配方之间的关联与目录一致。

失败时只删除做到一半的临时文件夹。

## Windows 归档（ZIP 文件）

在 Windows 上，`.negaflowarchive` 是存放目录和瑕疵状态的 ZIP 归档，不复制原始照片文件。

| 包含 | 不含 |
|---|---|
| `library.sqlite` | 原始照片文件和 IR 原始文件 |
| `defects/*` 瑕疵配方 | 缩略图、预览和可重建的缓存 |
| `archive.json`（记录每个条目的字节数和 SHA-256 哈希） | 导出的文件 |

Windows 先把归档写入临时文件，校验通过后再原子替换目标文件。构建失败时删除临时文件，目标位置已有的归档保持原样。

## 局限

macOS 和 Windows 的 `.negaflowarchive` 使用不同的格式和目录架构，归档在同一平台的机器之间迁移。原始格式原样保留，不为长期兼容做转换。PREMIS 保存事件与代理记录，以及向推荐格式的迁移，不在 v1 范围内。

一份归档不等于保存计划。请把副本放在其他介质和其他地点，并定期重新核对哈希。

来源：

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
