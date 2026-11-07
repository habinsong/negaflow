# 扫描仪配置文件质量判定

[文档首页](../README.md)

`scripts/evaluate_profile_quality.py`（在 `negaflow-mac/` 下运行）检查扫描仪配置文件的改动是否比已批准的基线更差。它比较 `LUT_target/analyze_lut_target.py` 生成的两份 `SOURCE/summary.json`，只有未用于调整配置文件的验证用例才计入判定。

这个工具不定义什么是好的色彩。哪些数值应该降低或升高、允许变动多少，由人写进语料清单。没有默认的合格线。

这个仓库目前没有 REAL/TARGET 图像对（`LUT_target/REAL` 和 `LUT_target/TARGET` 是空的）。因此没有真实的语料清单，没有已批准的基线，也没有真实设备的通过结果。合成测试只检查检查器本身的代码。

> [!WARNING]
> 仅凭这个仓库无法批准扫描仪的色彩准确度。发布决定需要固定的 REAL/TARGET 配对、未用于调整的验证用例，以及人工设定的容差。

## 应用对现有配置文件的使用范围

当你自己选择 `HS` 或 `SP` 目标时，可以使用来自内置 `realOnly` 组的有限的相对差异。

条件：

- 胶片类型和胶片名称一致。
- 整理后的源卷名集合一致。
- 图像数量相差不超过 15%。

源配置文件没有逐帧 ID 或 SHA-256，卷名一致也不能证明配对的是同样的画幅。所以不能称之为与真实设备相同的结果。

应用规则：

- 两组中方向相反的数值不应用。
- 黑白会丢弃所有色彩分量，只保留相对影调。
- 没有对应卷的正片配置文件，不应用相对校正。
- 没有同一位置的配对资料时，不应用扫描仪的纹理和锐化。
- 影调只对 Rec.709 伽马亮度应用一次，Lab 的 `a*` 和 `b*` 保持不变。
- 色彩增益在对数域插值，使相对锚点之间的关系保持成立。
- 任何文件或清单的 SHA-256 不符，整个配置文件包都会被拒绝。

## 厂商资料能确认什么

- [Fujifilm Frontier 570/SP-3000 指南](https://www.photolabdigital.com/fuji_frontier570_en%5B1%5D.pdf)列出了面阵 CCD、Hyper-tone、Hyper-sharpness 等功能，但没有公布传递函数或设置值。
- [Noritsu HS-1800 产品信息](https://www.noritsu.eu/hardware/noritsu-film-scanner.html)列出了支持的规格、分辨率和吞吐量，但没有给出固定的色彩传递函数。
- [Noritsu 专利 US 7,589,863](https://patents.google.com/patent/US7589863/en)描述了由操作员选择密度、层次和锐度的迷你冲印流程。

这些资料说明处理会随场景和操作员而变化。它们没有提供复现 HS-1800 或 SP-3000 的常数，negaflow 也不会凭产品名猜测这类数值。

## 语料清单架构 v1

清单放在它所固定的输入资料旁边，例如 `LUT_target/quality/corpus-v1.json`。路径相对于清单文件；给出 `--data-root` 时，以该路径为基准。

<details>
<summary>清单示例</summary>

```json
{
  "schemaVersion": 1,
  "corpusVersion": "scanner-corpus-2026-07-10.1",
  "acceptedBaselineSHA256": "sha256:<64 lowercase hex>",
  "cases": [
    {
      "role": "calibration",
      "stem": "NORITSU/color nega/Portra 400/calibration-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    },
    {
      "role": "holdout",
      "stem": "NORITSU/color nega/Portra 400/holdout-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    }
  ],
  "metrics": [
    {
      "name": "mean_delta_e2000",
      "direction": "lowerIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "similarity_score_0_100",
      "direction": "higherIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "neutral_a_shift",
      "direction": "absoluteLowerIsBetter",
      "allowedRegression": 0.0
    }
  ]
}
```

</details>

`0.0` 不是推荐值。请按你的测量方式和发布策略设定条目与容差。

## 清单规则

- `schemaVersion` 必须恰好是 `1`。未知的版本和未知的字段会被拒绝。
- `corpusVersion` 是资料的固定选取和划分的名称。
- `acceptedBaselineSHA256` 固定已批准的 `summary.json` 的确切字节。
- 每个用例要么是 `calibration`，要么是 `holdout`。名称不能重复。
- 资料不能为空，两种角色都至少要有一个用例。
- REAL 和 TARGET 文件都以 `sha256:<64 位小写十六进制>` 固定。
- 指标名称不能重复。
- `allowedRegression` 必须是大于等于 0 的有限数。布尔值会被拒绝。
- 方向只接受 `lowerIsBetter`、`higherIsBetter` 和 `absoluteLowerIsBetter`。

`absoluteLowerIsBetter` 比较与 0 的距离。只有当 0 是经过评审的参照时才使用。

## 准备候选与已批准的基线

```bash
python3 LUT_target/analyze_lut_target.py
```

批准发布之前，把候选的完整 `SOURCE/summary.json` 保存为下一份已批准的基线文件。候选通过评审之前，不会覆盖现有的已批准文件。把已批准文件的确切 SHA-256 填进 `acceptedBaselineSHA256`。

候选和基线的汇总里，清单中的每个用例必须恰好出现一次。缺失的用例、重复、处理失败，或清单之外的用例，都属于输入错误。

`calibration` 用例可用于拟合配置文件，不计入判定。`holdout` 用例不参与调整和选择。验证数值逐用例比较，所以平均值变好也盖不住某一张变差。

## 运行

<details open>
<summary>质量判定命令</summary>

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

</details>

文件校验模式：

| 取值 | 作用 | 可作为发布依据 |
|---|---|---|
| `all` | 检查每个 REAL/TARGET 文件的路径和 SHA-256 | 可以 |
| `holdout` | 只检查验证文件 | 用于快速诊断 |
| `none` | 不检查图像文件 | 不可以 |

默认是 `all`。报告会记录所用模式、清单和汇总文件的哈希、文件校验结果，以及验证集逐用例的比较和计数。同一份 JSON 会输出到 stdout 和 `--report` 文件，文件以原子方式保存。

退出码：

- `0`：输入有效，且没有超出容差的退步
- `1`：输入有效，但至少有一个验证值超出范围
- `2`：架构、资料、哈希、路径或指标有误或缺失

## 测试检查器

```bash
python3 -m unittest scripts/tests/test_evaluate_profile_quality.py
```

测试用临时合成文件覆盖正常比较、退步、哈希变化、错误的架构和数字、重复、缺失和失败的用例，以及空资料。它们不能证明真实扫描仪输出的质量。
