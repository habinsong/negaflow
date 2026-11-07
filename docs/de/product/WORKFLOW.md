# Von der Mediathek zum Abzug

[Dokumentationsstart](../README.md)

Diese Anleitung behandelt Import, Ordnerentwicklung, Übertragung von Einstellungen, Scanner-Miniaturen und Abzugsausgabe. Ein Ordner der Mediathek folgt dem physischen Elternordner jeder Quelle.

> [!IMPORTANT]
> Quelldateien bleiben unverändert, solange Sie ein Foto nicht ausdrücklich in einen anderen Ordner verschieben. Einen Ordner aus der Mediathek zu entfernen und eine Datei im Finder zu löschen sind getrennte Vorgänge.

## Import

Der Import zeigt unter den Importbedienelementen einen Fortschrittsbalken, eine Prozentzahl, die Zahl der fertigen und die Gesamtzahl der Dateien. Metadaten werden außerhalb des Hauptthreads gelesen, dann werden die neuen Bilder gemeinsam registriert, sodass ein großer Ordner den Mediatheksindex nicht immer wieder neu aufbaut.

Die automatische Entwicklung importierter Fotos ist **standardmäßig aus**. Ein Import läuft so ab:

1. Die Quelle wird registriert.
2. Ihre Originalminiatur und der Ordner erscheinen zuerst.
3. Die Entwicklung beginnt, wenn Sie einen Prozess und ein Ziel auf den Ordner anwenden oder die Ansicht Entwickeln öffnen.

Um jeden Import automatisch zu entwickeln, schalten Sie **Einstellungen → Arbeitsablauf → Neue Importe automatisch entwickeln** ein. Die Wahl bleibt über Neustarts erhalten. Sie gilt nur für die Bilder, die dieser Import registriert hat, und ersetzt nie einen vorhandenen entwickelten Zustand. Entwickelte Fotos werden nur durch ein ausdrückliches **Anwenden** auf den Ordner oder ein Einfügen von Einstellungen neu verarbeitet.

Scanner-Aufnahmen sind anders: Filmart, Prozess und Ziel werden beim Scannen gewählt, deshalb beginnt die Entwicklung, sobald das Scanergebnis veröffentlicht ist. Die Filmstreifen von Entwickeln und Abzug zeigen für Farbnegativ-, Dia-, Schwarzweißnegativ- und Schwarzweißpositiv-Quellen eine entwickelte Miniatur. Die Mediathek behält die Quellminiatur zur Prüfung der Quelle.

## Ordnerliste

- Eingeklappter und ausgeklappter Zustand bleiben erhalten. Einen Ordner anzulegen oder die App neu zu öffnen klappt die anderen Ordner nicht auf.
- Jede Ordnerzeile hat dasselbe Bedienelement `×`. Es entfernt diesen Ordner und seine Fotos **nur aus der Mediathek**. Die Quelldateien bleiben im Finder.
- Die Fotoliste eines Ordners in Entwickeln hat einen eigenen Scrollbereich mit begrenzter Höhe, eine lange Liste oder ein kleines Fenster schiebt den Rest der Seitenleiste daher nicht weg.

### Fotos in einen anderen Ordner verschieben

Ziehen Sie ein Foto oder eine Auswahl auf die Zeile eines anderen Ordners, um die physischen Dateien zu verschieben und den Katalog zugleich zu aktualisieren. Dieselbe Regel gilt für importierte Ordner, von der App angelegte Ordner und Ordner mit Scanner-Aufnahmen.

Ein vorhandener Name am Ziel wird nie überschrieben. Existiert `frame.tiff`, versucht negaflow `frame 2.tiff`, dann `frame 3.tiff` und so weiter. Eine IR-Begleitdatei einer Scannerquelle wird in derselben Transaktion verschoben.

### Änderungen im Finder

negaflow überwacht die registrierten physischen Quellordner. Nach einer kurzen Entprellung prüft es nur den geänderten Ordner erneut, wenn es Folgendes bemerkt:

