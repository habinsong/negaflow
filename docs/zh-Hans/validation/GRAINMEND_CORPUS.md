# GrainMend 实际扫描比较

[文档首页](../README.md)

GrainMend RGB 的回归检查用 FILM-R v2。

| 项目 | 值 |
|---|---|
| 受损件・手工修复件 | 各 44 张 |
| 许可 | CC BY 4.0 |
| 总大小 | 437,570,872 字节 |
| 存放位置 | `build/defect-corpus/` |
| 用途 | GrainMend RGB 回归比较 |

## 素材

- 名称：*Authentically damaged & manually restored film scans*
- 作者：Daniela Ivanova
- DOI：<https://doi.org/10.6084/m9.figshare.21803304.v2>
- 论文：<https://doi.org/10.1111/cgf.14749>
- 说明：<https://daniela997.github.io/FilmDamageSimulator/>
- 许可：CC BY 4.0
- 构成：44 张受损的 35mm 胶片扫描，以及 44 张专家手工修复件
- 总大小：437,570,872 字节

图像不放进仓库。 `Config/defect-corpus-film-r-v2.json` 固定了 DOI 版本、许可、配对数量和总大小。
获取脚本会核对 Figshare 给出的每个文件的 MD5 和大小。
下载的文件和结果放在 `build/defect-corpus/`，并从 Git 中排除。

## 获取

不带参数的命令只取一对，方便快速看一眼。

<details>
<summary>获取命令</summary>

```bash
python3 scripts/defect-corpus/fetch-film-r.py
```

全部 44 对：

```bash
python3 scripts/defect-corpus/fetch-film-r.py --all
```

如果 Figshare 的文件 CDN 拦截自动请求，可以在数据集页面用 `Download all` 下载 ZIP，
然后直接校验并解开。只有 ZIP 里的文件名、大小和 Figshare MD5 全部符合固定约定，解压才算完成。

```bash
python3 scripts/defect-corpus/fetch-film-r.py \
  --archive ~/Downloads/21803304.zip \
  --all
```

只取一例：

```bash
python3 scripts/defect-corpus/fetch-film-r.py --case portra400_135_1
```

</details>

## 运行比较

把受损件和名字以 `_restored` 结尾的修复件放在同一个文件夹里。

<details open>
<summary>44 对的比较命令</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run -c release negaflow defect-bench build/defect-corpus/film-r-v2 \
  --reference-dir build/defect-corpus/film-r-v2 \
  --out build/defect-corpus/film-r-v2-report \
  --metrics-only
```

</details>

`--metrics-only` 不生成大 PNG。
去掉这个选项，还会生成供人工确认的 `before`、`after`、`diff`、 `mask` 和 100% 裁切。

报告里包含的值：

- 既有检出数、置信度、改变的像素数、处理时间
- 受损件与专家修复件之间的 PSNR 和平均绝对误差
- GrainMend 结果与专家修复件之间的 PSNR 和平均绝对误差
- PSNR 的变化
- 相对参考的误差变小和变大的像素比例

FILM-R 论文同时使用 PSNR、SSIM 和 LPIPS。
本仓库不新增 ML 依赖，因此只自动算标准库能算的 PSNR 和绝对误差。

光靠这些数字不批准发布。手工修复件里同样带着编辑判断和 JPEG 差异。
用同样素材和设置重跑时的自动质量下限，固定在 `Config/defect-removal-film-r-v2-baseline.json`。
最终判定要把 `before`、 `after`、`diff`、`mask` 和 100% 裁切放在一起看。

> [!CAUTION]
> 不会只凭 PSNR 或平均误差就批准 GrainMend 的画质。原始质感的损伤和误检，要结合前后图像、差分
> 图像、遮罩和 100% 裁切一起判断。

这份素材只能验证渲染图像上的 GrainMend RGB 路径。
它不能用来证明 RAW 解码、胶片反转的准确度、 IR 对齐，或真实扫描仪的行为。

## 2026-07-25 的结果

44 对全部在 Release 构建下以 `--metrics-only --crops 0` 运行。
把此前的回归基准（灵敏度 3.0）和发布用自动路径（0.7）做了对比。

| 指标 | 此前基准 3.0 | 安全自动 0.7 |
|---|---:|---:|
| 参与评估的图像 | 44 | 44 |
| PSNR 变好 / 变差 / 持平 | 11 / 33 / 0 | 34 / 6 / 4 |
| 平均 PSNR 变化 | -1.688 dB | +0.466 dB |
| 中位 PSNR 变化 | -0.237 dB | +0.118 dB |
| 最差 PSNR 变化 | -18.952 dB | -1.338 dB |
| 加权改善像素 | 0.128% | 0.029% |
| 加权变差像素 | 0.792% | 0.017% |
| 加权改变像素 | 0.794% | 0.043% |
| 自动安全中止 | 无 | 3 张 |

以前应用的默认值是 6.0，比 3.0 的基准还激进。发布用的自动路径降到 0.7，微细异物检测默认关闭。
候选超过某个图块的 2% 时，会排除触及该图块的连通成分；只要有图块超过 5%，
或过滤后总候选超过 0.06%，这张照片就不做自动修复。这时用户可以用引导缩小范围再处理。

这条安全线只对自动生效。引导、画笔、克隆图章和 IR 的检出范围与修复行为，不会被自动的标准限制。

`Config/defect-removal-film-r-v2-baseline.json` 除了观测值回归基准，还会检查下面这些绝对下限。

- 改善不少于 30 张，变差不多于 10 张
- 平均和中位 PSNR 变化不低于 0 dB
- 最差 PSNR 变化不低于 -1.5 dB
- 加权变差像素不超过 0.03%
- 总改变像素不超过 0.06%

这次的结果比此前基准多改善了 23 张，少变差了 27 张，最坏情况提升了 17.614 dB。
即便如此，仍有 6 张的 PSNR 低于专家修复件。
FILM-R 提供的是真实受损件和手工修复件，同时也带着修复判断上的模糊。
素材和论文见 [FILM-R 项目](https:
//daniela997.github.io/FilmDamageSimulator/)和 [FILM-R 论文](https:
//arxiv.org/abs/2302.10004)。

把高密度候选排除在自动之外，这与既有图像修复研究中减少纹理区域误检的做法一致。
不过这个结果不能拿来主张下面几点。

- 所有照片上自动结果都好过手工修复。
- GrainMend RGB 等同于硬件 IR 清洁。
- 真实扫描仪的 RGB・IR 对齐和光学质量已获验证。

完整复现在手动的 `GrainMend corpus` workflow 里跑。
除了自动质量门禁，还必须做 100% 裁切的人工确认。
