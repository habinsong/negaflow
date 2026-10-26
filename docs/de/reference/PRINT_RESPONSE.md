# Feste Negativantwort

[Dokumentationsstart](../README.md)

## MAIN/PRINT und abgeleitete Ziele

`fixed-density-linear-v6` gilt für negative `MAIN/PRINT` ohne Scannerprofil. Die Dichtekorrektur ist fest. Bei gleicher Basis und gleichen Einstellungen ändern andere Pixel, Ausschnitt oder Histogramm die Inversion derselben Transmission nicht. Szenenabhängige Vibrance wird nicht angewandt.

Benutzerdefinierte Ziele und EXPIRED verwenden dieselbe feste Inversion wie MAIN. Die benutzerdefinierte Farbe folgt auf die Kalibrierung. EXPIRED korrigiert nur bei ausreichenden Belegen; ohne geeignete Belege entspricht die Ausgabe MAIN. Diese Ziele ignorieren ein verbliebenes Scannerprofil.

`B` ist die gemessene Basistransmission. `f` ist bei der generischen Antwort 1 oder der feste relative Bereichsfaktor des gewählten Films. `0.62` und `0.60D` sind Gamma- und Graudichtereferenzen des generischen Modells. Sie sind keine Messwerte jedes Films oder Scanners. Status-M-Dichten beschreiben Scanner-RGB nicht direkt.

```math
D_c = \log_{10}(B_c / \max(T_c,10^{-5}))
```

```math
q_c = D_c/f_c,\quad k=0.045,\quad d_t=0.60+0.62\log_{10}(k/0.18),\quad p=d_t\ln(10)/0.62
```

```math
E_c=\begin{cases}
k\,\operatorname{sgn}(q_c)(|q_c|/d_t)^p,&q_c<d_t\\
0.18\times10^{(q_c-0.60)/0.62},&q_c\ge d_t
\end{cases}
```

Der Dichtefuß schließt mit gleichem Wert und gleicher Steigung an den geraden Abschnitt an. Die unbelichtete Filmbasis ergibt vor dem Weißabgleich eine Szenenbelichtung von null. Dieser Potenzfuß ist ein allgemeiner Entwurf, keine je Film gemessene Kurve. Nahe der Filmbasis kann er auch Dichterauschen verstärken.

Automatische Korrekturen gelten nur nach ausdrücklichem Einschalten. Bei Auto-Farbe bleibt die Filmbasis vor der Ausgabekurve aus den Neutralachsenproben ausgeschlossen. Starke Farbstiche können weiterhin einen manuellen Weißabgleich erfordern.

## Ausgabekurve

Kanalweiser Weißabgleich und Belichtung wirken auf das szenenlineare `E`. Dieselbe feste Ausgabekurve wird nach dem Weißabgleich auf jeden Kanal angewendet. Der Mittelbereich erhält RGB-Verhältnisse; die Schulter verändert die Farbverhältnisse heller Bereiche. `0.045...0.70` bleibt identisch. Unter `0.045` wird ein kleiner Schwarzsockel addiert: `b=0.001` für Farbe und `0.0005` für Schwarzweiß. Über `0.70` nähert sich die rationale Schulter der 1. Beide Übergänge haben die Steigung 1. Die Umkehr des Filmfußes und die Schwarzdarstellung sind getrennte Schritte.

```math
F(x)=x+b(1-x/0.045)^2\quad(0<x<0.045),\qquad F(x)=b\quad(x\le0)
```

Auto-Pegel rechnet die Zielwerte vor der Spreizung durch die inverse Ausgabekurve zurück: Ausgabeschwarz `0.003`, Weiß `0.95`. Auto-Farbe schließt Proben mit einem szenenlinearen Kanalwert von höchstens `0.004` aus. Die unbelichtete Filmbasis ist null und benötigt keinen gesonderten Randgrenzwert. Ziele ohne Szenenanalyse behalten feste Referenzeinheiten für das Eingangsgamma. Bei szenenlinearen Negativen beträgt die Mindestspanne 4 % des gemessenen Weißwerts statt eines festen Belichtungswerts von 0.04.

Die Inversion hat keine `1.8D`-Obergrenze. Die Transmissionsuntergrenze `1e-5` schützt den Logarithmus. Die Gamut-Abbildung erfolgt an der Ausgabegrenze. In diesem Schritt liegt jeder Kanal zwischen Schwarzsockel und 1. Spätere manuelle Korrekturen können diesen Bereich überschreiten.

## Andere Ziele

