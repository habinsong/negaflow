# 渲染记录

[文档首页](../README.md)

旁注文件里的 `renderManifest` 用 SHA-256 把源文件、编辑值和最终文件连在一起。不记录文件路径。

> [!IMPORTANT]
> `renderManifest` 记录的是文件与设置之间的哈希关系。它没有数字签名和证书，所以不是 C2PA Content Credentials。

## v3 包含的内容

- 源文件字节数、SHA-256 和算法名 `sha-256`
- 实际使用的渲染输入
- GrainMend 缓存文件或内存输入的校验范围
- 显影、GrainMend 和导出设置的 SHA-256
- 扫描仪配置文件的 SHA-256
- 解码器来源和 Chroma Engine 渲染器版本
- 最终文件的 SHA-256、字节数、像素尺寸和格式

编码器写完后，用 ImageIO 重新打开文件确认像素尺寸，并计算整个文件的哈希。旁注文件在这之后才写入。v3 校验失败时，结果不会作为完整的输出集发布。

## GrainMend 输入

- `cleanedMemory`：内存中的像素没有标准哈希，所以校验范围记为 `sourceAndDevelopRecipe`。GrainMend 编辑历史的 SHA-256 始终包含在内。
- `cleanedFile`：对 GrainMend 缓存文件整体和编辑历史都计算哈希。

v1 和 v2 文件仍可打开。当时不存在的哈希不会事后补上。

## 与 C2PA 的区别

这里没有数字签名、证书、信任链和内嵌的声明存储，只有可以核对的 SHA-256 值。C2PA 的硬绑定与处理历史、PREMIS 的完整性思路作为参考。

来源：

- [C2PA Content Credentials 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html)
- [C2PA hard-binding guidance](https://spec.c2pa.org/specifications/specifications/2.4/guidance/Guidance.html)
- [PREMIS preservation metadata](https://www.loc.gov/standards/premis/)
- [Apple Image I/O orientation and image properties](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
