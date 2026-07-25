# GrainMend IR 要避开的胶片

[文档首页](../README.md)

红外清洁会分别读取可见光图像和红外图像，再叠加起来找缺陷。这个方式并不适合所有胶片。

- 普通彩色胶片和染料型黑白胶片可以用 IR。
- 留有银的普通黑白胶片会挡住 IR，缺陷图可能出错。
- Kodachrome 的 IR 衰减和其他彩色胶片不同，可能修补不足或修过头。

依据：

- [Epson 技术说明与限制](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson 胶片类型表](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast 对黑白和 Kodachrome 的说明](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> 无法确认胶片材质时不会自动应用 IR。错误的 IR 遮罩会把真实的图像结构当成缺陷抹掉。

## 自动应用的范围

`FilmType` 只区分彩色与黑白、负片与正片，没有信息能分辨染料型黑白与银盐，也分不出普通反转片
和 Kodachrome。

| 胶片类型 | 自动 IR | 原因 |
|---|---|---|
| 彩色负片 | 有条件 | 插件要报告 IR，并通过对齐检查 |
| 彩色正片 | 不用 | 无从判断是不是 Kodachrome |
| 黑白负片・正片 | 不用 | 分不出染料型和银盐 |

这不是说染料型黑白或普通彩色反转片绝对不能用 IR。只是现有资料无法确认胶片材质，所以不去猜。

## 对齐检查

`InfraredDefectRemoval` 会比较 IR 的渗漏纹理和 RGB 红通道，找出整数偏移，结果里带
`AlignmentDiagnostics`。

| 状态 | 含义 |
|---|---|
| `notRequested` | 调用方指明两个平面已经对齐 |
| `aligned` | 相关性过阈值，最优点在搜索范围内 |
| `insufficientTexture` | IR 里的对齐线索不够 |
| `weakCorrelation` | 相关性没过阈值 |
| `searchLimitReached` | 最优点压在搜索边界上 |

后三种不会用 `(0,0)` 代替，而是以 `alignmentUnreliable` 错误中断。最优点压在搜索边界时，不管
偏移多大都算失败。

自动测试代替不了真实设备上的 RGB/IR 对齐和逐种胶片的结果。真机确认按
[实机检查表](../validation/REAL_QA_CHECKLIST.md)里的 IR 项目做。

SANE 的设备控制和采集代码只放在独立仓库 `negaflow-scanner-sane` 里。
