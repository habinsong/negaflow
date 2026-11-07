# ネガ反転応答

[ドキュメントホーム](../README.md)

## MAIN/PRINT と CS

初期値は `MAIN` と自動バランス ON です。スイッチについては [Chroma Engine](../product/CHROMA_ENGINE.md) にあります。

**自動バランス ON。** チャンネルごとに、シーンでもっとも濃い0.2%パーセンタイルを使い、範囲は1.8Dに制限します。その後に `shoulder-print-response-v4` カーブと、彩度の低いシーン向けのバイブランスが続きます。フィルムプリセットは、測った範囲にチャンネルごとの相対係数を掛けます。1.8Dの制限は描画の安全策で、すべてのフィルムで測った性質ではありません。濃いネガに影響することがあります。

**自動バランス OFF。** 同じ v4 カーブに固定の公称範囲（カラー1.55D、白黒2.17D）を使い、プリセットを選ぶとプリセット係数を掛けます。シーンの範囲正規化と、彩度の低いシーン向けのバイブランスは省きます。カラーネガでは、スキャナーとフィルムのチャンネル範囲補正も掛けます。この値は、同じロール（ロールがなければ同じスキャンフォルダー）で有効に測れたフレーム3枚以上の中央値で、一度決まるとフレームごとに保たれます。フレームが足りない場合やフィルムが混在する場合は、3チャンネルが同じ範囲を使います。すると、同じベースと設定で透過率が等しければ、1ロールのフレームは同じ結果になります。

ON は、シーンの内容によって明るさと色の両方が変わることがあります。どちらのモードも、測定したフィルムの色の正確さを保証しません。

シーンの測定は、手動スライダーを動かしている間キャッシュされます。Windows ではプレビューの反転とバイブランスを D3D で、書き出しを CPU で処理します。

## ほかのターゲットと RAW

明示的なスキャナーターゲットは、シーン解析と固定の `shoulder-print-response-v4` プリミティブを保ちます。シーン解析に共通の1.8D上限はありません。フィルムプリセットは固定の相対係数を使い、フレームごとにこっそり正規化することはありません。

両プラットフォームとも、ネガのカメラ RAW を LibRaw の `output_color=0`、リニア伝達、チャンネル倍率1でデコードします。フィルムベースの測定と反転はデモザイク後のカメラ RGB で行い、そのあと `rgb_cam` がポジをリニア sRGB に移します。撮影時のホワイトバランス、自動輝度、シーンに応じた最大値の調整は無効です。プレビュー、欠陥キャッシュ、書き出しは、行列の適用を後ろに回した状態を保ちます。デジタル写真の描画は別です。対応していないネイティブ出力は、行列を適用したネガに黙って差し替えず、失敗します。この順序は、測定したカメラ・光源・フィルムの校正の代わりにはなりません。Raw TIFF と baked-source TIFF は反転していない作業用 RGB 画像なので、色行列はその出力の境界で適用します。

### バンドルなしの CLI の RAW 設定

アプリバンドルにはデコーダーが入っています。バンドルなしの macOS CLI やテストでは、同じライブラリをビルドし、プロセスを始める前に絶対パスを指定します。

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## 検証と出典

`NegativeAutoBalanceTests` は、範囲・カーブ・バイブランスの組み合わせ、OFF、キャッシュの再利用を確かめます。Windows のテストは、範囲の上限、プリセット係数、OFF、CPU/D3D の RAW 反転の順序を確かめます。

`FixedNegativeResponseTests` は、EXPIRED が使う v6 モデルの回帰を保っています。フレーム間のばらつきがゼロであることと、理想化した順方向モデルの色は、MAIN/CS の応答や実際のフィルムの色の正確さを検証しません。レンダラーとサムネイルの識別子が、現在の結果と古いキャッシュのプレビューを分けます。

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