- Das Verschieben oder Umbenennen einer Quelldatei
- Das Verschieben oder Umbenennen eines registrierten Ordners
- Ein neues Bild direkt in einem registrierten Ordner

Findet das dauerhafte Lesezeichen der Quelle den neuen Ort, wird das vorhandene Bild neu verknüpft. Ein verschobener Ordner behält seine Ordner-ID und sein Hinzufügedatum. Eine neu hinzugekommene Datei wird importiert, ohne Duplikate bereits bekannter Dateien zu erzeugen.

Das ist eine ereignisgesteuerte Ordnerüberwachung, kein regelmäßiger Durchlauf der ganzen Mediathek. Bilder mit demselben physischen Elternordner teilen sich eine Überwachung, und nur Ordner, die eine Änderung melden, werden geprüft.

## Entwicklung nach Ordner

Wählen Sie neben dem Ordnertitel einen Prozess und ein Ziel und wählen Sie dann **Anwenden**. Einen eigenen Ein-/Ausschalter gibt es nicht.

Anwenden rendert jedes Foto im Ordner neu, auch zuvor entwickelte. Der neue Prozess und das neue Ziel werden verwendet, während andere Nutzeranpassungen wie Belichtung und Kontrast bleiben. Rendert ein Bild bereits, wartet der Ordnerauftrag auf das Ende dieses Renderns.

Neben Anwenden erscheinen ein Fortschrittsbalken, eine Prozentzahl, die Zahl der fertigen und die Gesamtzahl der Fotos. Große Stapel halten nur so viele Arbeiter wie Render-Plätze vor, statt für jedes Foto eine Aufgabe zu starten.

## Geraderichten und Transformieren

Öffnen Sie rechts in Entwickeln Geometrie → Beschnitt. Halten Sie ⌘ (unter Windows Strg), ziehen Sie entlang einer Kante, die waagerecht sein soll, und lassen Sie los: Das Foto dreht sich, bis die Linie waagerecht steht. Eine eher senkrecht gezogene Linie wird senkrecht ausgerichtet. Solange Sie ⌥ (unter Windows Alt) halten, liegt ein feines Raster über dem Beschnitt. Beide Tasten lassen sich unter Einstellungen → Kurzbefehle ändern, dürfen aber nicht gleich sein. Auf dem Mac steht ⌃ für die Linie nicht zur Wahl, weil ⌃-Klick dort ein Rechtsklick ist.

Der Bereich Transformieren liegt zwischen Kalibrierung und Details & Effekte. Aus lässt das Foto unverändert. Auto, Waagerecht, Vertikal und Voll suchen einmal nach geraden Linien im Foto und korrigieren sie. Waagerecht dreht nur, Vertikal richtet auch stürzende Linien auf, Voll korrigiert die vertikale und horizontale Perspektive. Auto macht dasselbe wie Voll, hält große Korrekturen aber zurück. Geführt folgt 2 bis 4 Hilfslinien, die Sie auf das Foto ziehen.

Die Regler Vertikal, Horizontal, Drehen, Seitenverhältnis, Skalieren, X-Versatz und Y-Versatz kommen zu dem hinzu, was der Modus gefunden hat. Ein Doppelklick setzt einen Regler zurück. Zuschnitt begrenzen schneidet das Ergebnis auf das größte Rechteck ohne leere Ecken zu. Ist es aus, sind die leeren Ecken am Bildschirm und in exportierten Dateien weiß. Histogramm, Clipping-Warnung, Auto-Ton und Auto-Weißabgleich zählen sie nicht zum Foto. Die Korrektur bleibt bei 90°-Drehungen und Spiegelungen erhalten, und Alle Anpassungen zurücksetzen löscht sie zusammen mit Beschnitt und Geraderichten.

## Vorgaben und Kopieren/Einfügen

Die Entwicklungseinstellungen haben sieben getrennt wählbare Gruppen.

