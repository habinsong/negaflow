# Von der Bibliothek zum Druck

[Dokumentationsstart](../README.md)

Diese Anleitung beschreibt Import, Ordnerentwicklung, Übertragen von Einstellungen, Scanner-Vorschaubilder und Druckausgabe. Ein Bibliotheksordner folgt dem tatsächlichen Quellordner eines Fotos.

> [!IMPORTANT]
> Quelldateien bleiben unverändert, außer ein Foto wird ausdrücklich in einen anderen Ordner verschoben. Aus der Bibliothek entfernen und im Finder löschen sind getrennte Vorgänge.

## Import

Unter den Importaktionen stehen Fortschrittsbalken, Prozentwert, erledigte Anzahl und Gesamtzahl. Metadaten werden im Hintergrund gelesen; neue Bilder werden anschließend gemeinsam registriert, damit ein großer Ordner den Bibliotheksindex nicht wiederholt aufbaut.

Die automatische Entwicklung importierter Bilder ist **standardmäßig ausgeschaltet**. Zuerst erscheinen Quellvorschaubild und Ordner. Die Entwicklung beginnt nach Anwendung von Prozess und Ziel auf den Ordner oder beim Öffnen von Entwickeln. Für eine automatische Entwicklung aktivieren Sie **Einstellungen → Arbeitsablauf → Importierte Bilder automatisch entwickeln**.

Die automatische Importentwicklung gilt nur für Bilder, die dieser Import neu registriert. Sie überschreibt keinen bereits entwickelten Zustand. Entwickelte Fotos werden nur nach einem ausdrücklichen Ordner-**Anwenden** oder dem Einfügen von Einstellungen erneut verarbeitet.

Scanneraufnahmen sind eine Ausnahme: Filmtyp, Prozess und Ziel sind bereits gewählt. Nach der Veröffentlichung werden sie sofort entwickelt. Die Filmstreifen in Entwickeln und Druck zeigen für Farbnegative, Dias, Schwarzweißnegative und Schwarzweißpositive das entwickelte Vorschaubild.

## Ordner

- Der Ein-/Ausklappzustand wird gespeichert. Ein neuer Ordner oder Neustart öffnet keine anderen.
- Jede Ordnerzeile hat dasselbe `×`. Es entfernt den Ordner nur aus der **Bibliothek**; die Quellen bleiben im Finder.
- In Entwickeln scrollt die Fotoliste innerhalb des Ordners, ohne den Rest der Seitenleiste wegzuschieben.

### Fotos in einen anderen Ordner verschieben

Beim Ziehen eines Fotos oder einer Auswahl auf einen anderen Ordner werden Dateien und Katalog gemeinsam aktualisiert. Dies gilt für importierte, von der App erstellte und Scannerordner. Ist `frame.tiff` vorhanden, wird `frame 2.tiff`, danach `frame 3.tiff` gewählt. Es wird nichts überschrieben. Eine zugehörige IR-Datei wird in derselben Transaktion verschoben.

### Änderungen im Finder

Nach Verschieben oder Umbenennen im Finder verbindet das persistente Lesezeichen das bestehende Foto oder den Ordner mit dem neuen Ort. Neue Bilder direkt in einem registrierten Ordner werden ebenfalls importiert. Nur Ordner mit einem Änderungsereignis werden gelesen; es gibt keinen periodischen Komplettscan.

## Entwicklung pro Ordner

Wählen Sie Prozess und Ziel neben dem Ordnernamen und klicken Sie **Anwenden**. Einen zusätzlichen Ein-/Aus-Schalter gibt es nicht.

Alle Fotos im Ordner werden neu gerendert, auch bereits entwickelte. Prozess und Ziel werden ersetzt, andere manuelle Korrekturen wie Belichtung und Kontrast bleiben erhalten. Neben Anwenden stehen Fortschrittsbalken, Prozentwert, erledigte Anzahl und Gesamtzahl. Die Warteschlange hält nur so viele Aufgaben wie Renderplätze bereit.

## Vorgaben und Kopieren/Einfügen

Entwicklungseinstellungen haben sieben unabhängig wählbare Gruppen.

| Gruppe | Werte |
|---|---|
| Eingabegamma | Interpretation der Übertragungskennlinie der Quelle |
| Basisskalierung | Multiplikator der Filmbasis |
| Basis | Filmtyp und Prozess, Ziel, Scannerprofil, Filmbasis, Kanaldichtekorrektur, automatische Balance, Tonwerte und Neutralabgleich |
| Ton | Belichtung, Kontrast, Dichte, Lichter, Schatten, Weiß, Schwarz und Kurven |
| Farbe | Temperatur, Farbton, Farbtiefe, Dynamik, Sättigung, Mischer, Grading, Kalibrierung, S/W-Tonung und Film-Emulation |
| Details | Korn, Schärfe, Halation, Klarheit, Vignette, Rauschminderung, GrainMend-Stärke und lokale Korrekturen |
| Geometrie | Beschnitt, Drehung, Spiegelung, Ausrichtung und Beschnittformat |

