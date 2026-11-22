# Chroma Engine

[Dokumentationsstart](../README.md)

Chroma Engine invertiert und entwickelt Film. Der Code liegt im Modul `Chromabase`. App und CLI nutzen dasselbe Modul, dieselbe Eingabe durchläuft also dieselbe Reihenfolge von Schritten.

| Auf einen Blick | Einzelheiten |
|---|---|
| Standardentwicklung | `MAIN`, Auto-Abgleich ON |
| Filmbasis | Automatische Messung, Pipette, direkte RGB-Eingabe |
| Interne Farbe | Linearer Gleitkomma-Farbraum (16-Bit-Half-Float unter macOS, 32-Bit-Float unter Windows) |
| Automatische Funktionen | Auto-Abgleich ON |
| Ausgabefarbraum | sRGB, Display P3 und Adobe RGB sowie RGB-Drucker-ICC `prtr` für den Export (`prtr`/`mntr`/`spac` für den Softproof) |

> [!IMPORTANT]
> Voreingestellt sind `MAIN` und Auto-Abgleich ON. Der Schalter ist eine kleine Pille rechts neben der Zielüberschrift. Er erscheint nur bei Farb- und S/W-Negativen mit MAIN (einschließlich PRINT) und CS. Er passt Farbe und Helligkeit an das aktuelle Bild an, bei OFF entfällt dieser Schritt. Automatische Tonwerte, Automatischer Weißabgleich, Auto-Tonwertkorrektur und Auto-Farbe sind eigene Funktionen und standardmäßig OFF.

## Was Vorrang hat

1. Lässt sich die Filmbasis messen, geht die Messung dem nach Namen gewählten Standardwert vor.
2. Filmeigenschaften, Scanlichtquelle, Scannerstil und automatische Szenenkorrektur werden getrennt gehalten.
3. Funktionen wie Automatische Tonwerte und Automatischer Weißabgleich schalten sich nur ein, wenn Sie sie ausführen.
4. Dieselbe Quelle, dieselben Bearbeitungswerte und dasselbe Profilpaket durchlaufen dieselbe Reihenfolge.
5. Synthetische Tests und Prüfungen an echten Geräten werden nie als gleichwertiger Beleg ausgegeben.

## Reihenfolge der Schritte

Das Arbeitsbild wird in einem linearen Gleitkomma-Farbraum verarbeitet: 16-Bit-Half-Float in Core Image unter macOS, 32-Bit-Float in der Windows-Engine. Beide behalten Werte unter 0 und über 1. Farbmischer, Farb-Grading, Kalibrierung und Punktkurven arbeiten in perzeptiver sRGB-Kodierung auf `[0, 1]` und bewahren dabei Werte außerhalb des Bereichs (`< 0` oder `> 1`). Vor der endgültigen Kodierung für Bildschirm oder Datei bildet `DisplayGamutMap` Farben außerhalb des Gamuts ohne Farbtonverschiebung in die linearen Primärvalenzen des Ziel-Ausgabefarbraums ab.

1. Datei lesen und Ausrichtung korrigieren.
2. Lineare Eingabe (Kamera-RGB bei RAW).
3. Filmart: Ein Positiv geht in die Positivverarbeitung, bei einem Negativ wird die Basis gemessen.
4. Optische Dichte und Invertierung, dann Auto-Abgleich ON oder OFF, dann die RAW-Kameramatrix.
5. `EXPIRED`-Rettungskorrektur (falls gewählt), dann Weißabgleich, Belichtung, Basis-Tonwerte und die parametrische Kurve.
6. Scannerziel (`HS`, `SP`, `F135`, `HR`) und mitgeliefertes Scannerprofil.
7. Punktkurven, Farbmischer, Farb-Grading und Kalibrierung.
8. `CS`-Custom-Ziel und bei digitalen Quellen der digitale Film-Look.
9. Softwareseitige Defektentfernung und Rauschminderung.
10. Lokales Abwedeln und Nachbelichten, Detail und Textur sowie Geometrie-Transformation.
11. `DisplayGamutMap` und Kodierung im Anzeige- oder Ausgabefarbraum.

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
| `Film` | Nutzt das gemessene `Dmin`, sofern verfügbar, und fällt nur bei einem Fehlschlag auf das `Dmin` des Films zurück. Liefert den relativen Dichtebereichsfaktor des Films (`relativeRangeFactor`) und wendet jeden nicht neutralen Lichtquellengewinn bei Farbnegativen auf das ermittelte `Dmin` an (sowohl gemessen als auch als Rückfallwert). |
| `Auto` | Nutzt die räumliche Analyse und fällt bei einem Fehlschlag auf die randbasierte Methode zurück. |