Explizite Scannerziele behalten Szenenanalyse und `shoulder-print-response-v4`. Das feste Primitive bleibt verfügbar. Auch die Szenenanalyse hat keine allgemeine 1.8D-Obergrenze. Filmvorgaben verwenden feste relative Faktoren ohne automatische Einzelbildnormalisierung.

Film-RAW deaktiviert die von der API unterstützte Ausgabetonung. macOS scene-linear deaktiviert globale und lokale Tonkurven, shadow bias und Gamut-Mapping. Windows verwendet den linearen LibRaw-Transfer getrennt vom Digitalfoto-Rendering. Diese Einstellungen liefern keine gemessene Sensor-Film-Charakterisierung und garantieren kein RAW ohne Farbmatrix.

## Prüfung und Quellen

Geprüft werden ein unabhängiges Modell des geraden Filmkurvenbereichs, gleiche Farbfelder auf anderen Hintergründen, WB auf einer Neutralrampe und dichte Lichter. Synthetische Regressionen belegen keine Farbgenauigkeit realen Films. Bestehende Rezepte nutzen den korrigierten Algorithmus; Parameter und Originale bleiben erhalten. Die macOS-Rendererkennung und das Vorschaubildsuffix unterscheiden das neue Rendering.

Die Gleichungen wurden in diesem Repository implementiert. Code aus darktable, RawTherapee oder NegPy wurde nicht kopiert.

## Gemessener synthetischer Vergleich

Die Regression rekonstruiert den ursprünglichen Standardpfad mit dem erhaltenen v4-Verfahren samt 1.8D-Bereichsgrenze und automatischer Vibrance. Derselbe Dichtefleck `(0.48, 0.68, 0.70)` wird vor vier Hintergründen mit fester Filmbasis verglichen. Dies ist nicht der Reddit-Test mit 18 Bildern. Ein eigenes ideales Vorwärtsmodell mit glattem Filmfuß liefert die Ton- und Weißabgleichstests; es belegt keine Genauigkeit auf echtem Film.

| Messgröße | Ursprünglich | Erste Korrektur(v5) | Überarbeitet(v6) |
|---|---:|---:|---:|
| L*-Spanne zwischen Bildern | 40.49 | 0 | 0 |
| b*-Spanne zwischen Bildern | 35.22 | 0 | 0 |
| Lokaler Kontrast bei −3 EV | 1.57 | 2.17 | 0.97 |
| Maximales C* der Neutralstufen nach Weißabgleich | 8.89 | 0.99 | <0.001 |

v5 und v6 werden mit demselben Vorwärtsmodell des Filmfußes verglichen. Ein Schattenkontrast nahe 1 lässt etwa eine Ausgabestufe pro Eingangsstufe bestehen. L* und C* verwenden Lab D50. Der Fleck mit fester Filmbasis bleibt farbig; Konsistenz bedeutet nicht, dass eine beliebige Dichte neutral ist. `FixedNegativeResponseTests` mit einem JSON-Ausgabepfad in `NEGAFLOW_RESPONSE_COMPARISON` speichert die Messwerte.

## Prüfung des mitgelieferten Films

Auch die 18 erkannten Bilder aus `Roll_Perforation.tiff` wurden verglichen. Beide Inversionen verwenden dieselbe korrigierte, festgehaltene Filmbasis. Die L*-Spanne des identischen Dichteflecks fällt von 21.48 auf <0.001, die b*-Spanne von 30.94 auf <0.001. Die ursprüngliche blaue 1.8D-Grenze greift bei 18/18 Bildern. Der Vergleich folgt der Testidee des Kommentars, ohne dessen genaue Einstellungen nachzubilden.

Dabei wurde ein weiterer Fehler der Basisbestimmung sichtbar. Eine Mischkante aus Film und Hintergrundlicht ersetzte die Filmmessung `(0.354, 0.109, 0.057)` durch `(0.570, 0.510, 0.364)`. Rettungs- und Hüllkurvenstufe lehnen nun Ersatzwerte ab, die auf beiden Maskenfarbachsen wie Licht aussehen. Die Ausgabekurve wirkt nach dem Weißabgleich kanalweise: Ein extremer Blauwert steuert die Helligkeitsabbildung anderer Kanäle nicht mehr. Für diesen Film gibt es keine gemessene Farbreferenz. Konsistenz und begrenzte Ausgabe belegen keine kalibrierte Farbgenauigkeit. `NEGAFLOW_RESPONSE_ROLL_DIR` auf einen Ausgabeordner setzen und `testBundledRollFrameConsistency` ausführen, um Bilder und JSON zu speichern.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
