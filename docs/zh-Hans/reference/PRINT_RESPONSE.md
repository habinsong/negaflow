# 固定负片响应

[文档首页](../README.md)

## MAIN/PRINT 与派生目标

`fixed-density-linear-v6` 用于没有扫描仪配置文件的负片 `MAIN/PRINT`。密度校正值固定。片基和设置相同时，改变周围像素、裁剪或直方图不会改变相同透射率的反转结果。不应用随场景变化的 vibrance。

自定义目标和 EXPIRED 使用与 MAIN 相同的固定反转。自定义颜色在校准之后应用。EXPIRED 仅在证据满足条件时校正；没有合格证据时，其输出与 MAIN 相同。这些目标会忽略残留的扫描仪配置文件。

`B` 是实测片基透射率。通用响应的 `f` 为 1；选择胶片时使用固定的相对范围系数。`0.62` 和 `0.60D` 是通用模型的伽马和灰密度参考值，并非每种胶片或扫描仪的实测数据。Status M 密度也不能直接替代扫描仪 RGB 的特性。

```math
D_c = \log_{10}(B_c / \max(T_c,10^{-5}))
```

```math
q_c = D_c/f_c,\quad k=0.045,\quad d_t=0.60+0.62\log_{10}(k/0.18),\quad p=d_t\ln(10)/0.62
```

```math
E_c=\begin{cases}
k\,\operatorname{sgn}(q_c)(|q_c|/d_t)^p,&q_c<d_t\\
0.18\times10^{(q_c-0.60)/0.62},&q_c\ge d_t
\end{cases}
```

胶片密度趾部以相同的值和斜率连接直线段。未曝光片基在白平衡之前对应场景曝光0。这个幂函数趾部是通用设计，并非各胶片的实测曲线。片基附近的密度噪声也可能被放大。

自动校正仅在用户开启后应用。启用自动颜色时，输出趾部处理前的片基不参与中性轴采样。较强的场景偏色仍可能需要手动白平衡。

## 输出曲线

通道白平衡和曝光作用于场景线性值 `E`。白平衡后对每个通道应用相同的固定输出曲线。中间区间保留RGB比例，肩部会改变高光颜色比例。`0.045...0.70` 区间保持不变。低于 `0.045` 时加入较小的黑位底值；彩色的 `b` 为 `0.001`，黑白为 `0.0005`。高于 `0.70` 时，有理函数肩部趋近1。两个接点的斜率均为1。胶片趾部的逆变换与输出黑位处理分开进行。

```math
F(x)=x+b(1-x/0.045)^2\quad(0<x<0.045),\qquad F(x)=b\quad(x\le0)
```

自动色阶先用输出曲线的逆函数换算目标，再进行拉伸。输出黑位目标为 `0.003`，白位为 `0.95`。自动颜色排除具有不高于场景线性值 `0.004` 的通道的样本。未曝光片基为0，无需专门的边界阈值即可排除。不分析场景的目标使用固定的输入伽马参考范围。 场景线性负片的最小有效范围按实测白位的4%判断，不再使用固定曝光值0.04。

反转没有 `1.8D` 上限。透射率 `1e-5` 的下限用于保护对数运算。色域映射在输出边界处理。此阶段的各通道位于黑位底值与1之间。后续手动调整可能超出此范围。

## 其他目标

明确选择的扫描仪目标保留场景分析与旧版 `shoulder-print-response-v4`。旧固定 primitive 也保留兼容性。场景分析同样没有统一的 1.8D 上限。胶片预设使用固定相对系数，不逐帧自动归一化。

胶片 RAW 关闭 API 支持的输出色调。macOS 的 scene-linear 关闭全局和局部色调、shadow bias 与色域映射。Windows 使用 LibRaw 的线性传递函数，并与数字照片渲染区分。此设置不代表实测的传感器与胶片色彩特性，也不保证没有颜色矩阵的 RAW 输出。

## 验证与来源

测试包括独立的胶片直线段模型、不同背景中的同一色块、中性灰阶 WB 及高密度高光。合成回归不能证明真实胶片的色彩准确度。现有配方使用修正后的算法渲染，保留已存参数和原始文件。macOS 渲染器标识和缩略图后缀也区分新结果。

公式由本仓库直接实现。未复制 darktable、RawTherapee 或 NegPy 的实现代码。

## 合成输入的前后测量

在保留的v4处理上恢复1.8D范围限制和自动vibrance，重建原默认路径。固定片基后，在四种背景中比较密度为 `(0.48, 0.68, 0.70)` 的同一色块。这并非Reddit的18帧测试。色调和白平衡测试使用另一个带平滑趾部的理想胶片模型，不能证明真实胶片的准确度。

| 指标 | 原代码 | 首次修改(v5) | 复查(v6) |
|---|---:|---:|---:|
| 帧间L*跨度 | 40.49 | 0 | 0 |
| 帧间b*跨度 | 35.22 | 0 | 0 |
| −3 EV局部对比度 | 1.57 | 2.17 | 0.97 |
| 白平衡后中性梯度的最大C* | 8.89 | 0.99 | <0.001 |

v5和v6使用相同的正向趾部模型比较。暗部局部对比度接近1，表示输入一档的差异在输出中仍约为一档。L*和C*采用D50 Lab。固定片基色块仍带颜色；一致性不意味着任意密度都是中性。设置 `NEGAFLOW_RESPONSE_COMPARISON` 为JSON输出路径后运行 `FixedNegativeResponseTests` 即可保存测量。

## 内置胶卷检查

还比较了`Roll_Perforation.tiff`检测出的18帧。两种反转方法使用同一个修正后并固定的胶卷片基估计值。同密度色块的L*跨度从21.48降至<0.001，b*跨度从30.94降至<0.001。原蓝通道1.8D限制在18/18帧触发。比较沿用评论的测试思路，没有复现对方的准确设置。

检查还发现独立的片基估计问题。背光与胶片混合边缘将胶片测量值`(0.354, 0.109, 0.057)`替换成`(0.570, 0.510, 0.364)`。恢复和包络阶段现在拒绝在两个掩膜色度轴上都像光源的替换值。输出曲线也改为白平衡后逐通道应用，极大的蓝值不再牵动其他通道的亮度映射。此胶卷没有实测颜色参考。一致性及输出范围检查不代表颜色准确性验证。设置`NEGAFLOW_RESPONSE_ROLL_DIR`为输出目录，运行`testBundledRollFrameConsistency`即可保存图像及JSON。

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
