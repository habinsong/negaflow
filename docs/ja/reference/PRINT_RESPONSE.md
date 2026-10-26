# ネガ反転応答

[ドキュメントホーム](../README.md)

## MAIN/PRINT と CS

初期値は `MAIN` と自動バランス ON です。MAIN（PRINT を含む）と CS で、ターゲット見出しの右端にあるトグルで切り替えます。現在の写真から色と明るさを合わせ、OFF ではこの処理を省きます。自動トーン、自動ホワイトバランス、自動レベル、自動カラーは別の機能で、初期値は OFF です。

自動バランス ON は `412bb31` の MAIN/CS 反転を復元します。各チャンネルの最濃部 0.2% のパーセンタイルで濃度範囲を測り、1.8D に制限してから従来の `shoulder-print-response-v4` 曲線と低彩度シーンの彩度補正を適用します。フィルムプリセットは測定範囲にチャンネル別の相対係数を掛けます。1.8D は互換性のために残した描画上の制限で、全フィルムの実測物性ではありません。高濃度のネガにも影響します。

OFF でも同じ v4 曲線を使います。範囲は公称値（カラー 1.55D、白黒 2.17D）に固定し、選択したプリセットの係数を掛けます。シーン別の範囲正規化と彩度補正は省きます。同じベースと設定なら、同じ透過率は別のフレームでも同じ結果になります。ON は構図によって明るさと色が変わります。どちらもフィルムの実測色精度を証明しません。

手動スライダーだけの変更ではシーン測定値を再利用します。Windows のプレビューは従来の D3D 反転・彩度補正を使い、書き出しは CPU を使います。破棄した中央値 gain 方式とその速度測定は現在の実装には当てはまりません。RAW 反転は引き続きカメラ色行列より先に行い、別途修正したフィルムベース処理も維持します。アプリ全体を `412bb31` に戻したわけではありません。

## 他のターゲットと RAW

明示的なスキャナーターゲットはシーン解析と従来の `shoulder-print-response-v4` を使います。固定 primitive も互換用に残します。シーン解析にも共通の 1.8D 上限はありません。フィルムプリセットは固定相対係数を使い、フレームごとの自動正規化を行いません。

両プラットフォームとも、ネガのカメラ RAW を LibRaw の `output_color=0`、線形伝達、各チャンネル倍率 1 でデコードします。デモザイク後のカメラ RGB でフィルムベースを測定して反転し、その後 `rgb_cam` でポジを線形 sRGB に移します。撮影 WB、自動明るさ、シーンによる maximum 調整は無効です。プレビュー、欠陥補正キャッシュ、書き出しは遅延した行列を保持します。デジタル写真の描画は別の経路です。カメラ RGB 出力に対応しない場合はエラーになります。この順序だけでカメラ・光源・フィルムの実測校正にはなりません。Raw TIFF と欠陥を適用した原本 TIFF は未反転の作業 RGB なので、その出力時に色行列を適用します。

### バンドル外 CLI の RAW 設定

アプリはデコーダーを同梱します。macOS CLI やテストをバンドル外で動かす場合は、同じライブラリをビルドし、起動前に絶対パスを設定します。

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## 検証と出典

付属の `Roll_Perforation.tiff` の一つのクロップを、同じベースと設定で別途ビルドした `412bb31` エンジンと比較しました。MAIN、PRINT、Studio、Emulsion、フィルムプリセット、白黒の6条件で、復元した ON の32ビット float 画素が完全一致しました。一つの入力での比較であり、すべてのスキャンやカメラ RAW の検証ではありません。`NegativeAutoBalanceTests` は従来の範囲・曲線・彩度処理、OFF、キャッシュ再利用を検査します。Windows は範囲制限、プリセット係数、OFF、CPU/D3D の RAW 反転順序を検査します。

`FixedNegativeResponseTests` は EXPIRED が使う v6 モデルの回帰検査を保持します。そのフレーム間差 0 と理想的な順方向モデルの色結果は、復元した MAIN/CS や実フィルムの色精度を検証しません。レンダラーとサムネイルの識別子で古いキャッシュと復元結果を区別します。

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
