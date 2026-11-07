# 胶片配置文件

[文档首页](../README.md)

内置的扫描仪配置文件，来自项目作者拍摄并用冲扫机（实验室扫描仪）扫描的胶片画幅，经分析后保存为 JSON。

| 项目 | 当前值 |
|---|---:|
| 胶片类型默认值 | 27 |
| 创作风格 | 6 |
| 扫描仪配置文件 | 15 |
| 卷观测 | 25 |
| 画幅数 | 928 |
| 验证状态 | 全部为 `realOnly` |

> [!NOTE]
> `928` 是项目作者拍摄并用冲扫机（实验室扫描仪）扫描的胶片画幅数。

## 三种彼此独立的数据

| 数据 | 格式 | 用途 | 数量 |
|---|---|---|---:|
| 胶片类型 | Swift | Dmin/Dmax 与胶片类型默认值 | 27 |
| 风格预设 | JSON | 你自己选择的创作风格 | 6 |
| 扫描仪配置文件 | JSON | 在真实扫描中看到的相对影调和色彩统计 | 15 |

27 个胶片名称不是 27 个色彩准确度配置文件，6 个风格也与扫描仪配置文件是两回事。下文只讲第三种。

## 目前内置的内容

`Sources/Chromabase/ScannerProfiles/` 里有 15 个配置文件。

<details>
<summary>全部 15 个配置文件</summary>

| 扫描仪 | 胶片类型 | 胶片 | 卷观测 | 画幅数 | 状态 |
|---|---|---|---:|---:|---|
| NORITSU | 彩色负片 | Fuji C200 | 3 | 111 | `realOnly` |
| NORITSU | 彩色负片 | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| NORITSU | 彩色负片 | Kodak Portra 160 | 1 | 37 | `realOnly` |
| NORITSU | 彩色负片 | Kodak Portra 400 | 2 | 75 | `realOnly` |
| NORITSU | 彩色负片 | Kodak Portra 800 | 1 | 38 | `realOnly` |
| NORITSU | 彩色负片 | Kodak Pro Image 100 | 1 | 37 | `realOnly` |
| NORITSU | 彩色负片 | Kodak UltraMax 400 | 1 | 38 | `realOnly` |
| NORITSU | 彩色负片 | Kodak Vision3 250D | 1 | 37 | `realOnly` |
| NORITSU | 彩色负片 | Kodak Vision3 50D | 1 | 38 | `realOnly` |
| NORITSU | 彩色正片 | Kodak Ektachrome 100 | 1 | 38 | `realOnly` |
| NORITSU | 彩色正片 | Kodak Ektachrome 100D | 5 | 181 | `realOnly` |
| SP-3000 | 彩色负片 | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| SP-3000 | 彩色负片 | Kodak Portra 160 | 1 | 38 | `realOnly` |
| SP-3000 | 彩色负片 | Kodak Vision3 250D | 2 | 71 | `realOnly` |
| SP-3000 | 彩色正片 | Kodak Ektachrome 100D | 1 | 37 | `realOnly` |
| **合计** |  |  | **25** | **928** | **15 `realOnly`** |

</details>

25 是各配置文件分组的卷观测数之和，不是不重复的卷数。928 是画幅数。

## 如何制作

1. 拍摄与分类。素材按扫描仪、胶片类型、胶片名称和卷名分开。分析前先确认旋转与文件解析，空文件或无法读取的文件不计入。
2. 画幅测量。每个画幅测量亮度百分位及两端的截断、暗部/中间调/亮部的通道关系、饱和度与色相分布、低饱和像素的 Lab 中性轴，以及梯度、锐度和颗粒参考值。这些是场景观测，一个画幅的曝光或被摄体不会被说成扫描仪的固定特性。
3. 场景分组。按亮度、对比度、饱和度和色相范围把场景分组，并记录每组的数量和分布，避免某一类场景主导整个配置文件。
4. 代表画幅。为了让人能回到源素材，另外记录对比度最高的画幅、最清晰的画幅、颗粒参考值最高的画幅，以及代表亮度和饱和度范围的画幅。
5. 卷与分组汇总。`scripts/compile_scanner_profiles.py` 把各卷数据汇总为胶片与扫描仪分组。空的分箱不会被表示为值为 0 的观测，所有值必须是有限数，样本数必须真实。
6. JSON 与哈希。最终文件包含架构、ID、源数量、源路径、汇总统计、验证状态和 `profileHash`。检查器会核对字段、数量、有限性、文件名与 ID 是否一致、源数量以及哈希。

## JSON 的结构

<details>
<summary>配置文件 JSON 示例</summary>

```json
{
  "schemaVersion": 2,
  "id": "noritsu__color-nega__kodak-portra-400",
  "displayName": "NORITSU · color nega · Kodak Portra 400",
  "scanner": "NORITSU",
  "kind": "color nega",
  "filmKey": "kodak portra 400",
  "validationStatus": "realOnly",
  "rollCount": 2,
  "imageCount": 75,
  "singleRollLimited": false,
  "sourceProfiles": [],
  "tone": {},
  "color": {},
  "neutralAxis": {},
  "neutralAxisBins": [],
  "hueResponse": [],
  "texture": {},
  "sceneBuckets": [],
  "coverageCandidates": [],
  "profileHash": "sha256:..."
}
```