Ohne manuellen Wert oder mit falscher Film-ID geht es zur nächsten sicheren Methode. Das hellste Objekt der Szene wird nie unmittelbar als Filmbasis genommen.

## Optische Dichte und Invertierung

Die Dichte ergibt sich aus der linearen Transmission `T` und der Basis je Kanal `Dmin`:

```math
D = \log_{10}\left(\frac{D_{\min}}{T}\right)
```

`D = 0` heißt, die Eingabe entspricht der unbelichteten Basis. Perforation oder Gegenlicht können negativ werden. Diese Werte bleiben endlich und werden nicht sofort beschnitten.

### Daten je Filmart

Die aktuelle Tabelle enthält 27 Filmnamen: 23 C-41-Farbnegative und 4 ECN-2-Kinonegative. Die Daten dienen für:

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

Die Trennung verhindert, dass ein einziger Filmname Emulsionseigenschaften, Lichtquellenfarbe und den Ausgabestil eines Labors zugleich vertritt. Wird eine echte Basis gemessen, geht diese Messung dem Standard-`Dmin` des Films vor, während jeder nicht neutrale Lichtquellengewinn bei Farbnegativen weiterhin auf das ermittelte `Dmin` (gemessen wie auch Rückfallwert) angewendet wird. Scannerstatistiken werden nicht unmittelbar als absolute Farbmatrix einer Szene verwendet.

Die Daten sind in [Filmprofile](FILM_PROFILES.md) beschrieben.

## Entwicklungsziele

### `MAIN`

Das Standardziel mit Auto-Abgleich ON. Der Schalter ist am Anfang dieser Seite beschrieben.

### `PRINT`

Das Arbeitsbild entspricht `MAIN`. Ein gültiges RGB-Drucker-ICC wird einmal am Ende des Exports angewendet. Ein fehlendes oder ungültiges Profil schlägt fehl, statt auf sRGB oder beliebige Papierwerte zurückzufallen.

### `HS`, `SP`

Ein festes Rendering. Es folgt auf Weißabgleich, Belichtung, die Grundton-Regler und die parametrische Kurve und steht vor Punktkurve, Farbmischer, Color Grading und Kalibrierung. Ein Labor arbeitet genauso: Die Dichte- und Farbkorrektur des Bedieners geht in den Scan, die Printkurve bleibt fest. Es liest nichts aus dem Bild, ein Pixel liefert also in jedem Foto dasselbe Ergebnis. Belichtung und Farbe je Bild gehören zur Invertierung und zu den Schaltflächen Automatische Tonwerte, Automatischer Weißabgleich, Auto-Tonwertkorrektur und Auto-Farbe rechts. Die Neutralpipette misst das Bild vor dem Rendering, die Graustufenneigung von `HS` bleibt nach dem Klick also erhalten.

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

Dieses Projekt hat keine Referenzscans eines Pakon F-135 oder Kodak HR-500, deshalb ist keines der beiden Ziele an seiner Maschine geprüft. Jedes hat eine eigene Tabelle, gebaut aus dem, was Labore und Nutzer über diese Maschine berichten. Keines geht von den Zahlen von `SP` aus. Die Grauachse ist bei beiden neutral. Pakon-Nutzer berichten von gelben, grünen und blauen Stichen; das deutet auf eine Szenenbalance, die von Bild zu Bild wechselte.

- `F135` (Kodak Pakon F-135, der TLX/PSI-Scanner für Endkunden). Nutzer berichten, er sei weniger gesättigt als ein Noritsu, treffe den Weißabgleich öfter, behalte Zeichnung in Lichtern und Schatten, und manche Scans wirkten flach; ein Nutzer fand seine Schwarzweißausgabe hell. Mittelgrau liegt wie bei einem Endkundenabzug 0,3 Stufen heller. Der lokale Kontrast in den Mitten liegt bei 0,8–1,0, gegenüber 1,2–1,35 bei `SP`. Der Fuß ist angehoben (−6 Stufen bei 0,101, `SP` 0,073), die Lichter laufen lang aus, und das Szenenweiß, das die Invertierung auf linear 0,70 legt, landet bei sRGB 231. Der Sättigungsgewinn ist 0,68–0,74, bei jeder Helligkeit unter `HS`.
- `HR` (Kodak Professional HR 500). Ein Labor beschreibt die Ausgabe als nah am Raw-Scan, der später fertig bearbeitet wird, Nutzer loben den Umgang mit Farbe, und die Schattenzeichnung gilt als rauscharm. Mittelgrau liegt 0,1 Stufen dichter, der lokale Kontrast in den Mitten bei 1,15–1,2. Die Schatten laufen mit 1,2–1,3, dunkler und sauberer als die linearen Schatten von `MAIN` (−6 Stufen bei 0,018), und jede Schattenstufe trennt sich 1,6-mal so weit wie bei `SP`. Die Lichter werden nicht wie bei `SP` gestaucht; sie steigen mit 1,2–1,35, und das Szenenweiß landet bei sRGB 242. Die Sättigung bleibt bei 1,0 und sinkt in den Lichtern auf 0,88; `SP` hebt sie dort an.

