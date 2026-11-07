# IT8 色彩检验

[文档首页](../README.md)

色彩准确度需要测量，不能只靠目视。把 IT8 图像与其实物色标的参考文件配对，并为每个色块记录数值结果。

> [!IMPORTANT]
> 公开的 IT8 资料可以确认检查器和色彩计算有没有退步，但不能证明真实扫描仪或彩色负片的准确度。要评判设备，需要经过确认的实物色标和该设备的真实测量。

## 证据类别

| 名称 | 能确认什么 | 不能确认什么 |
|---|---|---|
| `algorithmRegression` | 文件解析、ICC 转换、色块面积、Lab、CIEDE2000 | 真实扫描仪的准确度 |
| `deviceCharacterization` | 用真实设备测量经过确认的实物色标 | 其他色标或设备的准确度 |
| `syntheticModel` | 独立合成模型的数学往返 | 真实胶片或设备的准确度 |

`deviceCharacterization` 需要实物色标的厂商、材质、序列号和批次。只要有一项与参考文件头不同，就不做任何评估。

IT8.7/1 和 ISO 12641-1 的透射色标针对正片透射原稿。这些结果对彩色负片的橙色底、染料相互作用、C-41 的差异以及 HS 和 SP 输出的准确度什么也说明不了。这类结论需要把同一张彩色负片走两条路径得到的配对资料，外加单独的验证集。

公开的 FADGI OpenDICE 图像与参考文件配对，测量了 264 个色块：ΔE00 中位数 9.8815，p95 13.2745，最大值 15.5996。独立的 LittleCMS 转换与评估器的差异最大为 0.105 个 Lab 单位。这些观测通不过胶片准确度的关卡：这张扫描是正片 IT8，实物序列号未经确认，也没有附带负片的相机、光源和胶片测量。

也查看了公开的负片数据集。FADGI 的负片参考只含密度，不含实测的色块。BlueNeg 把它复原的参考标注为 pseudo ground truth。2024 年 ARRI AQUA 分光测量研究的数据需要申请，不能公开下载。它们都没有为当前的反相提供独立的场景色彩参考。

