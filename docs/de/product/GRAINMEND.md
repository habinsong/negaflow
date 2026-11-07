# GrainMend

[Dokumentationsstart](../README.md)

GrainMend repariert Staub, Pinholes, Kratzer und Emulsionsschäden am Film. Nichts wird ins Original eingebrannt. Das Ergebnis bleibt als geordneter Bearbeitungsverlauf erhalten.

| Werkzeug | Was es ansieht | Wie es repariert |
|---|---|---|
| Automatisch | Das ganze Foto | Vorsichtig, nur Defekte, bei denen es sich sicher ist |
| Geführt | Ein von Ihnen gewählter Bereich | Sieht genau hin, bis zu kleinen Flecken und schwachen Defekten |
| Pinsel | Die Stelle, die Sie übermalen | Überträgt umgebende Struktur und Textur |
| Klonstempel | Ein von Ihnen gewählter Quellpunkt | Kopiert echte Quellpixel mit festem Versatz |
| IR | Der Infrarotkanal des Scanners | IR findet die Stelle, RGB baut die Pixel neu auf |

Die Entwicklungsansicht bietet Automatisch, Geführt, Pinsel und Klonstempel. IR lässt sich beim Scannen einschalten, wenn das Plug-in die Fähigkeit meldet, und nach dem Scan kommt sein Ergebnis in dieselbe GrainMend-Ebenenliste.

> [!CAUTION]
> GrainMend RGB arbeitet anders als Hardware-IR-Reinigung. GrainMend IR ist weder eine Implementierung noch ein Kompatibilitätsmodus von Digital ICE, iSRD oder SRDx.

## Das Schwierige

Filmdefekte und die Struktur des Fotos liegen in denselben Pixeln.

- Staub zeigt sich als kleine, unregelmäßige helle oder dunkle Flecken.
- Ein Pinhole kann wie ein einzelner starker Punkt aussehen.
- Kratzer sind lang und dünn, ebenso wie Drähte, Fensterrahmen und Schriftzüge.
- Emulsionsschäden verändern Farbe und Textur zugleich.
- Bei hoher Auflösung ist das Filmkorn so groß wie ein kleiner Defekt.

Hohe Frequenzen im Ganzen zu löschen nimmt mit dem Staub auch Korn und Kanten mit. GrainMend teilt die Arbeit in Erkennung, Klassifizierung, Reparatur und Speicherung.

## Arbeitsablauf

Die Erkennungsmaske und das reparierte Ergebnis werden getrennt gehalten. Dadurch lässt sich die Maske prüfen, nur ein Teil der Defekte anwenden oder die Reparatur neu aufbauen. Die Schritte:

1. Eingabebild, Prüfbereich und Größe.
2. Defektkandidaten, dann Maskenbereinigung.
3. Klassifizierung der Defekte.
4. Strukturprüfung: Ist es Struktur im Foto, wird nichts angewendet.
5. Eine Quellkachel in der Nähe suchen.
6. Helligkeit, Textur und Richtung angleichen.
7. Die Grenze überblenden.
8. Zum Bearbeitungsverlauf hinzufügen.

## Werkzeuge

### Automatisch

Über das ganze Foto findet es nur Defekte, bei denen es sich sicher ist. Einen kleinen Defekt zu übersehen ist besser, als eine große Struktur fälschlich zu löschen. Es schleicht sich nie in die Standardentwicklung, Sie müssen es ausführen, damit etwas hinzukommt.

### Geführt

Sie wählen ein Rechteck, und nur dieser Bereich samt Umgebung wird analysiert. Da Sie auf den Defekt bereits gezeigt haben, geht es kleinen Flecken, schwachen Defekten und dichten Ansammlungen aggressiver nach als Automatisch.

Es liest weiter, als das Ergebnis reicht, deshalb werden die umgebenden Pixel für die Reparatur am Rand des Bereichs nicht abgeschnitten. Der aktuelle maximale Kontextradius beträgt 264 Pixel.

### Pinsel

Sie übermalen die zu reparierende Stelle selbst. Das Übermalte wird nicht mit einer Farbe abgedeckt. Es findet nahe der Maske eine passende Quellkachel und überträgt Struktur und Textur. Passt keine Kachel, kann es begrenzt auf den Erkennungspfad zurückfallen.

### Klonstempel

Ein Klick mit `⌥` wählt den Quellpunkt, dann zeichnen Sie auf das Ziel. Es nutzt keine automatische Erkennung, sondern hält den Versatz zwischen den beiden Punkten und kopiert die echten Pixel.