Jedes Rendering wurde auf sieben echte Negative gelegt, entwickelt bis zu der Stufe, an der die Ziele ansetzen (zwei Filme, nur zur Diagnose). Je Foto gemittelt unterscheidet sich jedes Paar aus `MAIN` und den vier Zielen um mindestens 2,9 CIEDE2000. Das gemessene Paar `SP`–`HS` liegt bei 4,3. Innerhalb einzelner Fotos sinken `MAIN`–`HR` und `F135`–`HR` bei High-Key-Motiven und Motiven mit vielen Mitteltönen auf 2,0–2,6. Eine Prüfung an der Maschine braucht, was `SP` hatte: dieselben Negative, auf der echten Maschine gescannt.

### `EXPIRED`

Ein Rettungsziel für alten Film. Es entsättigt nicht pauschal und dehnt den Bereich nicht, sondern bleibt bei einer begrenzten Korrektur, die die aktuellen Belege tragen.

### `CS`

`CS` (Custom) fasst 18 Farbstile in drei Gruppen zusammen: Emulsion und Reversal, Dye Transfer und Skip Bleach, Plate Glass und Amber Glass, Ultramarine und Terracotta sowie Celadon, Nacre und Dichroic (11); Wetzlar und Classic sowie Studio und Rochester (4); Slide Show, Cinema und Point & Shoot (3).

Ein Custom-Ziel nutzt die `MAIN`-Invertierung mit Auto-Abgleich und wendet danach die Antwort von custom-3 für Tonwert, Dichte und Chroma an. Scannerprofile werden dafür nicht verwendet. Die CLI nimmt dieselben IDs, zum Beispiel `--target classic`.

## Der Film-Look bei digitaler Quelle

Der Reiter Film umfasst 42 Filme in fünf Kategorien: 7 Diafilme, 16 Farbnegative, 4 ECN-2-Kinofilme, 13 Schwarzweißnegative und 2 Schwarzweiß-Umkehrfilme.

Diese Stufe gilt nur für Quellen vom Typ `Digital Color` und `Digital B&W`. Filmscans überspringen sie vollständig, weil sie die Emulsionsantwort bereits mitbringen.

`Digital Color` führt vier Schritte der Reihe nach aus:

1. Lineare Streuung und rotgewichtete Halation (`DigitalHalation`).
2. 33³-3D-LUT im Positivbereich mit Kanalkurven, Spektralmatrix, Tiefen- und Lichtertönung, Sättigung und MTF-Kantenschärfe laut Datenblatt (`FilmEmulationStage`).
3. Zusätzliches Farb-Preset des Films mit halber Stärke (`DigitalFilmColorPresetStage`).
4. Dichteabhängiges Filmkorn (`DigitalFilmGrain`).

`Digital B&W` durchläuft achromatische Halation, spektrale RGB-zu-Grau-Umwandlung mit der Tonwertkurve der Emulsion (`digitalBWFilm`), MTF-Kantenschärfe und achromatisches dichteabhängiges Korn.

## Entwicklungsregler

| Gruppe | Einträge |
|---|---|
| Tonwert | Belichtung und Kontrast, Dichte, Lichter und Tiefen, Weiß und Schwarz sowie parametrische Kurve und RGB- oder kanalweise Punktkurven |
| Farbe | Temperatur und Tönung, Dynamik und Sättigung, Farbtiefe und HSL mit 8 Farben, Farb-Grading in drei Zonen und Kanalkorrektur sowie Schwarzweißumwandlung und -tonung |
| Detail und Effekte | Schärfe und Klarheit, Filmkorn und Vignette sowie Halation und Rauschminderung |
| Lokale Anpassung | Radiale, lineare, Polygon- und Pinselmasken, Abwedeln und Nachbelichten |
| Transformation / Geometrie | Perspektive und Geraderichten |

