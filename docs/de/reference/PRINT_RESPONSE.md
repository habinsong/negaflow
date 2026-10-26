# Negativantwort

[Dokumentationsstart](../README.md)

## MAIN/PRINT und CS

Voreingestellt sind `MAIN` und Auto-Abgleich ON. Bei MAIN (einschließlich PRINT) und CS sitzt der Schalter rechts neben der Zielüberschrift. Er passt Farbe und Helligkeit an das aktuelle Bild an; OFF überspringt diesen Schritt. Auto-Tonwert, Auto-Weißabgleich, Auto-Tonwertkorrektur und Auto-Farbe sind getrennte Funktionen und bleiben standardmäßig OFF.

Auto-Abgleich ON stellt die MAIN/CS-Inversion aus `412bb31` wieder her. Jeder Kanal misst seinen Dichtebereich am dichtesten 0.2%-Perzentil der Szene, begrenzt ihn auf 1.8D und verwendet danach die bisherige Kurve `shoulder-print-response-v4` und die Sättigungskorrektur für gedämpfte Szenen. Filmvorgaben multiplizieren den Bereich mit relativen Kanalfaktoren. Die Grenze von 1.8D bleibt für das bisherige Rendering erhalten; sie ist kein gemessener Materialwert aller Filme und kann dichte Negative beeinflussen.

OFF verwendet dieselbe v4-Kurve mit festem Nennbereich (Farbe 1.55D, Schwarzweiß 2.17D), gegebenenfalls multipliziert mit den Faktoren der Filmvorgabe. Szenenabhängige Bereichsnormierung und Sättigungskorrektur entfallen. Bei gleicher Basis und gleichen Einstellungen ergibt dieselbe Transmission in verschiedenen Bildern denselben Wert. ON kann Helligkeit und Farbe mit dem Bildinhalt ändern. Keiner der Modi belegt gemessene Filmfarbgenauigkeit.

Bei Änderungen manueller Regler werden Szenenmessungen wiederverwendet. Windows behält die bisherige D3D-Inversion und Sättigungskorrektur für die Vorschau; der Export nutzt die CPU. Der verworfene Median-Gain-Prototyp und seine Laufzeiten beschreiben diese Implementierung nicht. RAW wird weiterhin vor der Kamerafarbmatrix invertiert; die getrennten Filmbasiskorrekturen bleiben erhalten. Die Anwendung wurde nicht vollständig auf `412bb31` zurückgesetzt.

## Andere Ziele und RAW

Explizite Scannerziele behalten Szenenanalyse und `shoulder-print-response-v4`. Das feste Primitive bleibt verfügbar. Auch die Szenenanalyse hat keine allgemeine 1.8D-Obergrenze. Filmvorgaben verwenden feste relative Faktoren ohne automatische Einzelbildnormalisierung.

Beide Plattformen dekodieren Kamera-RAW von Negativen mit LibRaw `output_color=0`, linearer Übertragung und Kanalverstärkung 1. Filmbasismessung und Inversion laufen im demosaizierten Kamera-RGB. Erst danach wandelt `rgb_cam` das Positiv in lineares sRGB um. Aufnahme-WB, automatische Helligkeit und szenenabhängige Maximum-Anpassung sind deaktiviert. Vorschau, Defektcache und Export behalten die aufgeschobene Matrix. Digitalfotos nutzen einen getrennten Renderpfad. Nicht unterstützte Kamera-RGB-Ausgabe führt zu einem Fehler. Diese Reihenfolge ersetzt keine gemessene Kamera/Licht/Film-Kalibrierung. Raw-TIFF und TIFF mit eingerechneten Defektkorrekturen sind nicht invertierte Arbeits-RGB-Bilder; die Matrix wird an dieser Ausgabegrenze angewendet.

### RAW in der CLI außerhalb des Bundles

Das App-Paket enthält den Decoder. Für die macOS-CLI oder Tests außerhalb des Pakets wird dieselbe Bibliothek gebaut und ihr absoluter Pfad vor Prozessstart gesetzt.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## Prüfung und Quellen

Ein Ausschnitt aus dem mitgelieferten `Roll_Perforation.tiff` wurde bei gleicher Basis und gleichen Einstellungen mit einem separat gebauten `412bb31`-Engine verglichen. Bei MAIN, PRINT, Studio, Emulsion, einer Filmvorgabe und Schwarzweiß waren die 32-Bit-Float-Pixel des wiederhergestellten ON-Pfads exakt gleich. Der Vergleich betrifft eine Eingabe, nicht jeden Scan oder Kamera-RAW. `NegativeAutoBalanceTests` prüft die bisherige Kombination aus Bereich, Kurve und Sättigung sowie OFF und Cache-Wiederverwendung. Windows prüft Bereichsgrenze, Vorgabefaktoren, OFF und die RAW-Inversionsreihenfolge auf CPU/D3D.

`FixedNegativeResponseTests` behält die v6-Modellregressionen für EXPIRED. Deren Bildabweichung von 0 und die Farbergebnisse des idealisierten Vorwärtsmodells validieren weder das wiederhergestellte MAIN/CS noch reale Filmfarbgenauigkeit. Renderer- und Vorschaubildkennungen trennen das neue Ergebnis von alten Caches.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