| Gruppe | Werte |
|---|---|
| Eingangsgamma | Deutung der Übertragungskennlinie der Quelle |
| Basisskalierung | Skalierung der Filmbasis |
| Basis | Filmart und Prozess, Ziel, Scannerprofil, Filmbasis, Kanalbereichskalibrierung, Auto-Abgleich, Auto-Tonwertkorrektur und neutraler Abgleich |
| Tonwert | Belichtung, Kontrast, Dichte, Lichter, Tiefen, Weiß, Schwarz und Tonwertkurven |
| Farbe | Temperatur, Tönung, Farbtiefe, Dynamik, Sättigung, Mixer, Grading, Kalibrierung, Schwarzweißtonung und Filmemulation |
| Detail | Korn, Schärfe, Halation, Klarheit, Vignette, Rauschminderung, GrainMend-Stärke und lokale Anpassungen |
| Geometrie | Beschnitt, Drehung, horizontale und vertikale Spiegelung, Geraderichten, Beschnittverhältnis und Transformieren |

Ein vollständiges Einfügen oder eine Nutzervorgabe ersetzt die Entwicklungseinstellungen des Ziels. Ein eingegrenztes Einfügen ersetzt die wirksamen Werte der gewählten Gruppen und behält die anderen. Wird nur ein Teil eines Looks eingefügt, werden dessen Beiträge zu Tonwert, Farbe und Textur in die Werte eingerechnet und der Verweis auf den Look gelöscht, damit ein alter Look nicht ein zweites Mal hinzukommt. Wiederholtes Einfügen derselben Einstellungen ergibt denselben Zustand. Menüs, Kurzbefehle und das Feld nutzen denselben Einfügebereich.

Einfügen und Nutzervorgaben gelten für alle ausgewählten Fotos. Ein Rückgängig oder Wiederholen deckt die ganze Auswahl ab, und Windows prüft jedes Ziel, bevor es eines ändert. Miniaturen und die aktive Vorschau werden aus dem neuen Rezept aktualisiert. Originaldateien, Bewertungen und quellgebundene Defektbearbeitungen werden nicht kopiert.

Nutzervorgaben speichern den vollständigen Entwicklungszustand und die Geometrie. Ältere Vorgaben oder Einfügebereiche ohne Geometrie enthalten sie aus Kompatibilitätsgründen. Ein leerer Name erhält den ersten freien nummerierten Namen, und Speichern überschreibt nie eine vorhandene Vorgabe, nur weil der Name übereinstimmt.

## Ohne Scanner-Plug-in

Ist beim Start kein Scanner-Plug-in installiert, zeigt die gemeinsame Seitenleiste von Mediathek und Entwickeln nicht automatisch die Erklärung zum fehlenden Plug-in, das Bedienelement zum erneuten Suchen oder den Simulatorblock. Der Bildimport bleibt verfügbar.

Erneutes Suchen nach Scannern und die Simulatorunterstützung sind weiterhin vorhanden. Sie bleiben über den Scanner-Einstieg und die Einstellungen erreichbar, und die vorhandene Scanneroberfläche erscheint, sobald ein Plug-in installiert oder der Simulator ausdrücklich aktiviert ist.

## Abzugslayouts und Ausgabezahlen

Der Abzug hat acht Layouts: Einzelbild, Kontaktbogen, Bildpaket, eigenes Paket, Cyanotypie, Glasplatte, Silbergelatine und Wasserzeichen. Die fünf Einzelbild-Layouts zeigen je ausgewähltem Foto eine fertige Seite in senkrechter Folge. Das Wasserzeichen ist ein eigenes Layout, die anderen behalten ihre bisherigen Bedienelemente.

Export und Schnellexport zählen fertige Seiten. Beispielsweise werden aus 39 Fotos in einem Kontaktbogen 6 × 7 eine zusammengesetzte Datei, aus einem vierfachen Bildpaket 10 Seiten, aus dem Standard-Paket eine Seite und aus den fünf Einzelbild-Layouts 39 Dateien in einem begrenzten Stapel.

