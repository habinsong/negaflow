# 负片反转响应

[文档首页](../README.md)

## MAIN/PRINT 与 CS

默认是 `MAIN`，自动平衡为 ON。开关的说明见 [Chroma Engine](../product/CHROMA_ENGINE.md)。

**自动平衡 ON。** 每个通道取场景中最密的 0.2% 百分位，范围限制为 1.8D，随后是 `shoulder-print-response-v4` 曲线和低饱和场景的自然饱和度。胶片预设把实测范围乘以各通道的相对系数。1.8D 限制是渲染上的保护，不是每种胶片的实测特性，可能影响密度高的负片。

**自动平衡 OFF。** 同一条 v4 曲线，使用固定的标称范围（彩色 1.55D，黑白 2.17D），选了预设时再乘以预设系数。跳过场景范围归一化和低饱和场景的自然饱和度。彩色负片还会乘上针对扫描仪和胶片的通道范围校准。该值取自同一卷（未设卷时取同一扫描文件夹）中至少三帧有效测量的中位数，一旦选定，就保留在每一帧上。帧数不足或胶片混杂时，三个通道使用相同的范围。这样，基底和设置相同、透射率相同的输入，在同一卷的各帧里得到相同的结果。

ON 会随场景内容同时改变亮度和颜色。两种模式都不能证明胶片色彩的实测准确性。

手动滑块变动期间，场景测量会被缓存。Windows 上预览的反转和自然饱和度走 D3D，导出走 CPU。

## 其他目标与 RAW

明确指定的扫描仪目标保留场景分析和固定的 `shoulder-print-response-v4` 基本曲线。场景分析没有通用的 1.8D 上限。胶片预设使用固定的相对系数，不会悄悄逐帧归一化。

两个平台都用 LibRaw 的 `output_color=0`、线性传递和单位通道倍率解码负片相机 RAW。片基测量和反转在去马赛克后的相机 RGB 上进行，随后 `rgb_cam` 把正片映射到线性 sRGB。拍摄白平衡、自动亮度和随场景变化的最大值调整都被关闭。预览、缺陷缓存和导出保持延后应用矩阵的状态。数码照片的渲染另行处理。不支持的原生输出会失败，而不是悄悄换成已应用矩阵的负片。这个顺序不能代替实测的相机、光源和胶片校准。Raw TIFF 和 baked-source TIFF 是未反转的工作 RGB 图像，所以色彩矩阵在该输出边界应用。

### 未打包的 CLI 的 RAW 设置

应用包自带解码器。未打包的 macOS CLI 或测试，需要构建同一个库，并在启动进程前设置它的绝对路径。

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## 验证与来源

`NegativeAutoBalanceTests` 检查范围、曲线和自然饱和度的组合、OFF 以及缓存复用。Windows 测试检查范围上限、预设系数、OFF 和 CPU/D3D 的 RAW 反转顺序。

`FixedNegativeResponseTests` 保留 EXPIRED 使用的 v6 模型回归。它的零帧间差异和理想化正向模型的颜色，不能验证 MAIN/CS 响应，也不能验证真实胶片的色彩准确性。渲染器和缩略图标识把当前结果与旧的缓存预览区分开。

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
