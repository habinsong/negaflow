# Chroma Engine

[Dokumentationsstart](../README.md)

Chroma Engine invertiert und entwickelt Film. Der Code liegt im Modul `Chromabase`. App und CLI nutzen dasselbe Modul, dieselbe Eingabe durchläuft also dieselbe Reihenfolge von Schritten.

| Auf einen Blick | Einzelheiten |
|---|---|
| Standardentwicklung | `MAIN`, Auto-Abgleich ON |
| Filmbasis | Automatische Messung, Pipette, direkte RGB-Eingabe |
| Interne Farbe | Linearer 32-Bit-Gleitkomma-Farbraum |
| Automatische Funktionen | Auto-Abgleich ON |
| Ausgabefarbraum | sRGB, Display P3, Adobe RGB, eigenes RGB-ICC |

> [!IMPORTANT]
> Voreingestellt sind `MAIN` und Auto-Abgleich ON. Der Schalter ist eine kleine Pille rechts neben der Zielüberschrift. Er erscheint nur bei Farb- und S/W-Negativen mit MAIN (einschließlich PRINT) und CS. Er passt Farbe und Helligkeit an das aktuelle Bild an, bei OFF entfällt dieser Schritt. Automatische Tonwerte, Automatischer Weißabgleich, Auto-Tonwertkorrektur und Auto-Farbe sind eigene Funktionen und standardmäßig OFF.

## Was Vorrang hat

1. Lässt sich die Filmbasis messen, geht die Messung dem nach Namen gewählten Standardwert vor.
2. Filmeigenschaften, Scanlichtquelle, Scannerstil und automatische Szenenkorrektur werden getrennt gehalten.
3. Funktionen wie Automatische Tonwerte und Automatischer Weißabgleich schalten sich nur ein, wenn Sie sie ausführen.
4. Dieselbe Quelle, dieselben Bearbeitungswerte und dasselbe Profilpaket durchlaufen dieselbe Reihenfolge.
5. Synthetische Tests und Prüfungen an echten Geräten werden nie als gleichwertiger Beleg ausgegeben.

## Reihenfolge der Schritte

Das Arbeitsbild wird in einem linearen 32-Bit-Gleitkomma-Farbraum verarbeitet. Nur Operationen, die ein Gamma brauchen, rechnen an ihrer festen Stelle um, und die Kodierung für Bildschirm oder Dateiformat folgt am Ende.

1. Datei lesen und Ausrichtung korrigieren.
2. Lineare Eingabe (Kamera-RGB bei RAW).
3. Filmart: Ein Positiv geht in die Positivverarbeitung, bei einem Negativ wird die Basis gemessen.
4. Optische Dichte und Invertierung, dann Auto-Abgleich ON oder OFF, dann die RAW-Kameramatrix.
5. Entwicklungsziel und Profile.
6. Tonwert, Farbe und lokale Anpassung.
7. Detail und Effekte.
8. Anzeige- oder Ausgabefarbraum.

Der `CIContext` wird nicht für jedes Rendern neu gebaut. Er wird wiederverwendet, nach Zweck getrennt: Anzeige, Analyse, Export. Die Vorschau berechnet nur die nötige Größe und die neueste Bearbeitungsversion, und der Export rendert erneut in Quellgröße.

Apples Core-Image-Dokumentation:

