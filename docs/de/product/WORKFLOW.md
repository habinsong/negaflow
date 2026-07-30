# Von der Bibliothek zum Druck

[Dokumentationsstart](../README.md)

Diese Anleitung beschreibt Import, Ordnerentwicklung, Übertragen von Einstellungen,
Scanner-Vorschaubilder und Druckausgabe. Ein Bibliotheksordner folgt dem tatsächlichen
Quellordner eines Fotos und ist nicht nur eine interne Kategorie.

> [!IMPORTANT]
> Quelldateien bleiben unverändert, außer ein Foto wird ausdrücklich in einen anderen Ordner
> verschoben. Aus der Bibliothek entfernen und im Finder löschen sind getrennte Vorgänge.

## Import

Unter den Importaktionen stehen Fortschrittsbalken, Prozentwert, erledigte Anzahl und Gesamtzahl.
Metadaten werden im Hintergrund gelesen; neue Bilder werden anschließend gemeinsam registriert,
damit ein großer Ordner den Bibliotheksindex nicht wiederholt aufbaut.

Die automatische Entwicklung importierter Bilder ist **standardmäßig ausgeschaltet**. Zuerst
erscheinen Quellvorschaubild und Ordner. Die Entwicklung beginnt nach Anwendung von Prozess und Ziel
auf den Ordner oder beim Öffnen von Entwickeln. Für eine automatische Entwicklung aktivieren Sie
**Einstellungen → Arbeitsablauf → Importierte Bilder automatisch entwickeln**.

Die automatische Importentwicklung gilt nur für Bilder, die dieser Import neu registriert. Sie
überschreibt keinen bereits entwickelten Zustand. Entwickelte Fotos werden nur nach einem
ausdrücklichen Ordner-**Anwenden** oder dem Einfügen von Einstellungen erneut verarbeitet.

Scanneraufnahmen sind eine Ausnahme: Filmtyp, Prozess und Ziel sind bereits gewählt. Nach der
Veröffentlichung werden sie sofort entwickelt. Die Filmstreifen in Entwickeln und Druck zeigen für
Farbnegative, Dias, Schwarzweißnegative und Schwarzweißpositive das entwickelte Vorschaubild.

## Ordner

- Der Ein-/Ausklappzustand wird gespeichert. Ein neuer Ordner oder Neustart öffnet keine anderen.
- Jede Ordnerzeile hat dasselbe `×`. Es entfernt den Ordner nur aus der **Bibliothek**; die Quellen
  bleiben im Finder.
- In Entwickeln scrollt die Fotoliste innerhalb des Ordners, ohne den Rest der Seitenleiste
  wegzuschieben.

Beim Ziehen eines Fotos oder einer Auswahl auf einen anderen Ordner werden Dateien und Katalog
gemeinsam aktualisiert. Dies gilt für importierte, von der App erstellte und Scannerordner. Ist
`frame.tiff` vorhanden, wird `frame 2.tiff`, danach `frame 3.tiff` gewählt. Es wird nichts
überschrieben. Eine zugehörige IR-Datei wird in derselben Transaktion verschoben.

Nach Verschieben oder Umbenennen im Finder verbindet das persistente Lesezeichen das bestehende
Foto oder den Ordner mit dem neuen Ort. Neue Bilder direkt in einem registrierten Ordner werden
ebenfalls importiert. Nur Ordner mit einem Änderungsereignis werden gelesen; es gibt keinen
periodischen Komplettscan.

## Entwicklung pro Ordner

Wählen Sie Prozess und Ziel neben dem Ordnernamen und klicken Sie **Anwenden**. Einen zusätzlichen
Ein-/Aus-Schalter gibt es nicht.

Alle Fotos im Ordner werden neu gerendert, auch bereits entwickelte. Prozess und Ziel werden
ersetzt, andere manuelle Korrekturen wie Belichtung und Kontrast bleiben erhalten. Neben Anwenden
stehen Fortschrittsbalken, Prozentwert, erledigte Anzahl und Gesamtzahl. Die Warteschlange hält nur
so viele Aufgaben wie Renderplätze bereit.

## Vorgaben und Kopieren/Einfügen

