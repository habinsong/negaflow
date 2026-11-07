# Negativantwort

[Dokumentationsstart](../README.md)

## MAIN/PRINT und CS

Voreingestellt sind `MAIN` und Auto-Abgleich ON. Der Schalter ist in [Chroma Engine](../product/CHROMA_ENGINE.md) beschrieben.

**Auto-Abgleich ON.** Jeder Kanal nutzt das dichteste 0,2-%-Perzentil der Szene mit einer Bereichsgrenze von 1,8D, danach folgen die Kurve `shoulder-print-response-v4` und die Vibrance für gedämpfte Szenen. Filmvorgaben multiplizieren den gemessenen Bereich mit ihren relativen Kanalfaktoren. Die 1,8D-Grenze ist eine Absicherung des Renderings, keine gemessene Eigenschaft jedes Films, und sie kann dichte Negative beeinflussen.

**Auto-Abgleich OFF.** Dieselbe v4-Kurve mit festem Nennbereich (Farbe 1,55D, S/W 2,17D), bei gewählter Vorgabe mit deren Faktoren multipliziert. Die Normalisierung des Szenenbereichs und die Vibrance für gedämpfte Szenen entfallen. Bei Farbnegativen kommt außerdem eine Kanalbereichskalibrierung für Scanner und Film hinzu. Sie ist der Median von mindestens drei Bildern mit gültiger Messung aus demselben Film oder, ohne Filmangabe, aus demselben Scanordner, und bleibt nach der Wahl auf jedem Bild. Bei weniger Bildern oder gemischtem Film behalten die drei Kanäle denselben Bereich. Gleiche Transmission mit derselben Basis und denselben Einstellungen ergibt dann in allen Bildern eines Films dasselbe Ergebnis.

ON kann mit dem Szeneninhalt Helligkeit und Farbe verändern. Keiner der beiden Modi belegt eine gemessene Farbgenauigkeit des Films.

Szenenmessungen werden zwischengespeichert, während manuelle Regler bewegt werden. Unter Windows laufen Invertierung und Vibrance der Vorschau über D3D, der Export über die CPU.

## Andere Ziele und RAW

Ausdrückliche Scannerziele behalten die Szenenanalyse und das feste Primitiv `shoulder-print-response-v4`. Die Szenenanalyse hat keine allgemeine 1,8D-Grenze. Eine Filmvorgabe nutzt feste relative Faktoren und normalisiert nicht stillschweigend jedes Bild.

Beide Plattformen dekodieren Kamera-RAW von Negativen mit LibRaw `output_color=0`, linearer Übertragung und Kanalmultiplikatoren von 1. Filmbasismessung und Invertierung laufen auf dem entmosaikten Kamera-RGB, danach bildet `rgb_cam` das Positiv in lineares sRGB ab. Aufnahme-Weißabgleich, automatische Helligkeit und szenenabhängige Maximalanpassung sind abgeschaltet. Vorschau, Defekt-Caches und Export behalten die aufgeschobene Matrix. Die Wiedergabe digitaler Fotos ist getrennt. Eine nicht unterstützte native Ausgabe schlägt fehl, statt stillschweigend ein matrixverarbeitetes Negativ zu nehmen. Diese Reihenfolge ersetzt keine gemessene Kalibrierung von Kamera, Licht und Film. Raw-TIFF und Baked-Source-TIFF sind nicht invertierte Arbeits-RGB-Bilder, ihre Farbmatrix wird an dieser Ausgabegrenze angewendet.

### RAW-Einrichtung für die CLI ohne Bundle

Das App-Bundle bringt seinen Decoder mit. Für eine macOS-CLI ohne Bundle oder für Tests bauen Sie dieselbe Bibliothek und setzen vor dem Start des Prozesses ihren absoluten Pfad.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## Prüfung und Quellen

`NegativeAutoBalanceTests` prüft die Kombination aus Bereich, Kurve und Vibrance, OFF und die Wiederverwendung des Caches. Die Windows-Tests prüfen die Bereichsgrenze, die Vorgabefaktoren, OFF und die Reihenfolge der CPU/D3D-RAW-Invertierung.

`FixedNegativeResponseTests` behält die v6-Modellregressionen, die EXPIRED verwendet. Die Nullabweichung zwischen Bildern und die Farben eines idealisierten Vorwärtsmodells belegen weder die MAIN/CS-Antwort noch die Farbgenauigkeit echten Films. Renderer- und Miniaturkennungen halten aktuelle Ergebnisse von älteren Cache-Vorschauen getrennt.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