</details>

## 主要条目

| 条目 | 内容 | 注意事项 |
|---|---|---|
| `tone` | 亮度分布及两端的截断 | 一个画幅的曝光不是机器的特性 |
| `color` | 暗部、中间调、亮部的通道与饱和度 | 观测到的分布，不是绝对色彩矩阵 |
| `neutralAxis` | 低饱和像素的 Lab `a*` 和 `b*` | 有些场景没有中性物体，所以同时给出样本数 |
| `hueResponse` | 各色相分箱的饱和度变化与色相旋转 | 只有两台机器的数据对得上时才做相对比较 |
| `texture` | 梯度、锐度、颗粒参考值 | 不直接当作机器的锐化数值 |
| `sceneBuckets` | 各场景的统计和代表画幅 | 让人能够再次追溯到源素材 |

`HS` 目标中对亮度通道的锐化，不是从 `texture` 测得的机器常数，也不会合成新的颗粒。`SP`、`MAIN` 和 `PRINT` 不含这种锐化。

## 证据状态

| 状态 | 含义 | 可以用在哪里 |
|---|---|---|
| `draft` | 数据或架构尚未完成 | 不用于内置或自动使用 |
| `realOnly` | 有真实扫描，但没有单独的参考资料 | 仅限手动选择，不作准确度声明 |
| `pairedSmoke` | 配对资料只确认了处理路径 | 不能当作质量证据 |
| `pairedValidated` | 通过了校准和验证资料及回归检查 | 政策允许时可自动选择 |

目前 15 个全部是 `realOnly`。可以确认它们来自对真实素材的观测，但无法确认它们与那台机器给出相同的结果。

要声称机器的准确度，还需要更多资料：

- 确认是同一个物理画幅的 ID
- 与校准分开保存的验证资料
- 制作参考图像的条件
- 扫描仪设置和操作员的选择
- 色标批次、照明和测量方法
- 逐张图像的合格标准

## 应用如何使用

### 手动选择

不会根据型号或文件信息自动选择任何配置。`HS` 或 `SP` 目标和配置文件由你自己选择。自动匹配只允许用于 `pairedValidated`，因此不适用于当前的内置资源。

### 两台扫描仪之间的相对差异

绝对的场景统计不会原样使用。只使用两台机器上相匹配分组之间的差异，而且有所限制：

- 整理后的卷名集合必须一致。
- 图像数量相差不能超过 15%。
- 色相分箱需要两侧的样本数都超过阈值。
- 方向翻转的数值不应用。
- 相反增益之间的数值在对数域里计算。
- 影调只对 Rec.709 伽马亮度应用一次，Lab 色彩分量保持不变。

源配置文件没有逐画幅的 SHA-256，卷名一致也不能证明配对的是同样的画幅。

### 黑白与正片

黑白会丢弃色彩分量，只用相对影调。对于正片，一卷的绝对亮度不会带到另一张照片上。不过 `HS` 和 `SP` 的基础风格会以一半的强度作用于正片，所以结果并不总是与 `MAIN` 相同。

### 纹理

没有同一画幅的配对资料时，不把 `texture` 当作机器专属的锐化或颗粒数值。这些数字里混有对焦、被摄体、JPEG 处理以及冲印店操作员的选择。

## 文件完整性

`ScannerProfileRegistry` 不会只打开 15 个中的一部分：

1. 读取清单架构。
2. 确认每个文件都存在，并检查其 SHA-256。
3. 重新计算每个 JSON 中的 `profileHash`。
4. 检查 ID、文件名、架构、状态、数量和有限性。
5. 只要有一项不符，就拒绝整个包。
6. 只缓存全部匹配的只读快照。

导出记录里保存实际使用的配置文件 ID 和 SHA-256。

## 检查命令

在 `negaflow-mac/` 下运行。第一条检查配置文件约定，第二条重新生成配置文件，第三条是 REAL/TARGET 质量判定。

```bash
python3 scripts/validate_scanner_profiles.py \
  --mode profile-contract \
  --profiles Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/compile_scanner_profiles.py \
  --source LUT_target/SOURCE \
  --out LUT_target/PROFILES \
  --resource-out Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

这个仓库目前没有可以支撑发布声明的 REAL/TARGET 清单或已批准的基线。合成测试只确认检查代码的失败条件，不能证明配置文件的准确度。

## 参考资料

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)
- [darktable negadoctor](https://docs.darktable.org/usermanual/4.6/en/module-reference/processing-modules/negadoctor/)

配置文件里的数值没有取自这些资料。它们只是用来了解为什么要把片基、场景影调和机器风格分开处理。JSON 里的数值来自为本项目拍摄的资料和仓库里的分析代码。

## 代码与相关文档

- `Sources/Chromabase/ScannerProfiles/`
- `Sources/Chromabase/Profiles/ScannerProfile/`
- `Sources/Chromabase/Profiles/ScannerTargetGrade/`
- `scripts/compile_scanner_profiles.py`
- `scripts/validate_scanner_profiles.py`
- `scripts/evaluate_profile_quality.py`
- [扫描仪配置文件质量判定](../reference/PROFILE_QUALITY_GATE.md)
- [IT8 色彩检验](../reference/IT8_COLOR_VALIDATION.md)
- [Chroma Engine](CHROMA_ENGINE.md)