Der Bearbeitungsverlauf hält Durchmesser, Härte, Koordinaten und Versatz fest und wirkt auch nach einer Drehung, Spiegelung oder einem Beschnitt auf dieselben Originalkoordinaten. Versätze rasten auf ganze Pixel ein, und nichts außerhalb des Bildes wird angewendet.

### IR

Wird nur genutzt, wenn das Plug-in einen echten IR-Kanal liefert, dessen Größe und Bereich zum RGB passen. IR ist das Material, das den Defekt lokalisiert. Die endgültigen Pixel kommen vom selben Reparierer wie bei RGB.

## Defekte in RGB finden

### Unterschied zur Umgebung

Die Helligkeit unterscheidet sich von Foto zu Foto, einen einzigen globalen Schwellwert gibt es also nicht. Der Unterschied zur umgebenden Helligkeit, die lokale Varianz und die Richtung ergeben Kandidaten für hellen Staub und dunkle Defekte.

### Maskenbereinigung

Isoliertes Rauschen wird verworfen, unterbrochene Defekte werden verbunden, und Pixel, die sich in einer der 8 Richtungen berühren, werden zu einem Fleck. Ein großer Bereich kann in Kacheln geteilt werden, doch ein Fleck über einer Grenze wird in den Koordinaten des ganzen Bildes wieder zusammengeführt.

### Auflösungsunterschiede

Dasselbe Staubkorn ist bei 1200 dpi und bei 7200 dpi eine andere Pixelzahl. Sind die Auflösungsangaben verlässlich, folgen die Grenzen der realen Größe. Ohne sie wird das Scannermodell nicht geraten, und es gilt eine vorsichtige Pixelregel.

### Klassifizierung

Jeder Fleck wird vermessen nach:

- Fläche und Umgebungsrechteck
- Verhältnis von langer zu kurzer Achse
- Waagerechter, senkrechter und diagonaler Richtung
- Linearität, Dichte und Kontrast zur Umgebung
- Ob er sich in eine nahe Kante fortsetzt
- Seiner Beziehung zu anderen Flecken

Das Ergebnis wird in Staub, Pinhole, Kratzer nach Richtung, Emulsionsschäden und Mikroflecken aufgeteilt, jeweils mit einer Sicherheit.

### Linien, die zum Foto gehören, nicht löschen

Drähte, Geländer, Gebäudeecken, Fensterrahmen und Schriftzüge dürfen nicht als Kratzer gelesen werden. Parallele Linien, Raster, die Fortsetzung von Kanten und an die Szenenstruktur gebundene Linien erhalten eine eigene Prüfung. Automatisch weist Fehlerkennungen strenger zurück, Geführt berücksichtigt zusätzlich Ihre Ortswahl.

## Reparatur

1. Nahe am Defekt eine Quellkachel suchen, die die Maske nicht überlappt und deren Struktur passt.
2. Den niederfrequenten Helligkeits- und Farbunterschied zwischen Kachel und Ziel angleichen.
3. Die hochfrequente Textur der Kachel behalten, damit das Filmkorn weiterläuft.
4. Bei einem langen Kratzer zuerst die Richtung ansehen, die von beiden Enden weiterläuft.
5. Am Maskenrand das Original und die reparierte Kachel weich überblenden.

Die Stärke ist das Mischverhältnis zwischen fertiger Kachel und Original.

Manchmal kann eine automatische Reparatur nicht wissen, was darunter lag. Gibt es keine brauchbare umgebende Textur oder verdeckte der Defekt eine ganze wichtige Struktur, braucht es den Pinsel, den Klonstempel oder gesonderte Feinarbeit.

## IR-Verarbeitung

### Eingangsbedingungen

- Das Plug-in meldet die IR-Fähigkeit ausdrücklich.
- RGB und IR gehören zur selben Scansitzung.
- Beide Bilder haben dieselbe Pixelgröße und denselben erwarteten Bereich.
- Die Dateien sind lesbar und bestehen die Prüfung der Original-ID.

Auch wenn bekannt ist, dass ein Modell IR hat, wird es auf dem Bildschirm oder in einer Anfrage nicht verwendet, solange das Plug-in es nicht meldet.

### Ausrichtung

Optik und Sensorauslesung können RGB und IR um einige Pixel versetzt lassen. Eine weite, dann eine enge Suche legt den Versatz fest. Die Sicherheit des Maximums und ob es am Rand des Suchbereichs landete, werden beide festgehalten.

Geringe Sicherheit oder ein bester Punkt am Ende der Suche gilt nicht als Erfolg.

### Szenenmuster abziehen