| Gruppe | Werte |
|---|---|
| Basis | Filmtyp und Prozess, Ziel, Scannerprofil und Filmbasis |
| Ton | Belichtung, Kontrast, Dichte, Lichter, Schatten, Weiß, Schwarz und Kurven |
| Farbe | Temperatur, Farbton, Sättigung, Mischer, Grading, S/W-Tonung und Film-Emulation |
| Details | Korn, Schärfe, Halation, Klarheit, Vignette, Rauschminderung, GrainMend und lokale Korrekturen |
| Geometrie | Beschnitt, Drehung, Spiegelung, Ausrichtung und Beschnittformat |

Vollständiges Einfügen verwendet alle Gruppen, eine Auswahl nur die gewählten. Bei mehreren
markierten Fotos gilt es für die ganze Auswahl. Benutzervorgaben speichern denselben vollständigen
Entwicklungszustand einschließlich Geometrie.

## Ohne Scanner-Plug-in

Ist beim Start kein Plug-in installiert, zeigt die gemeinsame Seitenleiste von Bibliothek und
Entwickeln den Hinweis, die erneute Suche und den Simulator nicht automatisch. Der Bildimport
bleibt verfügbar. Suche und Simulator wurden nicht entfernt und können über den Scanner-Einstieg
oder die Einstellungen geöffnet werden.

## Abzugslayouts und Ausgabeanzahl

Der Druckbereich bietet sieben Layouts: Einzelbild, Kontaktbogen, Bildpaket, Benutzerpaket,
Cyanotypie, Glasplatte und Silbergelatine. Die letzten drei verwenden denselben Inspektor wie das
Einzelbild. Bei mehreren Fotos zeigen die vier Einzelbildlayouts je Foto eine vollständige
Abzugsseite in einer vertikal scrollbaren Folge.

Abzugsexport und Schnellexport zählen fertige Seiten statt ausgewählter Quellen. 39 Fotos auf einem
6 × 7-Kontaktbogen ergeben eine zusammengesetzte Datei, ein Vierer-Bildpaket 10 Seiten, das
vorgegebene Benutzerpaket eine Seite und die Einzelbildlayouts einen begrenzten Stapel mit 39
Dateien.

Die Vorschau verwendet vorhandene Miniaturen, entwickelte Bilder oder Quellvorschauen und erzeugt
nur bei Bedarf eine kleine schnelle Vorschau. Der finale Export berechnet die Platzierungen aus
Metadaten, entwickelt nur die benötigten Pixel, bereitet zwei bis vier Quellen gleichzeitig vor
und hält den Core-Image-Graphen bis zum Seitenrendering verbunden. Ein gemeinsamer Kontext und ein
Rasterbudget von 512 MiB pro Seite verhindern unbegrenzte Vollauflösungs-Zwischenbilder.

## Druckprofile

| Einstellung | Vorschau | Druckexport | Entwickeln |
|---|---|---|---|
| Drucker-Ausgabeprofil | Zeigt das Ergebnis | Auf die fertige Seite angewendet | Nie angewendet |
| C-Print-Proofprofil | Simuliert Labor und Papier | Nicht in die Lieferdatei eingebrannt | Nie angewendet |

Das Ausgabeprofil wird einmal nach der vollständigen Zusammensetzung von Kontaktbogen, Fotopaket
oder benutzerdefiniertem Paket angewendet. Wiederholte Platzierungen und gemischte Fotos erhalten
alle dieselbe Umwandlung. Mehr dazu unter
[Drucklayouts und C-Print-Vorschau](../reference/C_PRINT.md).

## Prüfung mit 2.000 Bildern

Bei mehr als 256 Fotos vermeidet der Filmstreifen lange automatische Sprünge und erzeugt nur die
benötigten Elemente. Die Prüfung verteilt 24-MP-, 40-MP-, 60-MP-, 3200-DPI- und 4800-DPI-Quellen
auf 50 Ordner, mischt alle Prozesse und Ziele sowie Beschnitt und Ausrichtung und prüft danach
Entwicklung, Vorschaubilder und Katalog.

```bash
bash scripts/performance/run-virtual-library-stress.sh
```

Diese lange Prüfung wird bei einem normalen `swift test` übersprungen.