Keine Kombination der Basis-Tonregler oder der parametrischen Kurve kehrt Tonwerte um. Die Basis-Tonwerte wenden Kontrast und Dichte, dann Lichter und Tiefen sowie schließlich Weiß und Schwarz in dieser Reihenfolge an, jeweils auf das Ergebnis des vorigen Schritts, und jeder Schritt ist für sich monoton. Die vier Regler der parametrischen Kurve verschieben je einen Knoten bei 10, 35, 65 und 90 % der Bildhelligkeit; eine monotone kubische Kurve verbindet die Knoten. Die Knoten liegen mindestens 0,10 sRGB voneinander und von Schwarz und Weiß entfernt. Ein Regler am Anschlag verschiebt seinen Knoten deshalb bei jedem Bild um mindestens 0,045 sRGB.

Farbmischer, Farb-Grading, Kalibrierung und Punktkurven arbeiten in perzeptiver sRGB-Kodierung auf `[0, 1]` und bewahren dabei Werte unter 0 oder über 1. Vor der Ausgabekodierung bildet `DisplayGamutMap` Farben außerhalb des Gamuts ohne Farbtonverschiebung in die linearen Primärvalenzen des Ziel-Exportfarbraums ab.

Diese Werte werden als schrittweiser Bearbeitungsverlauf gespeichert. GrainMend und die gewöhnliche lokale Anpassung unterscheiden sich in Zweck und Speicherung.

### Automatische Korrekturen

| Regler | Verhalten |
|---|---|
| Automatische Tonwerte | Legt Belichtung und Kontrast, Dichte, Lichter und Tiefen sowie Weiß und Schwarz fest. Die Belichtung bringt die logarithmisch gemittelte Helligkeit der Szene auf einen Szenenschlüssel: Helle Bilder werden dunkler, dunkle heller, und eine hellere Szene erhält einen höheren Schlüssel. Die übrigen Regler werden in der Reihenfolge berechnet, in der die Basis-Tonwerte sie anwenden, jeweils aus den Werten nach den vorigen Schritten. Pixel unterhalb des diffusen Weiß, deren hellster Kanal neu den Vollausschlag erreicht, bleiben auf 0,5 % begrenzt; Spitzlichter und Lichtquellen heller als diffuses Weiß dürfen ausbrennen. Droht eine gesättigte Farbe auszubrennen, gibt zuerst Weiß nach, dann die Belichtung, dann die Aufhellung durch Dichte und Kontrast; die Dichte füllt die Mitteltöne, die eine zurückgenommene Belichtung zu dunkel lässt. Belichtung und gemessener Szenenschlüssel geben dafür höchstens eine Blende nach; bräuchte der Schutz der Farbe mehr, wird der Beschnitt hingenommen. Behält die Farbregler und Kurven des Nutzers. |
| Automatischer Weißabgleich | Schätzt Temperatur und Tönung aus nahezu neutralen Helligkeitsbändern. Verwirft Proben mit beschnittenem RGB-Kanal und mindert die Korrektur, wenn Hinweise auf Neutrales spärlich sind oder nur einen engen Tonwertbereich abdecken. |
| Auto-Tonwertkorrektur | Misst gemeinsame Helligkeitsendpunkte und wendet einen Helligkeitsgewinn auf RGB an, die Kanalverhältnisse bleiben. Bei Negativen gehen die Endpunkte auf die Schwarz- und Diffusweiß-Anker der Invertierung: linear 0,70 bei Farbe und 0,85 bei Schwarzweiß. Das Knie der Belichtungsschulter selbst liegt für beide fest bei linear 0,70, während der Headroom auf den Weißanker der jeweiligen Filmart skaliert. |
| Auto-Farbe | Passt verbleibende Farbstiche an neutrale Kandidaten an. Nutzt Kanalsteigungen nur, wenn eine Anpassung getrennte, ungenutzte Helligkeitsbänder vorhersagt, sonst Gewinne. Schwache Ersatzhinweise erhalten weniger Korrektur. Kanalsteigungen gelten vom dunkelsten Hinweisband bis Weiß; dunklere Töne behalten die Korrektur am unteren Rand der Hinweise. |

