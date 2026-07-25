# 代码与资源的来源

[文档首页](../README.md)

这里写的是 Negaflow 主体的 Apache-2.0 分发范围。它不是法律意见书，而是一份来源记录，方便日后
重新核对仓库和发布产物。

## 代码

`Sources`、`Tests`、`scripts` 是为 Negaflow 写的 Swift、Python 和 Shell 代码。主体里没有
C/C++/Objective-C 源码、外部包、静态或动态库，也没有 vendored 源码树，只链接 Apple 在 macOS
上提供的系统框架。

胶片反转用的是公开感光学里的密度、趾部、直线部和肩部这套概念。这里的曲线和系数出自 Negaflow
自己的四个光度基准点，没有照抄第三方程序的公式或常数。公式和推导见
[固定印相响应](../reference/PRINT_RESPONSE.md)。

GrainMend IR 按这个顺序工作。

1. 单独估计 RGB 与 IR 之间的整数偏移。
2. 按 `log(red)` 区间对 IR 截尾均值做插值，得到非参数化的场景渗漏曲线。
3. 扣掉场景渗漏，再算相对于局部均值的相对对比度。
4. 用截尾后的局部噪声阈值、连通分量和方向，做出缺陷遮罩。

这份代码没有链接也没有移植 SANE 的 IR 校正。公开文献和产品说明只是确认胶片与红外物理限制的
背景资料。参考方法和原理是一回事，照抄代码表达是另一回事。美国版权局也把方法、系统和具体表达
分开看。

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE 插件边界

主体里没有 `scanimage`、SANE 头文件、后端配置，也没有针对具体设备的处理代码。主体只通过带版本
的 JSON/NDJSON 约定与已安装的外部程序通信。真正的 SANE 部分作为独立的 GPL-2.0-or-later 仓库和
可执行文件分发。

只是分属不同进程，并不能直接得出许可结论。GNU FAQ 也写到：管道或命令行通信通常看起来像独立
程序，但通信过于紧密时结论可能不同。所以这份约定只交换与设备无关的请求、功能、进度和结果文件
信息，不共享 SANE 的数据结构。

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [扫描仪插件结构](../architecture/SCANNER_PLUGINS.md)

发布检查会再确认一次：应用包里没有混进插件、SANE 可执行文件或库。插件那边自带 `LICENSE`、
`COPYING`、完整的对应源码和第三方声明。

## 内置资源

[`Config/bundled-resource-provenance-v1.json`](../../../Config/bundled-resource-provenance-v1.json)
固定了进入应用和源码树的每个资源所声明的来源、许可和 SHA-256。

| 分组 | 来源 | 分发内容 |
|---|---|---|
| ScannerKit TIFF | 维护者拍摄并整理的排版素材 | 4 个 TIFF |
| 应用图标 | 维护者的项目美术素材 | 原始 PNG、构建用 PNG、ICNS |
| 风格预设 | 为 Negaflow 写的数值 | 6 个 JSON |
| 扫描仪配置文件 | 由维护者保存的扫描测量生成 | 数值配置文件，不含原始扫描 |

TIFF 里能看到的相机和色彩空间元数据，是拍摄与编码留下的容器信息。扫描仪配置文件里的
`sourceProfiles` 是生成时本地测量资料的逻辑路径，那些原始照片不分发。

FILM-R v2 素材只在做质量测量时下载，图像本身不会进仓库，也不会进应用。DOI 版本、CC BY 4.0、
文件大小和哈希固定在
[`Config/defect-corpus-film-r-v2.json`](../../../Config/defect-corpus-film-r-v2.json)。

## 名称与互操作

胶片、扫描仪、色彩空间、XMP namespace 和产品名称，用于标识对象和保持文件互操作。不主张商标
所有权，也不主张合作关系。范围见 [`TRADEMARKS.md`](../../../TRADEMARKS.md)。

## 自动检查和它管不到的部分

`python3 scripts/ci/verify-provenance.py` 遇到下面任一情况就失败。

- 没有登记，或哈希变了的内置资源
- 进入主体的 C/C++/Objective-C、外部包、二进制归档、vendor 树
- 进入主体代码的 SANE 专用名称，或受检外部实现的痕迹
- 让发布脚本把 SANE 插件塞进应用的改动
- 进入仓库的 FILM-R 图像素材

这个检查能拦住当前代码树里明显的回退。它证明不了与整个互联网的相似性，也管不了照片与配置文件
输入的权利、专利、商标以及各国的法律判断。来源变了就把声明和哈希一起复核。说不清楚时，先把该
资源从分发里拿掉，再问权利人或专业人士。
