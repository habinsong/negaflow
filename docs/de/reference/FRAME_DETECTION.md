# Wie die Bilderkennung am Flachbettscanner den Film findet

[Dokumentationsstart](../README.md)

Eine Flachbett-Vorschau zeigt den Halter, das Licht, das daran vorbeikommt, und den eingelegten Film, falls einer da ist. Die automatische Bilderkennung muss entscheiden, welche Teile dieses Bildes Film sind und wo ein Bild endet und das nächste beginnt, bevor sich der eigentliche Scan lohnt.

Der Detektor kennt die tatsächliche Größe des vorgeschauten Bereichs in Millimetern und rechnet ein Filmformat deshalb exakt in Pixel um, statt es aus Seitenverhältnissen zu raten.

## Film erkennt man am Korn

An der Helligkeit lassen sich Film und leere Fenster nicht unterscheiden. Messwerte aus einer Epson GT-X900-Vorschau:

| Was in der Spalte liegt | Mittlere Helligkeit |
|---|---|
| Leeres Halterfenster, Licht geht ungehindert durch | 0,92 |
| Film im Nachbarfenster | 0,10 |
| Haltermaske | 0,002 |
| Zubehörhalter mit weißem Hintergrund | 1,00 |

Wer nach Helligkeit sucht, wählt leere Fenster und verwirft den Film. Bei einem Halter mit weißem Grund kippt die Reihenfolge komplett um.

Das Korn trennt beides eindeutig, denn Filmkorn und Motiv gibt es nur auf dem Film:

| Was in der Spalte liegt | Detail senkrecht |
|---|---|
| Film | 0,0044 bis 0,032 |
| Haltermaske, leeres Fenster, weißer Hintergrund | 0,00005 bis 0,001 |

Der Unterschied beträgt über eine Zehnerpotenz und wechselt das Vorzeichen bei keinem Filmtyp, Halter oder Positiv/Negativ. Alle folgenden Schritte bauen darauf auf.

## Stufen

1. **Spaltenkorn.** Das Detail wird spaltenweise über die Vorschau gemessen. Spalten mit Korn und Motiv werden zu Fensterkandidaten.
2. **Fenster.** Kandidatenspalten wachsen bis zum Filmrand und werden mit der Breite des gewählten Formats abgeglichen. Fenster, die den Rand des Scanbereichs berühren, werden verworfen. Sie sind vom Scanbereich abgeschnitten, der Hauptscan würde die falsche Stelle erfassen.
3. **Abschnitte.** Im Fenster werden die Bildzeilen von den Stegen oben und unten getrennt. Eine Zeile zählt als Film, wenn sie sich von den Stegen daneben unterscheidet **oder** Korn trägt. Helligkeit allein verliert dichte Dias, Korn allein verliert Zwischenräume und strukturlose Bilder.
4. **Raster.** Ein Kamm aus Stegpositionen wird über die gesamte (Abstand, Phase)-Ebene eingepasst. Bewertet wird der Kontrast zwischen Bild und Steg, sodass es keine Rolle spielt, ob der Zwischenraum klarer Träger, Maximaldichte oder von einer Halterrippe verdeckt ist.
5. **Korrektur.** Jede Grenze springt an den nächsten Zwischenraum, anschließend wird der Satz wieder auf gleichen Abstand ausgerichtet. Die Bilder eines Streifens liegen in gleichem Abstand. Zwei Scans desselben Streifens landen innerhalb von 0,2 mm an derselben Stelle.

## Was abgelehnt wird

| Situation | Ergebnis |
|---|---|
| Halter ohne Film | Nichts. Die Fenster haben kein Korn, es entsteht kein Fenster |
| Nur ein Streifen in drei Fenstern | Nur das bestückte Fenster |
| Vom Scanbereich halbiertes Fenster | Verworfen |
| Bild, das über das Filmende hinausragt | Verworfen; innenliegende Bilder bleiben auch unbelichtet |
| Streifen ohne Beleg für periodische Zwischenräume | Nichts |

## Formate

Die Länge entlang des Streifens ist die Richtung des Bildabstands, die Länge quer dazu die Fensterbreite. Beide kommen aus dem gewählten Format, deshalb stimmen bei Halbformat und 645 die beiden Achsen.

| Format | Entlang des Streifens | Quer dazu |
|---|---|---|
| 35 mm Vollformat | 36 mm | 24 mm |
| 35 mm quadratisch | 24 mm | 24 mm |
| 35 mm Halbformat | 18 mm | 24 mm |
| 120 · 6×4,5 | 41,5 mm | 56 mm |
| 120 · 6×6 bis 6×17 | 56 bis 168 mm | 55 bis 56 mm |

Der Abstand bei 35 mm wird vom Perforationstransport bestimmt und bewegt sich kaum, die Suche ist deshalb eng. Eine 120-Kamera legt ihren Abstand selbst fest, hier wird weiter geöffnet. Keiner der beiden Werte ist fest verdrahtet.

## Messergebnisse

Zehn echte Vorschauen eines Epson GT-X900, 1768 × 2906 bei 300 dpi über 149,86 × 246,38 mm.

| Vorschau | Halter | Ergebnis |
|---|---|---|
| Schwarzweißnegativ, drei Streifen | Original | 3 Fenster × 6 Bilder |
| Schwarzweißnegativ, nur ein Streifen | Original | 1 Fenster × 6 Bilder, die zwei leeren ignoriert |
| Farbnegativ, drei Streifen | Original | 3 Fenster × 6 Bilder |
| Farbnegativ, nur ein Streifen | Original | 1 Fenster × 6 Bilder |
| Farbdia, drei Streifen | Original | 3 Fenster × 6 Bilder |
| Farbdia, nur ein Streifen | Original | 1 Fenster × 6 Bilder |
| Farbnegativ, Zwischenräume vom Halter verdeckt | Fremd | 1 Fenster × 5 Bilder |
| Farbnegativ, Halter breiter als der Scanbereich | Fremd | 2 ganze Fenster; die 2 halben verworfen |

Angepasster Abstand über alle Streifen: 37,65 bis 38,12 mm. Die Erkennung dauert im Debug-Build 0,5 bis 0,9 s pro Vorschau.

> [!NOTE]
> Diese Messung umfasst nur 35 mm. Die 120-Formate sind nur durch synthetische Vorlagen abgedeckt, ihre Abstandssuche wurde noch nicht an einer echten 120-Vorschau geprüft.

## Wo der Code liegt

| Datei | Aufgabe |
|---|---|
| `FlatbedFrameGridDetector.swift` | Einstieg, Formatgeometrie, Bildausdehnung |
| `FlatbedFrameGridDetector+Profiles.swift` | Spalten- und Zeilenprofile, Korn, gemeinsame Statistik |
| `FlatbedFrameGridDetector+Slots.swift` | Fenster, Filmpräsenz, Bänder |
| `FlatbedFrameGridDetector+Grid.swift` | Zwischenraumbelege, Kammanpassung, Grenzfeinabgleich |

`FlatbedFrameDetector` bleibt der Rückfall für eine Vorschau, deren physische Größe unbekannt ist.
