# Negative response

[Docs home](../README.md)

## MAIN/PRINT and CS

The default is `MAIN` with Auto Balance on. The switch is a small pill at the right of the Target heading. It appears only for color and B&W negatives on MAIN (including PRINT) and CS. It adjusts color and brightness from the current picture; switching it off bypasses that step. Auto Tone, Auto White Balance, Auto Levels and Auto Color remain separate and off by default.

Auto Balance ON restores the MAIN/CS inversion from `412bb31`: each channel uses its densest 0.2% scene percentile, with a 1.8D range limit, followed by the original `shoulder-print-response-v4` curve and muted-scene vibrance. Film presets multiply that measured range by their relative channel factors. The 1.8D limit is a rendering safeguard retained for compatibility, not a measured property of every film. It can affect dense negatives.

OFF uses the same v4 curve with a fixed nominal range (color 1.55D, B&W 2.17D), multiplied by preset factors when selected. It skips scene range normalization and muted-scene vibrance. For color negatives, OFF also multiplies a channel range calibration for the scanner and film. It is the median of at least three frames with a valid measurement from the same roll, or from the same scan folder when no roll is set. The value, once chosen, stays on each frame. With fewer frames, or with mixed film, the three channels keep the same range. Equal transmittance with the same base and settings then gives the same result across the frames of one roll. ON can change both brightness and color with scene content. Neither mode establishes measured film color accuracy.

Scene measurements are cached while manual sliders change. Windows retains the existing D3D inversion and vibrance preview path; export uses the CPU path. The discarded median-gain prototype and its timing measurements do not describe this implementation. RAW inversion still precedes the camera color matrix, and the separate film-base fixes remain; the whole application has not been rolled back to `412bb31`.

## Other targets and RAW

Explicit scanner targets retain scene analysis and the legacy `shoulder-print-response-v4`. Its fixed primitive remains available for compatibility. Scene analysis has no universal 1.8D cap. A stock preset uses fixed relative factors; it does not silently normalize each frame.

Both platforms decode negative camera RAW with LibRaw `output_color=0`, linear transfer and unit channel multipliers. Film-base measurement and inversion run on demosaiced camera RGB before `rgb_cam` maps the positive into linear sRGB. Capture WB, automatic brightness and scene-dependent maximum adjustment are disabled. Preview, defect caches and export retain the deferred matrix. Digital-photo rendering remains separate. Unsupported native output fails instead of silently using a matrix-processed negative. This order does not replace a measured camera/light/film calibration. Raw TIFF and baked-source TIFF are uninverted working-RGB images, so their color matrix is materialized at that output boundary.

### Unbundled CLI RAW setup

The app bundle carries its decoder. For an unbundled macOS CLI or tests, build the same library and set its absolute path before starting the process.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## Validation and sources

With one crop of the bundled `Roll_Perforation.tiff`, a fixed base and identical settings, the restored ON path matched the independently built `412bb31` engine exactly in 32-bit float pixels for MAIN, PRINT, Studio, Emulsion, a film preset and B&W. This comparison covers one input, not every scan or camera RAW. `NegativeAutoBalanceTests` checks the original range/curve/vibrance combination, OFF and cache reuse. Windows checks the range cap, preset factors, OFF and CPU/D3D RAW inversion order.

`FixedNegativeResponseTests` retains the v6 model regressions used by EXPIRED. Its zero frame variation and idealized forward-model color results do not validate the restored MAIN/CS response or real-film color accuracy. Renderer and thumbnail identifiers separate the restored result from older cached previews.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