还检查了一组[公开的 Kodak ColorPlus 200 曝光系列](https://discuss.pixls.us/t/any-interest-in-a-film-negative-feature-in-rt/12569/262)（五张 Sony ILCE-7 RAW 扫描，−1 到 +3 EV）。其色卡是 Grey White Balance Colour Card，所以拒绝使用 X-Rite 的参考值。120 个采样色块区域在解码后的相机 RGB 中都没有触到零或满量程。这只是对解码后信号的检查，不是传感器马赛克的直接测量，也不是色彩准确度的结果。没有该色卡和扫描环境的实测参考，输出的偏色就无法判定是来自输入还是来自应用。因为没有确认再分发权利，这些文件留在仓库之外。

[FADGI](https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html) · [BlueNeg](https://huggingface.co/datasets/ttgroup/blueneg-release) · [Plutino 2024](https://doi.org/10.1002/col.22946)

## 公开的回归资料

下面两个 FADGI/OpenDICE 文件配对使用。

- 说明: <https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html>
- 图像: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/IT8-7.1.tif>
  - SHA-256: `c62ee73f26390a2ad90e7e28280cbd1efb4f18834425bb7112ff1f8016832ffd`
  - 尺寸: `6255 x 4170`
  - 格式: 内嵌 `Adobe RGB (1998)` 的 16 位 RGB
- 参考文件: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/Profile_IT8-7.1.txt>
  - SHA-256: `19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840`
  - 色块: 从 `A1` 到 `L22` 的 264 个 Lab 值
  - 第 16 列：密度

因为没有确认再分发权利，这些文件不放进仓库和应用。请自行下载，并让[示例清单](../../reference/IT8_FADGI_OPENDICE.example.json)指向它们。示例的等级是 `algorithmRegression`，改成 `deviceCharacterization` 会被检查器拒绝。在 `negaflow-mac/` 下运行：

```bash
swift run negaflow it8-bench ../docs/reference/IT8_FADGI_OPENDICE.example.json \
  --image /path/to/IT8-7.1.tif \
  --reference /path/to/Profile_IT8-7.1.txt \
  --out /path/to/it8-report.json
```

## 测量规则

- 图像、参考文件或所选 ICC 的 SHA-256 与清单不符时，运行停止。
- 报告 v2 还会记录清单文本的 SHA-256。
- `A01` 和 `A1` 读取同一坐标，原始 ID 保留在报告里。
- 在 22 × 12 的网格中，每个色块取中间 60%，按源分辨率以浮点读取，行为 `A`–`L`，列为 `1`–`22`。
- 遵循内嵌的 ICC。
- 计算从线性 sRGB D65 到 XYZ，经 Bradford 适应到 D50，再到 Lab D50/2°。
- 每个色块记录面积、像素数、RGB 均值和标准差、两端截断比例、非有限值个数、参考和实测的 Lab、L/a/b 差以及 CIEDE2000。
- 中位数、p95 和最大值是观测值，不是合格线。不会无依据地设一个平均阈值，`qualityDecision` 保持 `notEvaluated`。
- 用来拟合配置文件的色标，不会再用于独立验证。

### 实物色标细节

实际设备测量时，由操作员从色标标签上读出下列信息并记录。

<details>
<summary>测量块示例</summary>

```json
{
  "measurement": {
    "samplerVersion": "center-mean-v1",
    "renderingIntent": "relativeColorimetric",
    "physicalTargetIdentity": {
      "manufacturer": "target label manufacturer",
      "material": "target label material",
      "serial": "target label serial",
      "batchMetadataKey": "PROD_DATE",
      "batchValue": "reference header production date"
    }
  }
}
```

</details>

`MANUFACTURER`、`MATERIAL`、`SERIAL` 和批次头（`BATCH`、`BATCH_ID`、`PROD_DATE` 之一）必须与参考文件逐字一致。顶层的 `targetID` 必须等于 `serial`，`batchID` 必须等于 `batchValue`。

这条记录只说明操作员写下的内容与参考文件一致。它不会从图像读取标签，也不为操作员的输入作担保。信息缺失时，不会用最接近的日期或通用参考文件代替。

参考文件若带有光源或观察者信息，会按 D50/2° 约定核对，出现矛盾就停止运行。目前 `measurement.renderingIntent` 无法直接固定 Core Image 的转换，所以报告里写 `manifestDeclarationNotControlledByEvaluator`。

## `PRINT` 输出

IT8.7/1 针对输入设备。打印机输出需要一份 RGB 打印机 ICC，它由对打印机、纸张、墨水或药液、驱动或工艺条件这一整套组合的真实测量得到。

检查与使用的顺序：

1. 确认 ICC 大小、`prtr` 设备类别、`RGB ` 数据空间、Lab/XYZ PCS 和 `acsp` 签名。
2. 确认 ColorSync 可以双向转换。
3. 选定时固定配置文件的名称、字节数和 SHA-256。
4. 在 `MAIN` 工作图像和页面布局完成之后，只对最终输出应用一次。
5. 不应用于 `rawScanTIFF` 或 `-main-flat`。
6. 配置文件缺失或有误，会在生成任何临时输出之前失败，不会用 sRGB 代替。

不声称当前的 Core Image 与 ColorSync 路径能在所有 macOS 版本上逐位固定渲染意图和黑场补偿。

## `MAIN` 合成色块回归

`NegativeAutoBalanceTests` 与 `shoulder-print-response-v4`。

MAIN/CS 在开关的两种状态下都使用 v4 曲线。保留的 v6 测试检查的是它们自己的固定基本曲线，那些测试里零帧间差异不是自动平衡 ON 的结果。

[负片反转响应](PRINT_RESPONSE.md)

## HS 与 SP 的相对风格回归

用 SHA-256 固定一份参考文件，其中有从 `A1` 到 `L22` 的 264 个 Lab D50 色块。每个色块生成一张合成负片，`MAIN`、`HS` 和 `SP` 各路径各运行两次。

```bash
swift run negaflow scanner-relative-it8-bench \
  /path/to/Profile_IT8-7.1.txt \
  --sha256 sha256:19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840 \
  --out /path/to/scanner-relative-it8-report.json
```

报告包含每个色块的 RGB 和 Lab、相对参考的 `DeltaE00`、目标之间的相对 `DeltaE00`，以及截断和非有限值的标记。中性灰阶的单调性从 `A16...L16` 密度列读取。

转换为线性 sRGB 后落在 0...1 之外的颜色，无法精确地做成合成负片，所以会被限制在可显示范围内。因此宽范围的统计是观测值，不是合格线。

证据等级始终是 `syntheticModel`，判定始终是 `notEvaluated`。配置文件清单或任何文件的 SHA-256 不符时，运行停止。要评判真实设备的准确度，需要同一张实物负片在两台机器上的扫描，以及单独的验证资料。

D50/2° 并非从参考文件头确认。这是该基准把 Lab 当作 D50/2° 来读的自身约定，所以 `colorimetryInterpretationProvenance` 为 `benchmarkContractNotVerifiedFromReferenceHeader`。