Vollständiges Einfügen und Benutzervorgaben ersetzen die Entwicklungseinstellungen des Ziels. Teilweises Einfügen ersetzt die wirksamen Werte der gewählten Gruppen und erhält die übrigen. Wird nur ein Teil eines Looks eingefügt, werden dessen Ton-, Farb- und Texturbeiträge in die Werte eingerechnet und der Look-Verweis entfernt. Der alte Look wird dadurch nicht erneut addiert. Wiederholtes Einfügen derselben Einstellungen verändert den Zustand nicht weiter. Bedienfeld, Menüs und Tastenkürzel verwenden denselben Einfügebereich.

Einfügen und Benutzervorgaben gelten für alle ausgewählten Fotos. Einmal Rückgängig oder Wiederholen umfasst die gesamte Auswahl. Windows prüft alle Ziele vor dem Ersetzen. Miniaturen und aktive Vorschau werden mit den neuen Einstellungen aktualisiert. Originaldateien, Bewertungen und quellgebundene Defektbearbeitungen werden nicht kopiert.

Benutzervorgaben speichern den vollständigen Entwicklungszustand einschließlich Geometrie. Ältere Formate ohne Geometriefeld schließen es aus Kompatibilitätsgründen ein. Ein leerer Name erhält die erste freie Nummer. Ein gleicher Name allein überschreibt keine vorhandene Vorgabe.

## Ohne Scanner-Plug-in

Ist beim Start kein Plug-in installiert, zeigt die gemeinsame Seitenleiste von Bibliothek und Entwickeln den Hinweis, die erneute Suche und den Simulator nicht automatisch. Der Bildimport bleibt verfügbar. Suche und Simulator wurden nicht entfernt und können über den Scanner-Einstieg oder die Einstellungen geöffnet werden.

## Abzugslayouts und Ausgabeanzahl

Der Druckbereich bietet sieben Layouts: Einzelbild, Kontaktbogen, Bildpaket, Benutzerpaket, Cyanotypie, Glasplatte und Silbergelatine. Die letzten drei verwenden denselben Inspektor wie das Einzelbild. Bei mehreren Fotos zeigen die vier Einzelbildlayouts je Foto eine vollständige Abzugsseite in einer vertikal scrollbaren Folge.

Abzugsexport und Schnellexport zählen fertige Seiten. 39 Fotos auf einem 6 × 7-Kontaktbogen ergeben eine zusammengesetzte Datei, ein Vierer-Bildpaket 10 Seiten, das vorgegebene Benutzerpaket eine Seite und die Einzelbildlayouts einen begrenzten Stapel mit 39 Dateien.

Die Vorschau verwendet vorhandene Miniaturen, entwickelte Bilder oder Quellvorschauen und erzeugt nur bei Bedarf eine kleine schnelle Vorschau. Der finale Export berechnet die Platzierungen aus Metadaten, entwickelt nur die benötigten Pixel, bereitet zwei bis vier Quellen gleichzeitig vor und hält den Core-Image-Graphen bis zum Seitenrendering verbunden. Ein gemeinsamer Kontext und ein Rasterbudget von 512 MiB pro Seite verhindern unbegrenzte Vollauflösungs-Zwischenbilder.

## Druck-Wasserzeichen

Layouts mit einem Foto pro Seite (Einzelbild, Cyanotypie, Glasplatte, Silbergelatine) können unter dem Foto einen Wasserzeichenrand anfügen. Der Rand kommt außen an das Foto, nichts wird beschnitten. Ein gleich hoher Rand lässt sich auch oben anfügen. Beim Papierformat „Foto“ folgt das Papier dem Foto samt Rändern.

Der untere Rand zeigt links die Kamera und darunter das Objektiv. Rechts stehen ein Logo, dann Brennweite, Blende, Verschlusszeit und ISO, darunter das Aufnahmedatum. Mit „Logo“ an wird ein Logo eingefügt; ohne gewählte Datei das negaflow-Logo. negaflow liefert keine Herstellerlogos mit, wählen Sie also eine eigene JPEG-, PNG- oder andere Bilddatei. Einstellungen und Vorlagen speichern nur den Dateipfad. Beim Zeichnen wird die Datei geprüft; solange Größe und Änderungszeit gleich bleiben, wird das zwischengespeicherte Logo verwendet. Wurde die Datei verschoben oder gelöscht, fehlt nur das Logo; der Statuspunkt unten und der Diagnosebericht halten das fest. Leere Felder für Kamera, Objektiv und Belichtung übernehmen die Aufnahmedaten jedes Fotos. Das Datum wird nicht automatisch gefüllt.