Die Paketvorschau nutzt eine vorhandene Miniatur, ein entwickeltes Bild oder eine Raw-Vorschau wieder und erzeugt nur dann eine kleine schnelle Vorschau, wenn es keine gibt. Der endgültige Export berechnet jede Platzierung aus den Quellmetadaten, entwickelt nur die Pixel, die diese Platzierung braucht, bereitet zwei bis vier Quellen gleichzeitig vor und hält den Core-Image-Graphen bis zum Rendern der letzten Seite verbunden. Ein gemeinsamer Render-Kontext und ein Budget von 512 MiB Quellraster pro Seite verhindern, dass eine Seite zu einer unbegrenzten Menge von Zwischenbildern in voller Auflösung anwächst.

## Abzug-Wasserzeichen

Wählen Sie im Menü der Layouttypen Wasserzeichen, nach Silbergelatine. Es fügt unter jedem Foto einen Rand hinzu, ohne es zu beschneiden, und Sie können oben einen gleich hohen Rand ergänzen. Das Fotopapierformat folgt dem Foto samt Rändern.

Der untere Rand zeigt links die Kamera mit dem Objektiv darunter. Rechts zeigt er ein Logo, dann Brennweite, Blende, Belichtungszeit und ISO, darunter das Datum. Schalten Sie Logo ein, um eines hinzuzufügen. Ist keine Datei gewählt, wird das negaflow-Logo verwendet. negaflow liefert keine Herstellerlogos mit, wählen Sie also eine eigene JPEG-, PNG- oder andere Bilddatei. Einstellungen und Vorlagen speichern nur den Dateipfad. Beim Zeichnen wird die Datei geprüft und das zwischengespeicherte Logo wiederverwendet, solange Größe und Änderungszeit gleich bleiben. Wurde die Datei verschoben oder gelöscht, entfällt nur das Logo, und der Statuspunkt unten sowie der Diagnosebericht halten es fest. Leere Felder für Kamera, Objektiv, Belichtung und Datum bleiben leer, und nur eingegebener Text wird gezeichnet. Ist der Text lang oder der Rand schmal, etwa bei einem Hochformat, werden alle Elemente im Rand um denselben Faktor verkleinert, der Text ragt also nie über das Foto hinaus und wird nicht abgeschnitten.

Der Rand kann weiß, schwarz oder eine Unschärfe des Fotos sein. Auf Weiß ist der Text schwarz mit grauen zweiten Zeilen. Auf Schwarz ist aller Text weiß. Bei Unschärfe wählen Sie Schwarz oder Weiß für den Text und für das Histogramm. Das Histogramm wird als Punktsäulen gezeichnet. Die Regeln für die Positionen von Name und Histogramm stehen in [Abzugslayouts und C-Print-Vorschau](../reference/C_PRINT.md). Unschärfe und Histogramm nutzen eine gültige Filmstreifen-Miniatur wieder, wenn eine verfügbar ist, sonst ein verkleinertes Fotobild. Vorlagen speichern die Papierfarbe und alle Wasserzeichen-Einstellungen, auch Text und Logopfad.

## Abzugsprofile

Die ICC-Bedienelemente im Abzug haben unterschiedliche Aufgaben.

| Einstellung | Bildschirmvorschau | Abzugsexport | Entwicklungsvorschau |
|---|---|---|---|
| Druckerausgabeprofil | Zeigt das Abzugsergebnis | Auf die fertige Seite angewendet | Nie angewendet |
| C-Print-Proof-Profil | Softproof des Labor- und Papierprozesses | Nicht in die Auslieferungsdatei eingebrannt | Nie angewendet |
| Allgemeiner Softproof | Im eingestellten Anzeigebereich verwendet | Nur Anzeigehilfe | Folgt der eigenen Einstellung |

