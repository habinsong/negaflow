# Wie die Bilderkennung am Flachbettscanner den Film findet

[Dokumentationsstart](../README.md)

Eine Flachbett-Vorschau zeigt den Halter, das Licht, das daran vorbeikommt, und den eingelegten Film,
falls einer da ist. Die automatische Bilderkennung muss entscheiden, welche Teile dieses Bildes Film
sind und wo ein Bild endet und das nächste beginnt, bevor sich der eigentliche Scan lohnt.

Der Detektor kennt die tatsächliche Größe des vorgeschauten Bereichs in Millimetern und rechnet ein
Filmformat deshalb exakt in Pixel um, statt es aus Seitenverhältnissen zu raten.

## Film erkennt man am Korn, nicht an der Helligkeit

Helligkeit unterscheidet Film nicht von einem leeren Halterfenster. Gemessen an einer Vorschau eines
Epson GT-X900:

| Was in der Spalte steht | Mittlere Helligkeit |
|---|---|
| Leeres Halterfenster, Lampe scheint direkt hindurch | 0,92 |
| Film im Nachbarfenster | 0,10 |
| Maske des Halters | 0,002 |
| Fremdhalter mit weißem Hintergrund | 1,00 |

Nach Helligkeit zu sortieren greift also die leeren Fenster heraus und verwirft den Film, und ein
Halter mit weißem Hintergrund kehrt die Reihenfolge komplett um.

Korn kennt diese Zweideutigkeit nicht, denn Korn und Bild gibt es nur auf Film:

| Was in der Spalte steht | Vertikales Detail |
|---|---|
| Film | 0,0044 bis 0,032 |
| Maske, leeres Fenster, weißer Hintergrund | 0,00005 bis 0,001 |

Der Abstand beträgt mehr als eine Größenordnung und dreht sich weder mit der Filmart noch mit dem
Halter oder der Polarität um. Alle folgenden Stufen bauen darauf auf.

## Stufen

1. **Spaltenkorn.** Das Detail wird entlang jeder Spalte der Vorschau gemessen. Spalten mit Korn und
   Bild werden zu Fensterkandidaten.
2. **Fenster.** Die Kandidaten werden bis zum Filmrand erweitert und mit der Breite des gewählten
   Formats verglichen. Ein Fenster, das den Rand des gescannten Bereichs berührt, fällt heraus: der
   Scanbereich hat es halbiert und der eigentliche Scan würde die falsche Stelle aufnehmen.
3. **Bänder.** Innerhalb eines Fensters werden die Zeilen mit Film vom Halter darüber und darunter
   getrennt. Eine Zeile gilt als Film, wenn sie sich vom Halter daneben unterscheidet **oder** Korn
   trägt; Helligkeit allein verliert die dichten Bilder eines Dias, Korn allein verliert die
   Zwischenräume und die flachen Bilder.
4. **Raster.** Ein Kamm aus Zwischenraumpositionen wird über die gesamte Ebene (Abstand, Phase)
   angepasst. Bewertet wird der Kontrast zwischen dem Inneren eines Bildes und dem Zwischenraum; die
   Anpassung hängt also nicht davon ab, ob der Zwischenraum klarer Träger, maximale Dichte oder eine
   ihn verdeckende Halterstrebe ist.
5. **Feinabgleich.** Jede Grenze wird auf den nächsten Zwischenraum gezogen, danach wird der ganze
   Satz auf gleichmäßigen Abstand neu angepasst, denn die Bilder eines Streifens liegen gleichmäßig.
   Zweimaliges Scannen desselben Streifens liegt innerhalb von 0,2 mm.

## Was abgelehnt wird

| Situation | Ergebnis |
|---|---|
| Halter ohne Film | Nichts. Die Fenster haben kein Korn, es entsteht kein Fenster |
| Nur ein Streifen in drei Fenstern | Nur das bestückte Fenster |
| Vom Scanbereich halbiertes Fenster | Verworfen |
| Bild, das über das Filmende hinausragt | Verworfen; innenliegende Bilder bleiben auch unbelichtet |
| Streifen ohne Beleg für periodische Zwischenräume | Nichts statt eines willkürlichen Rasters |

## Formate

Die Länge entlang des Streifens ist die Richtung des Bildabstands, die Länge quer dazu die
Fensterbreite. Beide kommen aus dem gewählten Format, deshalb stimmen bei Halbformat und 645 die
beiden Achsen.

| Format | Entlang des Streifens | Quer dazu |
|---|---|---|
| 35 mm Vollformat | 36 mm | 24 mm |
| 35 mm quadratisch | 24 mm | 24 mm |
| 35 mm Halbformat | 18 mm | 24 mm |
| 120 · 6×4,5 | 41,5 mm | 56 mm |
| 120 · 6×6 bis 6×17 | 56 bis 168 mm | 55 bis 56 mm |

Der Abstand bei 35 mm wird vom Perforationstransport bestimmt und bewegt sich kaum, die Suche ist
deshalb eng. Eine 120-Kamera legt ihren Abstand selbst fest, hier wird weiter geöffnet. Keiner der
beiden Werte ist fest verdrahtet.

## Was gemessen wurde

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

Angepasster Abstand über alle Streifen: 37,65 bis 38,12 mm. Die Erkennung dauert im Debug-Build 0,5
bis 0,9 s pro Vorschau.

> [!NOTE]
> Diese Messung umfasst nur 35 mm. Die 120-Formate sind nur durch synthetische Vorlagen abgedeckt,
> ihre Abstandssuche wurde noch nicht an einer echten 120-Vorschau geprüft.

## Wo der Code liegt

| Datei | Aufgabe |
|---|---|
| `FlatbedFrameGridDetector.swift` | Einstieg, Formatgeometrie, Bildausdehnung |
| `FlatbedFrameGridDetector+Profiles.swift` | Spalten- und Zeilenprofile, Korn, gemeinsame Statistik |
| `FlatbedFrameGridDetector+Slots.swift` | Fenster, Filmpräsenz, Bänder |
| `FlatbedFrameGridDetector+Grid.swift` | Zwischenraumbelege, Kammanpassung, Grenzfeinabgleich |

`FlatbedFrameDetector` bleibt der Rückfall für eine Vorschau, deren physische Größe unbekannt ist.
