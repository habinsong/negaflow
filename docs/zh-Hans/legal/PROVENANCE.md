# 代码与资源的来源

[文档首页](../README.md)

本文记录 negaflow 应用以 Apache-2.0 分发的范围。它是用于核对仓库和发布产物的来源记录，不构成法律意见。

## 代码

`negaflow-mac` 里的 Swift、Python 和 shell 集成是为 negaflow 编写的。

负片相机 RAW 的解码使用固定版本的 LibRaw，构建为可替换的 `libraw.dylib`，按 CDDL-1.0 分发。两个平台应用同样的三个补丁：

- [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch): 在 `src/demosaic/xtrans_demosaic.cpp` 中，按顺序处理富士 X-Trans 的图块，并行处理图块内的行，并以互不相邻的行组为单位运行绿色边界处理
- [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch): 在 `src/postprocessing/mem_image.cpp` 中，并行复制输出位图的行
- [`raw-decoders-parallel.patch`](../../../negaflow-mac/scripts/libraw/raw-decoders-parallel.patch): 在 `src/decoders/decoders_dcraw.cpp` 中，把普通无损 JPEG（CR2）和尼康 NEF 数据交给并行霍夫曼解码器，并并行解码索尼 ARW2 的行

打过补丁的构建在测试过的 RAW 文件上，与未打补丁的串行构建结果一致。

在 macOS 上，LLVM OpenMP（libomp 20.1.8，Apache License v2.0 with LLVM Exceptions）被静态链接进库。应用在 `Contents/Resources/licenses/libraw/` 中附带源码压缩包、补丁、构建脚本、版权和许可证文件。`native-preview-bridge.cpp`（Negaflow contributors，CDDL-1.0）里有一个 LibRaw 子类，它并行运行三个逐像素循环而输出逐字节相同，还有解码器补丁所调用的并行霍夫曼解码器。LibRaw 源码不会并入 Apache 源码树。

Windows 使用相同的上游版本和补丁。它的 `native-preview-bridge.cpp`（CDDL-1.0）增加了线性 DNG 的 Windows 专用函数，其他组件记录在 [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md) 中。仅供测试的 `CameraNativeRaw.dng` 是 raw.pixls.us 第 2204 号条目的 CC0-1.0 资料，由旁边的来源 JSON 标明，并从应用中排除。补充声明文件缺失时，构建和打包步骤会给出警告并继续，上游许可证文件和对应源码仍然包含在内。

胶片反相使用已公开的感光测量概念：密度、趾部、直线段和肩部。曲线和系数来自 negaflow 的四个测光锚点，而不是第三方程序的公式或常数。公式和推导见[负片反转响应](../reference/PRINT_RESPONSE.md)。

已公布的厂商数据表为随产品发布的三组胶片常数提供依据：各类胶片的 Dmin 和 Dmax 预设（`FilmStockDmin`），黑白的光谱和特性曲线预设（`BWFilmProfile`），以及物理颗粒和 MTF 参数（`DigitalFilmPhysics`）。这些数值是从公开技术资料中大致读取或拟合得到的，`FilmStockDmin` 给每个条目标上 `datasheetCurve` 或 `estimated`，使来源一目了然。从公开图表读出的数值是关于胶片的事实，不是对任何人代码或文字的复制，而从扫描中测得的片基始终优先于它们。

GrainMend IR 按下面的顺序运行：

1. 自行估计 RGB 与 IR 之间的整数偏移。
2. 按 `log(red)` 分箱，对 IR 的截尾均值做插值，建立非参数的场景漏光曲线。
3. 减去场景漏光，再计算相对于局部均值的相对对比度。
4. 用截尾的局部噪声阈值、连通域和方向生成缺陷蒙版。

这段代码没有链接或移植 SANE 的 IR 校正。已发表的论文和产品页面只是用来确认胶片与红外的物理局限的背景资料。采用方法或原理是一回事，照搬代码的表达是另一回事。美国版权局也在方法、系统与其具体表达之间划了同样的线。

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE 插件边界

应用里没有 `scanimage`、没有 SANE 头文件、没有后端配置，也没有针对具体设备的处理代码。它只通过带版本的 JSON/NDJSON 约定与已安装的外部程序通信。真正的 SANE 工作作为 GPL-2.0-or-later 的独立仓库和可执行文件发布。

作为独立进程，本身并不能解决许可证问题。GNU FAQ 说，管道或命令行通信通常看起来像独立程序，但通信过于紧密时结论可能改变。所以这个约定只交换与设备无关的请求、能力、进度和结果文件信息，不共享 SANE 的数据结构。

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [扫描仪插件结构](../architecture/SCANNER_PLUGINS.md)

发布检查会再次确认没有插件、SANE 可执行文件或 SANE 库混入应用包。插件一侧自带 `LICENSE`、`COPYING`、完整的对应源码和第三方声明。

