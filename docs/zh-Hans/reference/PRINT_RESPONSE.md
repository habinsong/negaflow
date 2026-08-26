# 固定印相响应

[文档首页](../README.md)

放在哪里：

- Swift：`Sources/Chromabase/Film/NegativeInversion.swift` 里的 `PrintResponse`
- Metal：`negativeInvert` 内核
- 固定检查：
`NegativeInversionCalibrationTests.testPrintResponseDerivesFromPhotometricContract`

## 曲线

胶片特性曲线把曝光和密度的关系分成趾部、直线部和肩部来说明。
negaflow 用 stretched exponential 曲线近似密度域里的肩部。

```math
\begin{aligned}
D &= \log_{10}\left(\frac{D_{\min}}{T}\right) \\
d &= \frac{D}{d_{\max}} \\
\log_{10}(P) &= y_{\mathrm{ceil}} - A \exp\left(-(r d)^s\right)
\end{aligned}
```

`A`、`r`、`s` 是代码里 `amplitude`、`rate`、`shape` 的简写，`d_{\max}` 就是 `dmaxNorm`。

- `D`：扣掉片基后的光学密度
- `d`：除以所用密度范围之后的值
- `P`：线性输出亮度

曲线在整个区间里一直上升。`d ≥ 0` 时输出落在 `[baseToe, ceiling)` 内。
比片基更亮的背光或齿孔那种小于 0 的值不会被截成 0，而是继续保持有限的正值。

```math
y(-|d|) = 2\log_{10}(P_{\mathrm{toe}}) - y(|d|)
```

反函数也有闭式解，用来做合成负片和往返检查。

```math
d = \frac{\left[\ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(P)}\right)\right]^{1/s}}{r}
```

## 四个基准点

曲线系数不保存，由下面这些值算出来。

| 基准点 | 彩色 | 黑白 | 用途 |
|---|---:|---:|---|
| `P(0)` 片基黑点 | 0.001 | 0.0005 | 不让它贴到 8-bit 编码 0 |
| `P(midFraction)` 中灰 | 0.18 | 0.18 | 18% 灰 |
| `P(1)` 白 | 0.70 | 0.85 | 实测最高密度处的亮度 |
| `P(∞)` 上限 | 0.90 | 0.98 | 反射光余量 |

`midFraction` 是 `0.60D / 1.55D`，约 `0.387`。

系数怎么算：

```math
\begin{aligned}
y_{\mathrm{ceil}} &= \log_{10}(P_{\mathrm{ceil}}) \\
A &= y_{\mathrm{ceil}} - \log_{10}(P_{\mathrm{toe}}) \\
r_X &= \ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(X)}\right) \\
s &= \frac{\ln(r_{\mathrm{white}}/r_{\mathrm{mid}})}
          {\ln(1/f_{\mathrm{mid}})} \\
r &= r_{\mathrm{white}}^{1/s}
\end{aligned}
```

## 默认密度范围

`normalRange` 不是胶片的物理最大密度，而是正常曝光场景用到的范围。
它主要在测不到片基、或场景对比度很低时起作用。

```math
\begin{aligned}
\operatorname{normalRange}(\mathrm{color}) &= 0.62 \times 2.5 = 1.55\,D \\
\operatorname{normalRange}(\mathrm{B\&W}) &= 0.62 \times 3.5 = 2.17\,D
\end{aligned}
```

- `0.62`：C-41 特性曲线直线部斜率的近似值
- 彩色 `2.5`：约 7⅓ 级漫射亮度范围加高光余量
- 黑白 `3.5`：黑白放大惯用更长的直线部
- `0.60D`：正常曝光场景的中灰密度

`applySceneRanged` 不用这个值，而是量这一张画面各通道实际用到的密度范围。

## v4 改了什么

以前是分三段的函数加固定预设。
v4 换成一条曲线加四个基准点，没有分段边界，每个值都能在代码和测试里追到。

和以前结果的差别：

- 彩色中间调和高光，归一化密度 0.3～1.1：在 ±0.05 级以内
- 彩色深暗部，0.1～0.2：约 −0.2 级
- 彩色片基黑点：约 +0.25 级
- 黑白：暗部约 −0.4 级，中间调约 +0.1 级
- NORITSU/FUJI 的中灰 0.18 基准点保持不变

## 参考资料和范围

趾部、直线部、肩部和伽马这套框架来自公开的感光学。
文献里的曲线系数没有照抄，negaflow 的系数由上面四个基准点自己算出来。

- [Sensitometry](https://en.wikipedia.org/wiki/Sensitometry)
- [Hurter–Driffield Characteristic Curve](https://studyguides.com/study-methods/overview/cmpanf83znm1201neitjb4waw)
- [RA-4 相纸比较](https://tinker.koraks.nl/photography/on-a-color-mission-comparing-two-ra4-color-papers/)

RA-4 资料里已知的对比度范围不会直接拿来用。这条曲线的对比度由四个基准点导出的 `shape` 决定。
