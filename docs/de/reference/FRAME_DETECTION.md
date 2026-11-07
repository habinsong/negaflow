# Wie die Bilderkennung am Flachbettscanner den Film findet

[Dokumentationsstart](../README.md)

Die Vorschau eines Flachbettscanners zeigt einen Halter, das Licht, das daran vorbeikommt, und den eingelegten Film. Bevor sich ein vollständiger Scan lohnt, entscheidet die automatische Bilderkennung, welche Teile Film sind und wo ein Bild endet und das nächste beginnt. Sie kennt die reale Größe des Vorschaubereichs in Millimetern und rechnet ein Filmformat daher exakt in Pixel um.

## Film wird an der Textur erkannt

Helligkeit unterscheidet Film nicht von einem leeren Halterfenster. Gemessen an einer Vorschau des Epson GT-X900:

| Was die Spalte enthält | Mittlere Helligkeit |
|---|---|
| Leeres Halterfenster, Lampe scheint direkt durch | 0.92 |
| Film im Nachbarfenster | 0.10 |
| Halterblende | 0.002 |
| Fremdhalter mit weißem Hintergrund | 1.00 |

Eine Sortierung nach Helligkeit wählt die leeren Fenster und verwirft den Film, und ein weißer Halterhintergrund kehrt die Reihenfolge um. Die Textur trennt beides, denn Korn und Bild gibt es nur auf dem Film:

| Was die Spalte enthält | Vertikales Detail |
|---|---|
| Film | 0.0044 – 0.032 |
| Halterblende, leeres Fenster, weißer Hintergrund | 0.00005 – 0.001 |

Der Abstand beträgt eine Größenordnung und behält sein Vorzeichen bei jeder Filmart, jedem Halter und jeder Polarität. Jede der folgenden Stufen nutzt ihn.

## Stufen

1. Spaltentextur. Das Detail wird an jeder Spalte der Vorschau entlang gemessen. Spalten mit Korn und Bild werden zu Fensterkandidaten.
2. Fenster. Die Kandidatenspalten wachsen bis zum Filmrand und werden mit der Breite des gewählten Formats verglichen. Ein Fenster, das den Rand des Scanbereichs berührt, wird verworfen, weil der Scanbereich es halbiert hat und der vollständige Scan den falschen Bereich erfassen würde.
3. Bänder. Innerhalb eines Fensters werden die Zeilen mit Film vom Halter darüber und darunter getrennt. Eine Zeile ist Film, wenn sie sich vom Halter daneben unterscheidet oder Textur trägt. Helligkeit allein verliert die dichten Bilder eines Dias, Textur allein verliert die Lücken und flache Bilder.
4. Raster. Ein Kamm aus Lückenpositionen wird über die (Abstand, Phase)-Ebene angepasst. Der Wert ist der Kontrast zwischen dem Inneren eines Bildes und dem Inneren der Lücke, die Anpassung hängt also nicht davon ab, ob die Lücke klare Basis, maximale Dichte oder eine Halterrippe ist.
5. Verfeinerung. Jede Grenze rastet an der nächsten Lücke ein, dann wird der ganze Satz auf gleichmäßigen Abstand neu angepasst, weil die Bilder eines Streifens gleichmäßig verteilt sind. Zweimaliges Scannen desselben Streifens landet innerhalb von 0,2 mm.

## Was abgelehnt wird

| Situation | Ergebnis |
|---|---|
| Halter ohne Film | Nichts. Die Fenster haben keine Textur, es entsteht kein Fenster |
| Halter mit einem Streifen in drei Fenstern | Nur das bestückte Fenster |
| Fenster, das der Scanbereich halbiert | Verworfen |
| Ein Bild, das über das Filmende hinausragt | Verworfen. Innere Bilder bleiben auch unbelichtet erhalten |
| Ein Streifen ohne Hinweise auf periodische Lücken | Nichts |

## Formate

Die Länge entlang des Streifens ist die Richtung des Bildabstands, die Länge quer dazu die Fensterbreite. Beides kommt aus dem gewählten Format, deshalb haben auch Halbformat und 645 ihre Achsen richtig herum.

| Format | Entlang des Streifens | Quer zum Streifen |
|---|---|---|
| 35 mm Vollformat | 36 mm | 24 mm |
| 35 mm quadratisch | 24 mm | 24 mm |
| 35 mm Halbformat | 18 mm | 24 mm |
| 120 · 6×4.5 | 41.5 mm | 56 mm |
| 120 · 6×6 – 6×17 | 56 – 168 mm | 55 – 56 mm |

Der Abstand bei 35 mm folgt aus dem Perforationstransport und bewegt sich kaum, die Suche ist daher eng. Eine 120er-Kamera bestimmt ihren Abstand selbst, die Suche ist weiter. Keiner der beiden ist auf einen festen Wert festgelegt.

## Messungen

Zehn echte Epson-GT-X900-Vorschauen, 1768 × 2906 bei 300 dpi über einen Bereich von 149,86 × 246,38 mm.

| Vorschau | Halter | Ergebnis |
|---|---|---|
| Schwarzweißnegativ, drei Streifen | Original | 3 Fenster × 6 Bilder |
| Schwarzweißnegativ, ein Streifen eingelegt | Original | 1 Fenster × 6 Bilder, die zwei leeren Fenster ignoriert |
| Farbnegativ, drei Streifen | Original | 3 Fenster × 6 Bilder |
| Farbnegativ, ein Streifen eingelegt | Original | 1 Fenster × 6 Bilder |
| Farbdia, drei Streifen | Original | 3 Fenster × 6 Bilder |
| Farbdia, ein Streifen eingelegt | Original | 1 Fenster × 6 Bilder |
| Farbnegativ, Lücken vom Halter verdeckt | Fremdhersteller | 1 Fenster × 5 Bilder |
| Farbnegativ, Halter breiter als der Scanbereich | Fremdhersteller | 2 ganze Fenster, die zwei halben Fenster verworfen |

Angepasster Abstand über alle Streifen: 37,65 – 38,12 mm. Die Erkennung dauert im Debug-Build 0,5 – 0,9 s pro Vorschau.

> [!NOTE]
> Diese Messungen betreffen nur 35 mm. Die 120er-Formate sind durch synthetische Testdaten abgedeckt, ihre Abstandssuche wurde noch nicht an einer echten 120er-Vorschau geprüft.

## Wo der Code liegt

| Datei | Aufgabe |
|---|---|
| `FlatbedFrameGridDetector.swift` | Einstieg, Formatgeometrie, Bildausdehnung |
| `FlatbedFrameGridDetector+Profiles.swift` | Spalten- und Zeilenprofile, Textur, gemeinsame Statistik |
| `FlatbedFrameGridDetector+Slots.swift` | Fenster, Filmvorhandensein, Bänder |
| `FlatbedFrameGridDetector+Grid.swift` | Lückenhinweise, Kammanpassung, Grenzverfeinerung |

`FlatbedFrameDetector` bleibt als Rückfall für eine Vorschau mit unbekannter physischer Größe.