Filmfarbstoff und Dichte können im IR durchscheinen. Die logarithmische Helligkeit des Rotkanals wird in 64 Klassen geteilt, und in jeder Klasse wird der Mittelwert gebildet, nachdem die obersten und untersten 10 % der IR-Werte verworfen wurden. Leere Klassen werden aus den Nachbarn interpoliert und mit einem kurzen symmetrischen Kern geglättet. Das Abziehen dieser nichtparametrischen Kurve verringert das Szenenmuster, und spärlicher dunkler Staub bleibt aus der Klassenstatistik heraus.

Der Rest wird in Kontrast relativ zum lokalen Mittel umgerechnet. Damit ein großer Defekt den umgebenden Rauschboden nicht anhebt, wird die Rauscheingabe vor der Berechnung des adaptiven Schwellwerts auf den minimalen Erkennungskontrast beschnitten. Zusammenhängende dunkle Bereiche am Halter und am Filmrand werden aus der Maske entfernt.

### Sicherheitsbedingungen

- Eine ungewöhnlich breite Maske wird nicht angewendet.
- Eine nicht bestätigte Ausrichtung wird nicht angewendet.
- Auf Silber-Schwarzweiß wird nicht automatisch angewendet.
- Farbpositive und Spezialemulsionen gelten ohne Messung nicht als sicher.

Auch kommerzielle IR-Werkzeuge setzen bei gewöhnlichem Schwarzweiß und bei Kodachrome eigene Grenzen:

- [SilverFast: iSRD dust and scratch removal](https://www.silverfast.com/about-silverfast-why-scanning-basics-of-scanning/why-silverfast/silverfast-feature-highlights/isrd-dust-scratches-removal-eliminate-defects-with-infrared-channel/)

GrainMend IR ist weder eine Kopie noch ein Kompatibilitätsmodus dieser kommerziellen Werkzeuge. Die IR-Grenzen je Film und die Bedingungen, unter denen die Ausrichtung scheitert, stehen in [Filme, die GrainMend IR meidet](../reference/INFRARED_LIMITS.md).

## Bearbeitungsverlauf und Speicherung

Automatisch, Geführt, Pinsel, Klonstempel und IR teilen sich eine geordnete Bearbeitungsliste.

Was jeder Eintrag trägt:

- ID und Art
- Reihenfolge der Anwendung
- Ob er aktiv ist, und seine Stärke
- Bereich, Maske, Versatz der Klonquelle
- Defektklassifizierung und Diagnosewerte
- Ursprüngliches Bild und Bearbeitungsversion
- Die reparierte Kachel oder die Werte, um sie neu aufzubauen

Eine frühere Reparatur verändert die Eingabe der späteren, deshalb gehört auch die Reihenfolge der Liste zum Bearbeitungsverlauf.

Das Original wird nicht verändert. Der GrainMend-Verlauf liegt in einer von der App verwalteten Sidecar-Datei. SHA-256 des Originals, Bearbeitungsversion und ein Verlaufs-Fingerabdruck binden die Eingabe. Fehlt die Sidecar-Datei oder ist sie beschädigt, wird der Cache nicht als Original behandelt.

Der GrainMend-Cache ist eine abgeleitete Datei für schnelle Anzeige und erneutes Rendern. Fehlt er oder besteht er seine Prüfung nicht, wird er aus dem Original und dem Bearbeitungsverlauf neu aufgebaut. Lässt sich das für einen Export nötige Ergebnis nicht erzeugen, scheitert der Export, statt das Original einzusetzen.

## Leistung

- Eine kleine Bearbeitung berechnet nur den Defekt und seinen Kontext neu.
- Ein großer Bereich wird in überlappende Kacheln mit Rand für die Grenze geteilt.
- Ergebnisse werden nur aus den nicht überlappenden Zentren der Kacheln gesammelt.
- Höchstens 4 Kacheln werden gleichzeitig verarbeitet.
- `CleanedRawCanvas` kopiert nur das Rechteck, das sich geändert hat.
- Kopien für Rückgängig teilen sich den Speicher, bis sich wirklich etwas ändert.
- Unter Speicherdruck werden wiederherstellbare Bilder und der Kachel-Cache verworfen.

Die tatsächlichen Zeiten hängen von Auflösung, Defektzahl, Bereichsgröße und Mac ab.

Gemessen am 2026-07-25 mit einem Release-Build, Mac14,3, arm64, 24 GiB Speicher, macOS 26.5:

| Pfad | Eingabe | Ergebnis |
|---|---|---:|
| Geführte Erkennung | 1600×1600, 25 Staubkörner | 0,35 s, 25 erkannt |
| Teilweise ROI-Erkennung | 1600×1600 | 0,38 s |
| Geführter Dichtetest | 1280×960, 8 Bilder × 3 Läufe | Median 0,423 s, p95 0,488 s, Max. 0,526 s |
| IR-Erkennung | 6000×4000, 24 MP | 1,042 s, Spitzenzuwachs beim Speicher 249,2 MiB |

In 24 Läufen des Dichtetests lag die niedrigste Maskenabdeckung an Defektstellen bei 99,80 % und der höchste mittlere Restfehler bei 2,70/255. Das sind Regressionsmessungen an synthetischer Eingabe. Sie versprechen keine Verarbeitungszeiten auf einem anderen Mac oder bei echtem Film.

## Benchmark

`defect-bench` kann diese Dateien und Werte erzeugen:

- Vorher, nachher, Differenz, Maske
- 100-%-Ausschnitte
- Zahl der Erkennungen und Sicherheit
- Verarbeitungszeit
- PSNR und absoluter Fehler, wenn Referenzbilder vorliegen

```bash
swift run -c release negaflow defect-bench <input-dir> \
  --reference-dir <reference-dir> \
  --out <report-dir>
```

Die RGB-Regression nutzt die 44 Paare aus beschädigtem und von Experten restauriertem Bild aus FILM-R v2:

- Datensatz: Authentically damaged & manually restored film scans (FILM-R v2)
- Autorin: Daniela Ivanova
- DOI: <https://doi.org/10.6084/m9.figshare.21803304.v2>
- Lizenz: CC BY 4.0 (<https://creativecommons.org/licenses/by/4.0/>)
- Paare: 44
- Gesamtgröße: 437,570,872 bytes

Der automatische Pfad wendet Empfindlichkeit 0,7 und eine Sicherheitslinie gegen Übererkennung an. Bei den 44 FILM-R-Paaren wurden 34 Bilder besser und 6 schlechter. Die mittlere PSNR-Änderung beträgt +0,466 dB, der schlechteste Fall −1,338 dB, und gewichtete verschlechterte Pixel machen 0,017 % aus.

Trifft Automatisch auf eine hohe Dichte von Kandidaten, hört es auf anzuwenden und verweist Sie auf Geführt. Diese Sicherheitslinie gilt nicht für Geführt, wo Sie den Bereich festlegen, und nicht für Pinsel, Klonstempel oder IR. 6 Bilder haben noch einen niedrigeren PSNR als die Expertenrestaurierung. All das belegt weder, dass sich jedes Foto verbessert, noch dass RGB und IR gleichwertig sind, noch etwas über die IR-Qualität an einem echten Scanner.

## Testabdeckung

- Konnektivität in 8 Richtungen und Masken
- Morphologische Operationen
- Erkennung von Staub, Kratzern und Mikroflecken
- Linien und Raster als Fehlerkennung zurückweisen
- Kachelgrenzen in einem großen Bereich
- Kratzerreparatur nach Richtung
- Angleichen von umgebender Textur und Helligkeit
- Pinselmasken
- Versatz, Härte und Kachelzusammensetzung beim Klonstempel
- IR-Ausrichtung, Anker, Flecken und Speichergrenzen
- Anwenden auf der Originalstufe und Rendern des Bearbeitungsverlaufs der App
- Wiederholtes Hinzufügen und Rückgängig
- Besitz des Bildes beim Wechsel durch die Oberfläche

Manche Leistungstests laufen nur, wenn eine Umgebungsvariable gesetzt ist. Eine vorhandene Testdatei besagt nicht, dass sie in jeder Umgebung lief.

## Namen und Marken

`GrainMend` ist negaflows eigener Funktionsname.

- `Digital ICE` kann eine Marke von Eastman Kodak Company oder eines verbundenen Rechteinhabers sein.
- `iSRD`, `SRDx` und `SilverFast` sind Marken von LaserSoft Imaging.
- Diese Namen dienen nur dem technischen Vergleich und der Produktbezeichnung.
- GrainMend beansprucht keine Verbindung, Kompatibilität oder Gleichwertigkeit mit fremder Technik.

## Wo der Code liegt

- `Sources/Chromabase/DefectRemoval/`
- `Sources/negaflowApp/Features/Defects/`
- `Sources/negaflowApp/Features/Develop/Inspector/Tools/DefectControlsSection.swift`
- `Sources/negaflowCLI/Commands/CLI+DefectBenchCommand.swift`
- `Tests/ChromabaseTests/Defect*.swift`
- `Tests/negaflowAppTests/Defect*.swift`
- `Config/defect-corpus-film-r-v2.json`
- `scripts/defect-corpus/`