Automatische Tonwerte prüft den ersten Vorschlag an einer gerenderten Vorschau. Schlägt es eine weitere Änderung von Belichtung oder Weißpunkt vor, rendert es auch diesen Kandidaten und übernimmt ihn nur, wenn sich eine Bewertung aus Mittelton, Endpunkten, Tonwertbereich und Beschnitt verbessert. Eine weitere Aufhellung hält dieselbe Kanalgrenze ein. Zeigt die Prüfung im pixelweisen Vergleich mit dem neutralen Rendering, dass mehr als 0,5 % solcher Pixel neu beschnitten werden, Scanner-Ziel und Kurven eingeschlossen, senkt Automatische Tonwerte zuerst Weiß und dann die Belichtung und rendert bis zu drei weitere Vorschauen, um die hellste Einstellung innerhalb der Grenze zu finden. Bei der Wahl zwischen zwei Renderings gewinnt das mit weniger Beschnitt, bevor die Bewertung verglichen wird. Das ist eine begrenzte Korrektur, keine Suche nach einem einzigen idealen Rendering. Ein wiederholter Befehl weist Einstellungen zu, statt sie anzuhäufen, und ein Zurücksetzen behält die Farbregler des Nutzers.

Die Analyse nutzt flächengewichtete Mittelwerte in linearem RGB mit begrenzter langer Kante. Tonwert und Weißabgleich nutzen eine sRGB-Vorschau, Beschnitt bedeutet also Beschnitt der Vorschaukanäle, nicht Sensorsättigung. Diese Schätzungen können nicht jede Motivfarbe von einem Lichtstich unterscheiden und belegen keine gemessene Farbgenauigkeit des Films. Der Auto-Abgleich von MAIN/CS und seine Vibrance für gedämpfte Szenen gehören zur Invertierungsstufe.

## Farbmanagement

Trägt die Eingabe ein gültiges ICC, wird dieser Farbraum gelesen. Unter Windows werden Eingaben mit eingebettetem Wide-Gamut-ICC über ein internes Rec.2020-Zwischenprofil umgerechnet, und monochrome Scans mit Gray-ICC werden ebenfalls unterstützt. Die interne Rechnung läuft im festen linearen Arbeitsraum, und der Wechsel in einen Ausgaberaum geschieht bei Anzeige, Softproof und Export.

Wichtige unterstützte Ausgaben:

- sRGB
- Display P3
- Adobe RGB
- Vom Nutzer gewähltes RGB-ICC: Der Export für die Druckerausgabe verlangt ein RGB-Profil der ICC-Druckerklasse `prtr`, während der Softproof ausgabefähige RGB-Profile (`prtr`, `mntr` oder `spac`) akzeptiert

Name, Bytezahl und SHA-256 des Druckerprofils werden beim Start des Exports festgelegt. Ändert sich die Datei während des Renderns, bricht der Lauf ab. Wenn unter Windows das klassische ICM bei einem LUT-Drucker-ICC Relative Colorimetric ablehnt, fällt die Umrechnung auf Perceptual oder WCS-v4-Pfade zurück.

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
2. Synthetische Bilder: bekannte Eingabe und Ausgabe, Beschnitt, Ausrichtung und Farbraum
3. Synthetisches IT8: die mathematische Hin- und Rückrechnung über 264 Felder
4. Echte Aufnahmestatistik: die `realOnly`-Profile
5. REAL/TARGET-Paare: eine Geräte-Qualitätsprüfung mit getrenntem Validierungsmaterial
6. Echte Hardware: ein tatsächlicher Scanner, Film, Bildschirm und Abzug

Ein gutes synthetisches IT8-Ergebnis belegt keine absolute Genauigkeit bei echten Negativen. Die Beurteilung der Qualität von Scannerprofilen folgt [Qualitätsprüfung der Scannerprofile](../reference/PROFILE_QUALITY_GATE.md). Ergänzend gilt [IT8-Farbprüfung](../reference/IT8_COLOR_VALIDATION.md).

## Wo der Code liegt

- `negaflow-mac/Sources/Chromabase/Engine/`
- `negaflow-mac/Sources/Chromabase/Film/`
- `negaflow-mac/Sources/Chromabase/Digital/` (digitale Film-Looks)
- `negaflow-mac/Sources/Chromabase/Develop/`
- `negaflow-mac/Sources/Chromabase/Adjustments/`
- `negaflow-mac/Sources/Chromabase/Profiles/`
- `negaflow-mac/Sources/Chromabase/Imaging/`
- `negaflow-mac/Sources/Chromabase/Export/`
- `negaflow-windows/src/Native/` (entsprechende Windows-Engine in C++/Direct3D 11)

Die aktuelle Produktversion ist `1.2.7`. Änderungen an Bearbeitungsverlauf und Profilschemata müssen auch in späteren Versionen eine Prüfung durchlaufen.