Ein Druckerausgabeprofil wird nicht auf eine Quelle angewendet, bevor diese Quelle dupliziert wird. Kontaktbogen, Bildpaket oder eigenes Paket werden zuerst zusammengesetzt, dann wird das Profil einmal auf die ganze Seite angewendet. Wiederholte Platzierungen einer Quelle und Layouts mit gemischten Quellen erhalten daher dieselbe Ausgabeumrechnung.

Das C-Print-Proof-Profil ist die vom Labor gelieferte Prozessvorschau. Es wird nie stillschweigend als Ausgabeprofil eingesetzt. Anforderungen an Profile und die Genauigkeitsgrenze stehen in [Abzugslayouts und C-Print-Vorschau](../reference/C_PRINT.md).

## DNG-Export

DNG schreibt das entwickelte Bild als unkomprimierte lineare 16-Bit-RGB-Datei (`PhotometricInterpretation = LinearRaw`) im gewählten Ausgabefarbraum: sRGB, Display P3 oder Adobe RGB. Tonwert und Farbe sind bereits eingebrannt, andere Apps lesen die Datei daher als ausgabebezogen. Die Datei trägt Urheberrecht, Scanner, Software, Datum und Filmnotizen nach denselben Metadatenregeln wie TIFF. EXIF, IPTC und GPS der Quellkamera werden nicht kopiert. Sie braucht 6 Byte pro Pixel, ein Bild mit 24 Megapixeln hat also rund 144 MB.

DNG wird für unkomprimierte Quellen angeboten: TIFF, Kamera-RAW und DNG. JPEG-, PNG- und HEIC-Quellen lassen sich nicht als DNG exportieren. Entwickeln, das Ziel `PRINT` und die Abzugslayouts unterstützen alle DNG. Das Abzug-DNG hält die zusammengesetzte Seite in Standard-RGB mit einer ColorMatrix fest, die ICC-Umrechnung des Druckers entfällt. Der DNG-Export nutzt den in Export gewählten Ordner und behält die Endung `.dng`. Abgeschlossen ist er erst, wenn die endgültige Datei veröffentlicht und geprüft ist. exiftool und der Bilddecoder von Apple lesen die Datei. Die Darstellung in anderen RAW-Editoren wurde nicht gemessen.

## Was die Quelle verändert

| Aktion | Quelle im Finder | Katalog und Bearbeitungen |
|---|---|---|
| `×` am Ordner | Bleibt erhalten | Ordner und Fotos aus der Mediathek entfernt |
| In einen anderen Ordner ziehen | Verschoben; bei Namenskonflikt wird ein neuer Name gewählt | Auf den neuen Ort neu verknüpft |
| Im Finder verschieben oder umbenennen | Die Änderung des Nutzers bleibt erhalten | Automatisch über das Lesezeichen neu verknüpft |
| Ordnerentwicklung anwenden | Bleibt erhalten | Prozess und Ziel aktualisiert, dann neu gerendert |
| Vorgabe oder Kopieren/Einfügen | Bleibt erhalten | Gewählte Entwicklungs- und Geometriewerte aktualisiert |
| Abzugsexport | Bleibt erhalten | Eine eigene Ausgabedatei und ein Renderprotokoll entstehen |

## Prüfung einer großen Mediathek

Ab 256 Fotos macht der Filmstreifen nach jedem Auswahlwechsel keine langen automatischen Scrollsprünge mehr. Sichtbare Karten und Ordnerzeilen werden bei Bedarf erzeugt.

Der Belastungstest mit 2.000 Bildern importiert Pixelvorlagen mit 24 MP, 40 MP, 60 MP, 3200 DPI und 4800 DPI in 50 Ordner. Er mischt alle Prozesse und Ziele, hält Farbnegative über der Hälfte, wendet Beschnitt- und Ausrichtungsänderungen an und prüft dann Entwicklung, Miniaturen und den Katalog-Rundlauf. Aufruf aus `negaflow-mac/`:

```bash
bash scripts/performance/run-virtual-library-stress.sh
```

Der Belastungstest ist auf Anforderung zu starten und wird bei normalen `swift test`-Läufen übersprungen.