- [CIImage](https://developer.apple.com/documentation/coreimage/ciimage)
- [CIContext](https://developer.apple.com/documentation/coreimage/cicontext)
- [workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontext/workingcolorspace)
- [Core Image performance guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_performance/ci_performance.html)

## Filmbasis

### Warum gemessen wird

Der unbelichtete Teil eines Negativs ist ein Bezugspunkt, der Film, Entwicklung und Scanlichtquelle vereint. Die orange Maske des Farbnegativs gehört dazu. Liegt die Basis falsch, stimmen alle folgenden Dichten und Kanalbeziehungen nicht mehr. Auch Kodaks Daten zur Portra 400 führen Mindestdichte, Kennlinien und spektrale Farbstoffdichte getrennt auf.

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)

### Automatische Messung

`FilmBaseEstimator` wertet die räumliche Verteilung heller Pixel über das ganze Bild aus, um die unbelichtete Basis zu erkennen.

- Ein Filmpixel kann nicht heller sein als die unbelichtete Basis.
- Was viel heller ist, kann Gegenlicht, Perforation oder Bereich außerhalb des Films sein.
- Eine echte Basis bildet meist ein breites Band am Bildrand.
- Bei mehreren Filmstreifen auf einem Blatt können getrennte Bereiche gemeinsam gelesen werden.
- Einer Grenze, an der sich Halter und Film mischen, wird weniger getraut als dem Inneren.

Sie ermittelt die Helligkeitsverteilung auf einem verkleinerten Analysebild, gruppiert zusammenhängende Bereiche und entfernt dann Kandidaten außerhalb des Films. Bestehen mehrere Streifen die Bedingungen, werden sie gemeinsam berechnet. Das Ergebnis hält auch fest, welche Methode gewählt wurde und wie sicher sie ist.

### Methode wählen

| Modus | Verhalten |
|---|---|
| `Manual` | Nutzt das eingegebene RGB als Dmin. Auch eine erfolgreiche Pipettenwahl landet hier. |
| `Film` | Nutzt die Messung als Dmin, und der gewählte Film liefert vor allem `dmaxNorm`. Standardwerte von Film und Lichtquelle kommen nur ins Spiel, wenn die Messung scheitert. |
| `Auto` | Nutzt die räumliche Analyse und fällt bei einem Fehlschlag auf die randbasierte Methode zurück. |

Ohne manuellen Wert oder mit falscher Film-ID geht es zur nächsten sicheren Methode. Das hellste Objekt der Szene wird nie unmittelbar als Filmbasis genommen.

## Optische Dichte und Invertierung

Die Dichte ergibt sich aus der linearen Transmission `T` und der Basis je Kanal `Dmin`:

```math
D = \log_{10}\left(\frac{D_{\min}}{T}\right)
```

`D = 0` heißt, die Eingabe entspricht der unbelichteten Basis. Perforation oder Gegenlicht können negativ werden. Diese Werte bleiben endlich und werden nicht sofort beschnitten.

### Daten je Filmart

Die aktuelle Tabelle enthält 27 Filmnamen für Farbnegativ, Schwarzweiß und Kinonegativ. Die Daten dienen für:

- Den Dmin-Standardwert, wenn die Basis nicht gemessen werden kann
- Feste, auf die Filmart bezogene Dichtefaktoren

Manche Werte wurden durch Ablesen von Kurven in öffentlichen Unterlagen angenähert, manche vorsichtig gesetzt. 27 Namen sind keine 27 geprüften Farbprofile, und ist die Basis gemessen, hat die Messung Vorrang.

### MAIN/PRINT und CS

Bei Auto-Abgleich ON nutzt jeder Kanal das dichteste 0,2-%-Perzentil der Szene mit einer Bereichsgrenze von 1,8D, danach folgen die Kurve `shoulder-print-response-v4` und die Vibrance für gedämpfte Szenen. OFF nutzt dieselbe Kurve mit festem Nennbereich (Farbe 1,55D, S/W 2,17D). Bei Farbnegativen multipliziert OFF zusätzlich eine Kanalbereichskalibrierung für Scanner und Film, gewonnen aus mindestens drei Bildern desselben Films.

ON kann mit dem Szeneninhalt Helligkeit und Farbe verändern. Keiner der beiden Modi belegt eine gemessene Farbgenauigkeit des Films. Formeln, die 1,8D-Grenze und die RAW-Reihenfolge stehen in:

[Negativantwort](../reference/PRINT_RESPONSE.md)

## Drei Arten von Profilen

| Art | Die Frage, die sie beantwortet | Werte |
|---|---|---|
| Filmart | Wie sind Basis und Dichtebereich des Films | Dmin/Dmax, Filmart |
| Lichtquelle | Wie hat die Scanlichtquelle jeden Kanal beeinflusst | Kanalgewinn, basisgesteuerte Korrektur |
| Scannerziel | Welchen Tonwert- und Farbstil hat das Ergebnis | Relative Statistik aus für dieses Projekt gemachten Scans |

Die Trennung verhindert, dass ein einziger Filmname Emulsionseigenschaften, Lichtquellenfarbe und den Ausgabestil eines Labors zugleich vertritt. Gibt es eine echte Basis, geht die Messung den Standardwerten der Lichtquelle vor. Scannerstatistiken werden nicht unmittelbar als absolute Farbmatrix einer Szene verwendet.

Die Daten sind in [Filmprofile](FILM_PROFILES.md) beschrieben.

## Entwicklungsziele

### `MAIN`

Das Standardziel mit Auto-Abgleich ON. Der Schalter ist am Anfang dieser Seite beschrieben.

### `PRINT`

Das Arbeitsbild entspricht `MAIN`. Ein gültiges RGB-Drucker-ICC wird einmal am Ende des Exports angewendet. Ein fehlendes oder ungültiges Profil schlägt fehl, statt auf sRGB oder beliebige Papierwerte zurückzufallen.

### `HS`, `SP`

Ein festes Rendering nach der Invertierung. Es liest nichts aus dem Bild, ein Pixel liefert also in jedem Foto dasselbe Ergebnis. Belichtung und Farbe je Bild gehören zur Invertierung und zu den Schaltflächen Automatische Tonwerte, Automatischer Weißabgleich, Auto-Tonwertkorrektur und Auto-Farbe rechts.

Das Rendering besteht aus einer Luminanz-Tonwertkurve, einem helligkeitsabhängigen Sättigungsgewinn und bei `HS` einer leichten Neigung der Grauachse. Alle Kurven sind monotone kubische Kurven, an den Stützstellen knickt nichts.

- `SP` stammt aus vier Bildern eines Films, die auf einem echten SP-3000 und auf dem eigenen Scanner des Projekts gescannt und pixelgenau zugeordnet wurden. Die Tonwertkurve bezieht ein Viertel ihres Gewichts aus den Perzentilen von 185 SP-3000-Bildern. Auf diesen vier Bildern sinkt das mediane CIEDE2000 zum SP-3000-Scan von etwa 7,4 bei `MAIN` auf 3,9. Ein dunkles Bild bewegt sich kaum, weil das Labor dort bildweise einen roten Tiefenstich entfernt hat, was ein festes Rendering nicht kann.
- `HS` hat keine Pixelpaare. Es geht von `SP` aus und addiert den medianen Unterschied beider Maschinen auf drei Filmen mit übereinstimmenden Film- und Rollennamen: etwas dunklere Mitten, etwas höhere Weißwerte, farbige Pixel mit 0,88-facher Sättigung und Grautöne mit Grünstich in der helleren Hälfte (a* etwa −1 bis −4).
- `HS` schärft den Helligkeitskanal. Der Radius beträgt 0,9 px bei der 35-mm-Ausgabe der Maschine (3089 px lange Kante) und skaliert mit der Auflösung, sodass Vorschau und Export übereinstimmen. Die Stärke wurde nicht gemessen.

Die Wahl eines mitgelieferten Profils fügt weiterhin `scannerSignature` hinzu, den relativen Unterschied von Filmen, deren Namen und Bildzahlen auf beiden Maschinen übereinstimmen. Alle heutigen Profile sind `realOnly`.

- Der relative Unterschied wird nur berechnet, wenn Filmnamen und Bildzahlen nah genug beieinanderliegen.
- Werte, deren Richtung kippt, werden nicht angewendet.
- Bei Schwarzweiß entfallen die Farbanteile.
- Stimmt der SHA-256 einer Datei oder des Manifests nicht, wird das gesamte Profilpaket abgelehnt.

### `F135`, `HR`

Dieses Projekt hat keine Referenzscans eines Pakon F-135 oder Kodak HR-500, deshalb ist keines der beiden Ziele an seiner Maschine geprüft. Beide gehen vom gemessenen `SP`-Rendering aus, dazu die Kurve des Kodak Endura Premier Papiers (Datenblatt E-4070), angepasst an dessen Mitte. Ab einer Blendenstufe unter Mittelgrau aufwärts teilen sie diese Kurve. Sie unterscheiden sich in den Schatten.

- `F135` folgt dem Papier bis −2 Blendenstufen. Ab −3 Stufen abwärts bleibt es 0,9 Stufen unter `SP`, so weit hat der Papierfuß es höchstens abgesenkt. Die Schwärzen sind tiefer als bei `SP`, jede Schattenstufe bleibt aber getrennt: Der lokale Kontrast liegt dort bei mindestens 91 % von `SP`.
- `HR` übernimmt unter −4 Stufen die gemessenen Schatten von `SP`. Die Punkte bei −3 und −2 Stufen liegen etwas tiefer, damit die Kurve ohne Kontrasteinbruch in die Papiermitte steigt. Die Schatten sind bis zu 5,4 L* heller als bei `F135`, die Sättigung ist 0,92-fach.

Eine Prüfung braucht, was `SP` hatte: dieselben Negative, auf der echten Maschine gescannt.

### `EXPIRED`

Ein Rettungsziel für alten Film. Es entsättigt nicht pauschal und dehnt den Bereich nicht, sondern bleibt bei einer begrenzten Korrektur, die die aktuellen Belege tragen.

### `CS`

`CS` (Custom) fasst 18 Farbstile in drei Gruppen zusammen: Emulsion, Reversal, Dye Transfer, Skip Bleach, Plate Glass, Amber Glass, Ultramarine, Terracotta, Celadon, Nacre und Dichroic (11); Wetzlar, Classic, Studio und Rochester (4); Slide Show, Cinema und Point & Shoot (3).

Ein Custom-Ziel nutzt die `MAIN`-Invertierung mit Auto-Abgleich und wendet danach die Antwort von custom-3 für Tonwert, Dichte und Chroma an. Scannerprofile werden dafür nicht verwendet. Die CLI nimmt dieselben IDs, zum Beispiel `--target classic`.

## Der Film-Look bei digitaler Quelle

Der Reiter Film links bietet Dia- und Farbnegativemulsionen. Bei einem Scan sind das nur eine Farbumrechnung, denn der Scan trägt Spielraum, Dichteantwort, Streuung und Korn des Films bereits in seinen Pixeln.

Ein digitales Foto hat nichts davon. Eine Messung zeigte, was eine bloße Farbumrechnung dort bewirkt: Bei kameragerenderter Eingabe fielen die Lichterstufen auf 0,0031, etwa ein Vierzehntel derselben Stufen bei flacher Eingabe, während die Sättigung dennoch stieg. Das Ergebnis wirkt wie ein digitaler Filter.

Eine als `Digital Color` oder `Digital B&W` markierte Quelle durchläuft deshalb eine eigene Kette, die der Reihe nach nachbildet, was der Film tut:

1. Die Anzeigewiedergabe der Kamera rückgängig machen, um die Belichtung zu schätzen, die der Film erhielte. Ausgefressene Details kommen nicht zurück, es ist eine plausible Rekonstruktion.
2. Streuung und Halation hinzufügen, solange das Bild noch linear ist und bevor es Dichte gibt. Zurückkehrendes Licht trifft zuerst die rote Schicht und erzeugt einen rot betonten Schein. Es verteilt Licht um, ohne Energie hinzuzufügen.
3. Virtuelle Entwicklung. Eine Kennlinie baut Dichte auf, DIR-Kuppler hemmen benachbarte Schichten, und ein Negativ läuft dann durch RA-4-Papier. Das niedrige Gamma eines Negativs und das hohe Gamma des Papiers sind zwei getrennte Kurven, wodurch die Lichter ohne Beschnitt auslaufen.
4. Die Farbsignatur der Emulsion, da der Kontrast schon aus Schritt 3 kam.
5. Korn, das der Dichte folgt, und eine Kantenantwort aus der MTF des Datenblatts.

Scanquellen betreten diese Kette nie. Der Schalter ist allein das Quellenkennzeichen, und der Scanpfad bleibt unverändert.

Die Belichtung wird auf den Spielraum jeder Emulsion umskaliert. Ein Umkehrfilm wird etwa eine Blende über Mittelgrau weiß, würde man eine Digitalszene mit sechs Blenden unverändert hineinschieben, bliebe also gar kein Lichterdetail. Die Umskalierung bewahrt die Kontrastrangfolge jeder Emulsion.

Korn und Halation werden zu Filmeigenschaften, sobald eine Emulsion gewählt ist. Die Texturregler stellen daher deren Stärke ein, statt einen zweiten, getrennten Effekt hinzuzufügen.

## Entwicklungsregler

| Gruppe | Einträge |
|---|---|
| Tonwert | Belichtung, Kontrast, Lichter, Tiefen, Weiß, Schwarz, RGB- und kanalweise Punktkurven |
| Farbe | Temperatur, Tönung, Dynamik, Sättigung, HSL mit 8 Farben, Farb-Grading in drei Zonen, Kanalkorrektur, Schwarzweißumwandlung und -tonung |
| Detail und Effekte | Schärfe, Klarheit, Dunstentfernung, Filmkorn, Vignette, Halation, Rauschminderung |
| Lokale Anpassung | Radiale, lineare, Polygon- und Pinselmasken, Abwedeln und Nachbelichten |

Diese Werte werden als schrittweiser Bearbeitungsverlauf gespeichert. GrainMend und die gewöhnliche lokale Anpassung unterscheiden sich in Zweck und Speicherung.

### Automatische Korrekturen

| Regler | Verhalten |
|---|---|
| Automatische Tonwerte | Legt Belichtung, Kontrast, Dichte, Lichter, Tiefen, Weiß und Schwarz fest. Behält die Farbregler und Kurven des Nutzers. |
| Automatischer Weißabgleich | Schätzt Temperatur und Tönung aus nahezu neutralen Helligkeitsbändern. Verwirft Proben mit beschnittenem RGB-Kanal und mindert die Korrektur, wenn Hinweise auf Neutrales spärlich sind oder nur einen engen Tonwertbereich abdecken. |
| Auto-Tonwertkorrektur | Misst gemeinsame Helligkeitsendpunkte und wendet denselben Helligkeitsgewinn auf RGB an. Bewahrt die Kanalverhältnisse, statt jeden Kanal getrennt zu dehnen. |
| Auto-Farbe | Passt verbleibende Farbstiche an neutrale Kandidaten an. Nutzt Kanalsteigungen nur, wenn eine Anpassung getrennte, ungenutzte Helligkeitsbänder vorhersagt, sonst Gewinne. Schwache Ersatzhinweise erhalten weniger Korrektur. |

Automatische Tonwerte prüft den ersten Vorschlag an einer gerenderten Vorschau. Schlägt es eine weitere Änderung von Belichtung oder Weißpunkt vor, rendert es auch diesen Kandidaten und übernimmt ihn nur, wenn sich eine Bewertung aus Mittelton, Endpunkten, Tonwertbereich und Beschnitt verbessert. Das ist eine begrenzte Korrektur, keine Suche nach einem einzigen idealen Rendering. Ein wiederholter Befehl weist Einstellungen zu, statt sie anzuhäufen, und ein Zurücksetzen behält die Farbregler des Nutzers.

Die Analyse nutzt flächengewichtete Mittelwerte in linearem RGB mit begrenzter langer Kante. Tonwert und Weißabgleich nutzen eine sRGB-Vorschau, Beschnitt bedeutet also Beschnitt der Vorschaukanäle, nicht Sensorsättigung. Diese Schätzungen können nicht jede Motivfarbe von einem Lichtstich unterscheiden und belegen keine gemessene Farbgenauigkeit des Films. Der Auto-Abgleich von MAIN/CS und seine Vibrance für gedämpfte Szenen gehören zur Invertierungsstufe.

## Farbmanagement

Trägt die Eingabe ein gültiges ICC, wird dieser Farbraum gelesen. Die interne Rechnung läuft im festen linearen Arbeitsraum, und der Wechsel in einen Ausgaberaum geschieht bei Anzeige, Softproof und Export.

Wichtige unterstützte Ausgaben:

- sRGB
- Display P3
- Adobe RGB
- Ein vom Nutzer gewähltes RGB-Drucker- oder Ausgabe-ICC

Name, Bytezahl und SHA-256 des Druckerprofils werden beim Start des Exports festgelegt. Ändert sich die Datei während des Renderns, bricht der Lauf ab.

Es wird nicht behauptet, dass der aktuelle Pfad über Core Image und ColorSync Rendering Intent und Schwarzpunktkompensation auf jeder macOS-Version bitgleich liefert. Diese Garantie bräuchte zuvor einen eigenen ColorSync-Pufferpfad und Speicherprüfungen für große 16-Bit-Bilder.

## Ausgabekodierung

Formateinstellungen liegen außerhalb der Farbpipeline, entscheiden aber, was in der gelieferten Datei erhalten bleibt.

JPEG speichert Farbe in geringerer Auflösung als Helligkeit, sofern der Encoder nicht über seine Unterabtastungsschwelle hinaus getrieben wird. Darunter wird die Chrominanz horizontal und vertikal halbiert, was gesättigte Kanten weicher macht, während das Helligkeitsdetail erhalten bleibt. Eine Qualität ab 95 % wird deshalb ohne Chroma-Unterabtastung kodiert, niedrigere Einstellungen behalten den gewählten Wert, weil man mit ihnen eine kleinere Datei verlangt. PNG und TIFF sind verlustfrei und tasten nie unter ab. Ihre einzige Qualitätsstellschraube ist die Bittiefe, 8 oder 16 Bit je Kanal, und Dithering wird nur bei 8 Bit angewendet, wo es Quantisierungsbänder verdeckt.

## Leistung und Sicherheit

- Der `CIContext` wird je Zweck wiederverwendet.
- Anpassungen nutzen eine Vorschau niedrigerer Auflösung, und der Export baut aus der Quelle neu auf.
- Lang laufende Aufgaben prüfen Bild-ID, Bearbeitungsversion und Sitzung unmittelbar vor dem Anwenden eines Ergebnisses erneut.
- Wird der Speicher knapp, werden Caches wie Miniaturen und Vorschauen verworfen.
- Originale und Bearbeitungsverlauf werden von Caches getrennt gehalten.

## Prüfstufen

1. Formeltests: Monotonie der Kurve, Anker, Umkehrfunktion
2. Synthetische Bilder: bekannte Eingabe und Ausgabe, Beschnitt, Ausrichtung, Farbraum
3. Synthetisches IT8: die mathematische Hin- und Rückrechnung über 264 Felder
4. Echte Aufnahmestatistik: die `realOnly`-Profile
5. REAL/TARGET-Paare: eine Geräte-Qualitätsprüfung mit getrenntem Validierungsmaterial
6. Echte Hardware: ein tatsächlicher Scanner, Film, Bildschirm und Abzug

Ein gutes synthetisches IT8-Ergebnis belegt keine absolute Genauigkeit bei echten Negativen. Die Beurteilung der Qualität von Scannerprofilen folgt [Qualitätsprüfung der Scannerprofile](../reference/PROFILE_QUALITY_GATE.md) und [IT8-Farbprüfung](../reference/IT8_COLOR_VALIDATION.md).

## Wo der Code liegt

- `Sources/Chromabase/Engine/`
- `Sources/Chromabase/Film/`
- `Sources/Chromabase/Develop/`
- `Sources/Chromabase/Adjustments/`
- `Sources/Chromabase/Profiles/`
- `Sources/Chromabase/Imaging/`
- `Sources/Chromabase/Export/`

Die aktuelle Produktversion ist `1.2.6`. Änderungen an Bearbeitungsverlauf und Profilschemata müssen auch in späteren Versionen eine Prüfung durchlaufen.