Der Rand kann weiß, schwarz oder eine Unschärfe des Fotos sein. Auf Weiß ist die Schrift schwarz, die zweiten Zeilen grau. Auf Schwarz ist die ganze Schrift weiß. Bei Unschärfe wählen Sie Schwarz oder Weiß für Schrift und Histogramm. Das Histogramm besteht aus Punktsäulen. Histogramm und Name stehen jeweils unten in der Mitte oder, wenn der obere Rand an ist, oben links, mittig oder rechts. Stehen beide am selben mittigen Platz, werden sie spiegelbildlich zur Mittellinie gesetzt. Unschärfe und Histogramm verwenden eine gültige Filmstreifen-Miniatur erneut, wenn sie vorhanden ist. Andernfalls verwenden sie ein verkleinertes Foto. Vorlagen speichern die Papierfarbe und alle Wasserzeichen-Einstellungen samt Texten und Logopfad.

## Druckprofile

| Einstellung | Vorschau | Druckexport | Entwickeln |
|---|---|---|---|
| Drucker-Ausgabeprofil | Zeigt das Ergebnis | Auf die fertige Seite angewendet | Nie angewendet |
| C-Print-Proofprofil | Simuliert Labor und Papier | Nicht in die Lieferdatei eingebrannt | Nie angewendet |

Das Ausgabeprofil wird einmal nach der vollständigen Zusammensetzung von Kontaktbogen, Fotopaket oder benutzerdefiniertem Paket angewendet. Wiederholte Platzierungen und gemischte Fotos erhalten alle dieselbe Umwandlung. Mehr dazu unter [Drucklayouts und C-Print-Vorschau](../reference/C_PRINT.md).

## DNG-Export

Das DNG schreibt das entwickelte Bild als unkomprimierte lineare 16-Bit-RGB-Datei (`PhotometricInterpretation = LinearRaw`) im gewählten Ausgabefarbraum: sRGB, Display P3 oder Adobe RGB. Ton und Farbe sind bereits eingerechnet, andere Programme lesen die Datei daher als ausgabebezogen. Urheberrecht, Scanner, Software, Datum und Filmangaben folgen derselben Metadatenrichtlinie wie beim TIFF. EXIF, IPTC und GPS der Quellkamera werden nicht übernommen. Pro Pixel sind es 6 Byte, ein Bild mit 24 Megapixeln hat also etwa 144 MB.

DNG ist für unkomprimierte Quellen wählbar: TIFF, Kamera-RAW und DNG. JPEG-, PNG- und HEIC-Quellen lassen sich nicht als DNG exportieren. Entwicklung, das Ziel `PRINT` und Drucklayouts unterstützen DNG. Das Druck-DNG speichert die zusammengestellte Seite in Standard-RGB mit einer ColorMatrix; die Drucker-ICC-Konvertierung entfällt. Der DNG-Export verwendet den unter Export gewählten Ordner und die Endung `.dng`. Der Export ist erst abgeschlossen, wenn die endgültige Datei veröffentlicht und geprüft wurde. exiftool und Apples Bilddecoder lesen die Datei. Die Darstellung in Lightroom oder Camera Raw wurde nicht gemessen.

## Was die Originale verändert

| Aktion | Original im Finder | Katalog und Bearbeitungen |
|---|---|---|
| `×` am Ordner | Bleibt | Ordner und Fotos verlassen die Bibliothek |
| Foto in einen anderen Ordner ziehen | Wird verschoben, bei Namensgleichheit umbenannt | Wird neu verknüpft |
| Verschieben oder Umbenennen im Finder | Die Änderung bleibt bestehen | Über das Lesezeichen automatisch neu verknüpft |
| Entwicklung pro Ordner anwenden | Bleibt | Prozess und Ziel aktualisiert, danach neu gerendert |
| Vorgabe oder Kopieren/Einfügen | Bleibt | Ausgewählte Entwicklungs- und Geometriewerte aktualisiert |
| Abzugs-Export | Bleibt | Eine eigene Ausgabedatei und ein Render-Protokoll entstehen |

## Prüfung mit 2.000 Bildern

Bei mehr als 256 Fotos vermeidet der Filmstreifen lange automatische Sprünge und erzeugt nur die benötigten Elemente. Die Prüfung verteilt 24-MP-, 40-MP-, 60-MP-, 3200-DPI- und 4800-DPI-Quellen auf 50 Ordner, mischt alle Prozesse und Ziele sowie Beschnitt und Ausrichtung und prüft danach Entwicklung, Vorschaubilder und Katalog.

```bash
bash scripts/performance/run-virtual-library-stress.sh
```

Diese lange Prüfung wird bei einem normalen `swift test` übersprungen.
