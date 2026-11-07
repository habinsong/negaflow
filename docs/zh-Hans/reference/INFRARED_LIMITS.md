# GrainMend IR 要避开的胶片

[文档首页](../README.md)

红外清洁分别读取可见光图像和红外图像，叠加后寻找缺陷。它并不适合所有胶片。

- 普通彩色胶片和染料型黑白胶片可以使用 IR。
- 普通黑白胶片保留银，会挡住 IR，可能得到错误的缺陷图。
- Kodachrome 对 IR 的衰减与其他彩色胶片不同，可能校正不足或校正过度。

依据：

- [Epson technical notes and limits](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson film type table](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast on black and white and Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> 无法确认胶片材质时，不会自动应用 IR。错误的 IR 蒙版会把真实的画面结构当作缺陷抹掉。

## 自动应用的范围

关键在于成像的物质。彩色胶片显影后只留下染料，染料对红外透明。黑白胶片是银影像，会挡住红外，校正会把照片本身读成一个大缺陷并抹掉。

| 胶片类型 | 自动 IR | 原因 |
|---|---|---|
| 彩色负片 | 有条件 | 染料影像。插件必须报告 IR，且对位检查要通过 |
| 彩色正片 | 有条件 | 染料影像。条件与彩色负片相同 |
| 黑白负片和正片 | 关闭 | 银影像会挡住红外 |

`FilmType` 无法区分染料型黑白和银黑白，也无法区分 Kodachrome 和普通幻灯片。这两种情况交给用户：

- 染料型黑白按黑白扫描，所以即使胶片允许，IR 也保持关闭。不会只凭胶片类型去猜。
- Kodachrome 是彩色幻灯片，所以会提供 IR。它的染料对红外的衰减与 E-6 不同，缺陷可能校正不足或过度。结果不对就关掉该图层。

## 对位检查

`InfraredDefectRemoval` 把 IR 中的漏光纹理与 RGB 的红通道比较，寻找整数偏移。结果带有 `AlignmentDiagnostics`。

| 状态 | 含义 |
|---|---|
| `notRequested` | 调用方说明两个平面已经对齐 |
| `aligned` | 相关性超过阈值，最佳点在搜索范围内 |
| `insufficientTexture` | IR 中可用于对位的线索太少 |
| `weakCorrelation` | 相关性未达阈值 |
| `searchLimitReached` | 最佳点落在搜索边界上 |

后三种以 `alignmentUnreliable` 错误停止，不会用 `(0,0)` 代替。最佳点落在搜索边界上，无论偏移多大都算失败。

自动测试不能代替在真实设备上、按胶片逐一做的 RGB/IR 对位检查。这些检查要用真实胶片手工完成。

SANE 设备控制和采集代码只在单独的 `negaflow-scanner-sane` 仓库里。
