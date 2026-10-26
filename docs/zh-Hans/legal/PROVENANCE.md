# 代码与资源的来源

[文档首页](../README.md)

这里记录 negaflow 主体的 Apache-2.0 分发范围。这是一份用于重新核对仓库和发布产物的来源记录，不构成法律意见。

## 代码

`negaflow-mac` 的 Swift、Python 和 Shell 集成代码由本项目编写。负片相机 RAW 解码使用未修改且固定版本的 LibRaw，以可替换的 `libraw.dylib` 按 CDDL-1.0 分发。应用的 `Contents/Resources/licenses/libraw/` 包含源码归档、构建脚本、版权与许可证文件。Apache 源码树不合并 LibRaw 源码。Windows 使用同一上游版本，其他组件记录在 [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md)。测试用 `CameraNativeRaw.dng` 来自 raw.pixls.us 条目 2204，许可为 CC0-1.0；相邻 JSON 记录来源，应用不包含该文件。

补充声明文件缺失时，构建和打包会给出警告并继续。上游许可证和对应源码仍随包提供。

胶片反转用的是公开感光学里的密度、趾部、直线部和肩部这套概念。 这里的曲线和系数出自 negaflow 自己的四个光度基准点，没有照抄第三方程序的公式或常数。 公式和推导见 [固定印相响应](../reference/PRINT_RESPONSE.md)。

公开的厂商技术数据表用于三组随附胶片常数：各胶片的 Dmin 与 Dmax 预设（`FilmStockDmin`）、黑白光谱灵敏度与特性曲线预设（`BWFilmProfile`），以及颗粒与 MTF 物理参数（`DigitalFilmPhysics`）。 这些数值是从公开数据表的图表上读出或拟合的近似值，`FilmStockDmin` 会逐条把来源标成 `datasheetCurve` 或 `estimated`，让出处一直可见。 从公开图表读出的数值是关于胶片的事实，不是照抄别人的代码或文字；只要扫描里有实测的片基， 实测永远优先。

GrainMend IR 按这个顺序工作。

1. 单独估计 RGB 与 IR 之间的整数偏移。
2. 按 `log(red)` 区间对 IR 截尾均值做插值，得到非参数化的场景渗漏曲线。
3. 扣掉场景渗漏，再算相对于局部均值的相对对比度。
4. 用截尾后的局部噪声阈值、连通分量和方向，做出缺陷遮罩。

这份代码没有链接也没有移植 SANE 的 IR 校正。 公开文献和产品说明只是确认胶片与红外物理限制的背景资料。 参考方法和原理是一回事，照抄代码表达是另一回事。美国版权局也把方法、系统和具体表达分开看。

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE 插件边界

主体里没有 `scanimage`、SANE 头文件、后端配置，也没有针对具体设备的处理代码。 主体只通过带版本的 JSON/NDJSON 约定与已安装的外部程序通信。 真正的 SANE 部分作为独立的 GPL-2.0-or-later 仓库和可执行文件分发。

只是分属不同进程，并不能直接得出许可结论。 GNU FAQ 也写到：管道或命令行通信通常看起来像独立程序，但通信过于紧密时结论可能不同。 所以这份约定只交换与设备无关的请求、功能、进度和结果文件信息，不共享 SANE 的数据结构。

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [扫描仪插件结构](../architecture/SCANNER_PLUGINS.md)

发布检查会再确认一次：应用包里没有混进插件、SANE 可执行文件或 SANE 库。 插件那边自带 `LICENSE`、`COPYING`、完整的对应源码和第三方声明。

## 内置资源

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) 固定了进入应用和源码树的每个资源所声明的来源、许可和 SHA-256。

| 分组 | 来源 | 分发内容 |
|---|---|---|
| ScannerKit TIFF | 维护者拍摄并整理的排版素材 | 4 个 TIFF |
| 应用图标 | 维护者的项目美术素材 | 原始 PNG、构建用 PNG、ICNS |
| 风格预设 | 为 negaflow 写的数值 | 6 个 JSON |
| 扫描仪配置文件 | 由维护者保存的扫描测量生成 | 数值配置文件，不含原始扫描 |

TIFF 里能看到的相机和色彩空间元数据，是拍摄与编码留下的容器信息。 扫描仪配置文件里的 `sourceProfiles` 是生成时本地测量资料的逻辑路径，那些原始照片不分发。

FILM-R v2 素材只在做质量测量时下载，图像本身不会进仓库，也不会进应用。 DOI 版本、CC BY 4.0、文件大小和哈希固定在 [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json)。

## 名称与互操作

胶片、扫描仪、色彩空间、XMP namespace 和产品名称，用于标识对象和保持文件互操作。 Windows 引擎合成的输出 ICC 配置文件写入描述性名称（`"Negaflow Compatible P3"`、`"Compatible with Adobe RGB (1998)"`）与 `CC0 1.0 Universal` 声明，使导出的图像不受配置文件版权限制。 不主张商标所有权，也不主张合作关系。范围见 [`TRADEMARKS.md`](../../../TRADEMARKS.md)。

## 自动检查和它管不到的部分

`python3 scripts/ci/verify-provenance.py` 遇到下面任一情况就失败。

- 没有登记，或哈希变了的内置资源
- 进入主体的 C/C++/Objective-C、外部包、二进制归档、vendor 树
- 进入主体代码的 SANE 专用名称，或受检外部实现的痕迹
- 让发布脚本把 SANE 插件塞进应用的改动
- 进入仓库的 FILM-R 图像素材

这个检查能拦住当前代码树里明显的回退。 它证明不了与整个互联网的相似性，也管不了照片与配置文件输入的权利、专利、商标以及各国的法律判断。 来源变了就把声明和哈希一起复核。说不清楚时，先把该资源从分发里拿掉，再问权利人或专业人士。
