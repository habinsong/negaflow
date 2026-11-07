# 图库保存归档

[文档首页](../README.md)

目录备份用来让应用重新运行，不含原始照片。`.negaflowarchive` 归档把它们放进同一个包里。

| 包含 | 不含 |
|---|---|
| 可移植的目录 JSON | 正在运行的 SQLite 文件 |
| 被引用的原始文件和剩余的 IR 原始文件 | 缩略图和预览 |
| 仍然需要的 GrainMend 编辑历史 | 可以重建的 GrainMend 缓存 |
| 虚拟副本与共享原始文件的关联 | 导出的文件 |

> [!WARNING]
> 归档生成失败时，不会覆盖已有归档。原始文件、第三方 XMP 和正在运行的目录也不会被改动。

## 包结构与检查

包遵循 [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html) 的文件夹结构。内容文件和管理文件的 SHA-256 清单分开写。`negaflow-archive.json` 把画幅 ID 与存储的文件 ID 连起来。同一个原始文件的虚拟副本共用一份存储。

以下检查全部通过后，临时文件夹才会移到最终路径：

1. 当前应用能安全读取目录。
2. 原始文件和 IR 输入是普通文件，复制期间大小和修改时间不变。
3. 所有需要的 GrainMend 记录都能读取。
4. SHA-256、字节数、文件清单和 `Payload-Oxum` 一致。
5. 画幅与原始文件、IR 文件、GrainMend 记录之间的关联与目录一致。

失败时只删除做到一半的临时文件夹，已有归档保持原样。

## 局限

原始格式原样保留，不为长期兼容做转换。PREMIS 保存事件与代理记录，以及向推荐格式的迁移，不在 v1 范围内。

一份归档不等于保存计划。请把副本放在其他介质和其他地点，并定期重新核对哈希。

来源：

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
