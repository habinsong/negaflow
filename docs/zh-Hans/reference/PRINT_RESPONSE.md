# 负片反转响应

[文档首页](../README.md)

## MAIN/PRINT 和 CS

默认使用 `MAIN`，自动平衡为 ON。MAIN（含 PRINT）和 CS 的目标标题右侧有切换按钮。它根据当前照片调整颜色和亮度，OFF 时跳过此步骤。自动影调、自动白平衡、自动色阶和自动色彩是独立功能，默认 OFF。

自动平衡 ON 恢复 `412bb31` 的 MAIN/CS 反转。每个通道按场景最浓处 0.2% 分位数测量密度范围，限制为 1.8D，再应用原有 `shoulder-print-response-v4` 曲线和低饱和场景的饱和度补偿。胶片预设将测量范围乘以各通道相对系数。1.8D 是保留原有外观的渲染限制，并非所有胶片的实测物性，也会影响高密度负片。

OFF 也使用同一 v4 曲线，范围固定为标称值（彩色 1.55D，黑白 2.17D），并乘以选定预设的系数。它跳过场景范围归一化和饱和度补偿。同一片基和设置下，相同透射率在不同画面中产生相同结果。ON 会随场景内容改变亮度和颜色。两种模式都不能证明胶片的实测色彩准确度。

只改变手动滑块时会复用场景测量值。Windows 预览保留原有 D3D 反转和饱和度路径，导出使用 CPU。已弃用的中位数增益实现及其速度测量不适用于当前实现。RAW 仍先反转再应用相机色矩阵，独立的片基修复也保留。整个应用并未回退到 `412bb31`。

## 其他目标和 RAW

明确选择的扫描仪目标保留场景分析与旧版 `shoulder-print-response-v4`。旧固定 primitive 也保留兼容性。场景分析同样没有统一的 1.8D 上限。胶片预设使用固定相对系数，不逐帧自动归一化。

两个平台都用 LibRaw 的 `output_color=0`、线性传递函数和单位通道倍率解码负片相机 RAW。在去马赛克后的相机 RGB 中测量片基并反转，再用 `rgb_cam` 将正像转换到线性 sRGB。拍摄白平衡、自动亮度和按场景调整 maximum 均关闭。预览、缺陷修复缓存和导出保留延迟应用的矩阵。数字照片使用独立渲染路径。无法输出相机 RGB 时返回错误。这一步骤不能替代相机、光源和胶片的实测校准。Raw TIFF 和应用缺陷修复的原始 TIFF 是未反转的工作 RGB 图像，因此在该输出边界应用颜色矩阵。

### 独立 CLI 的 RAW 配置

应用包含解码库。在应用包之外运行 macOS CLI 或测试时，先构建相同库，并在进程启动前设置绝对路径。

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## 验证与来源

对附带 `Roll_Perforation.tiff` 的一个裁剪区域，使用相同片基和设置，与独立构建的 `412bb31` 引擎比较。MAIN、PRINT、Studio、Emulsion、胶片预设和黑白共6种条件下，恢复后的 ON 结果在32位 float 像素上完全一致。此比较仅涵盖一个输入，不代表所有扫描或相机 RAW。`NegativeAutoBalanceTests` 检查原有范围、曲线、饱和度组合，以及 OFF 和缓存复用。Windows 检查范围限制、预设系数、OFF 及 CPU/D3D 的 RAW 反转顺序。

`FixedNegativeResponseTests` 保留 EXPIRED 使用的 v6 模型回归。其帧间差异 0 和理想化正向模型的颜色结果不能验证恢复后的 MAIN/CS 或真实胶片色彩准确度。渲染器和缩略图标识用于区分旧缓存和恢复结果。

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