## 内置资源

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) 固定了进入应用和源码树的每个资源所声明的来源、许可证和 SHA-256。

| 类别 | 来源 | 随产品发布的内容 |
|---|---|---|
| ScannerKit TIFF | 维护者拍摄并整理的布局资料 | 4 个 TIFF 文件 |
| 应用图标 | 维护者提供的项目美术 | 源 PNG、构建用 PNG、ICNS |
| 风格预设 | 为 negaflow 写的数值 | 6 个 JSON 文件 |
| 扫描仪配置文件 | 由维护者保存的扫描测量制成 | 数值配置文件，不含源扫描 |

TIFF 文件中能看到的相机和色彩空间元数据，是拍摄和编码留下的容器信息。扫描仪配置文件里的 `sourceProfiles` 是构建时本地测量资料的逻辑路径，那些源照片不随产品发布。

FILM-R v2 资料只在质量测量时下载，图像不会进入仓库或应用。DOI 版本、CC BY 4.0、文件大小和哈希固定在 [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json) 里。

## DNG 导出

DNG 写入器（`negaflow-mac` 中的 `DNGLinearWriter`，`negaflow-windows` 中的 `dng_linear_export`）依据 Adobe 公布的 Digital Negative Specification 1.6 中的标签编号和色彩模型编写。其中没有 Adobe DNG SDK 的代码，也没有 LibRaw 或其他 DNG 写入器的代码。色彩矩阵由 sRGB、Display P3 和 Adobe RGB (1998) 已公布的色度坐标计算得出。

Adobe 为读写 DNG 文件的软件提供免版税的专利许可。本产品使用了这项许可，而许可要求附上下面的声明。

This product includes DNG technology under license by Adobe.

DNG 是 Adobe Inc. 的商标。该名称仅用于标识文件格式。

## 变换与拉直

变换部分和参考线拉直都是为 negaflow 编写的，不含第三方代码。

- 直线段的找法是：把亮度梯度方向一致的像素归成一组，再沿每组的主成分方向拟合直线。按方向归组边缘像素是 1980 年代起就已公开的技术。
- 求解器只保留与竖直或水平相差 30° 以内的线段，然后转动焦距固定的相机，在模式允许的范围内让线段尽量接近竖直和水平。它用 Nelder–Mead 单纯形法减小对离群值不敏感的角度误差之和。它不估计相机内参、曼哈顿方向或消失点。
- 引导模式只使用用户画的参考线。

Adobe 持有两项仍然有效的美国专利，内容是照片透视的自动校正。两者的优先权日都是 2012 年 4 月 27 日，Google Patents 预计 2033 年到期。

- [US 9,519,954](https://patents.google.com/patent/US9519954B2/en) 要求保护的是通过优化能量函数，同时估计内参矩阵、姿态矩阵和消失点。negaflow 不估计其中任何一项。
- [US 9,582,855](https://patents.google.com/patent/US9582855B2/en) 的独立权利要求更宽：至少部分依据人的感知标准，计算让线条对齐图像轴的单应性或平面变换。negaflow 的求解器同样让线条对齐图像轴。这个思路在 2012 年之前就已公开。Marcus Hebel 的 ShiftN 于 2006 年推出，2008 年 10 月发布 3.4 版。它寻找接近竖直的直边，并优化透视变换，使这些边相互平行并与画框对齐（[ShiftN](https://www.shiftn.de/ShiftN_functionality.html)、[版本记录](https://newsgroup.xnview.com/viewtopic.php?p=57759)）。negaflow 没有使用 ShiftN 的代码。

某个实现是否落入权利要求范围属于法律判断，本记录不对此下结论。

## 名称与互操作

胶片、扫描仪、色彩空间、XMP 命名空间和产品名称用来指明对象并保持文件的互操作性。Windows 引擎合成的输出 ICC 配置文件使用描述性名称（`"Negaflow Compatible P3"`、`"Compatible with Adobe RGB (1998)"`）和 `CC0 1.0 Universal` 声明，因此导出的用户图像不带配置文件的版权限制。不主张任何商标所有权或关联。完整范围见 [`TRADEMARKS.md`](../../../TRADEMARKS.md)。

## 自动检查及其盲区

`python3 scripts/ci/verify-provenance.py`（在 `negaflow-mac/` 下运行）遇到以下任何一种情况都会失败：

- 未登记或哈希发生变化的内置资源
- 应用里的 C/C++/Objective-C、外部软件包、二进制压缩包或 vendor 目录
- 应用代码里仅属于 SANE 的名称，或已核对的外部实现的痕迹
- 让发布脚本把 SANE 插件放进应用的改动
- 仓库里的 FILM-R 图像资料

这项检查拦住当前代码树里明显的退步。它不能证明与整个互联网上内容的相似性、摄影或配置文件输入的权利、专利、商标，也不能证明任何国家的法律结论。来源变化时，请把声明和哈希一并复核。来源不明时，把该资源从发布中移除，并询问权利人或专业人士。
