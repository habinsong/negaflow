# Produktstruktur

[Dokumentationsstart](../README.md)

negaflow ist eine App für macOS und Windows. Sie importieren oder scannen Filmbilder und durchlaufen dann Invertierung, Entwicklung, GrainMend, Ausgabe und Erhaltung. Jede Bearbeitung wird getrennt vom Original aufbewahrt.

> [!IMPORTANT]
> Originale, Bearbeitungsverlauf, Caches und Ausgabedateien sind verschiedenes Material. Der Verlust eines Caches darf nicht das Original oder den Bearbeitungsverlauf kosten, und ein Export schlägt fehl, wenn ein benötigtes Ergebnis nicht wiederhergestellt werden kann.

## Sicherheitsregeln, die sich nicht ändern

1. Originalbilder und fremde Sidecar-Dateien werden nie automatisch überschrieben.
2. Etwas aus der Mediathek zu entfernen und das Original in den Papierkorb zu legen sind getrennte Vorgänge.
3. Die Scanneroberfläche zeigt nur, was das Plug-in gemeldet hat.
4. Der Demo-Scanner wird nur verwendet, wenn Sie ihn ausdrücklich wählen.
5. Lässt sich ein bearbeitetes Ergebnis nicht wiederherstellen, wird nicht das Original an seiner Stelle exportiert.
6. Eine lange Aufgabe prüft Bild, Bearbeitungsversion und Sitzung unmittelbar vor dem Anwenden ihres Ergebnisses erneut.
7. Ein Cache muss aus dem Original und dem Bearbeitungsverlauf wiederherstellbar sein.
8. Profile, Ausgabepakete und Archive werden erst veröffentlicht, nachdem die erforderlichen Prüfungen bestanden sind.

## Module

`negaflowApp` und `negaflowCLI` nutzen beide `Chromabase` und `ScannerKit`. `Chromabase` arbeitet mit Bildern und Metadaten, und `ScannerKit` spricht mit dem externen Scanner-Plug-in.

### `Chromabase`

Die Chroma Engine und der Kern der Bildverarbeitung.

- Bilder lesen und Ausrichtung behandeln
- Messung der Filmbasis
- Entwicklung von Negativen und Positiven
- Tonwert, Farbe und lokale Anpassungen
- Film-, Look- und Scannerprofile
- GrainMend RGB und IR
- Histogramm und Farbmessung
- Ausgabekodierung und Metadaten

Mehr dazu:

- [Chroma Engine](../product/CHROMA_ENGINE.md)
- [GrainMend](../product/GRAINMEND.md)

### `ScannerKit`

Es besitzt den Vertrag, der ein externes Plug-in anbindet.

- Scanner-ID und Fähigkeiten
- JSON für Anfragen und Antworten
- Ausführen des externen Prozesses, Zeitgrenzen, Abbruch
- Eigentümer, Rechte, Freigabe und Hash des Plug-ins
- Prüfen der temporären Ausgabe, dann Veröffentlichen der endgültigen Datei
- Scansitzungen und Auftragsverlauf
- Der Demo-Scanner, den Sie selbst einschalten müssen

Die SANE-Implementierung liegt in einem eigenen GPL-Projekt, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane). App und Plug-in sprechen nur über JSON und die CLI miteinander.

### `negaflowCLI`

Nutzt dieselbe Engine und dasselbe `ScannerKit` wie die grafische Oberfläche.

- Scanner finden, Fähigkeiten prüfen, scannen
- Mehrere Bilder entwickeln
- Scannerprofile auflisten
- GrainMend `defect-bench`
- IT8 und scannerbezogener Vergleich
- Selbsttests und JSON-Automatisierung

### `negaflowApp`

Die Benutzeroberfläche, gebaut mit SwiftUI und AppKit.

- Mediathek, Entwickeln, Abzug, Zeichenfläche
- Scannen, GrainMend, Export
- Versionen, Einstellungen, Kurzbefehle
- Katalog, Cache, Backup, Erhaltungsarchiv
- Ein lokalisiertes Info-Fenster, dessen Produktversion aus der gemeinsamen Versionsressource stammt

## Ablauf für Nutzer

1. Importieren oder scannen.
2. Die Mediathek ordnen.
3. Filmart und Basis festlegen.
4. In der Chroma Engine entwickeln, mit GrainMend reparieren oder mit Versionen und virtuellen Kopien verzweigen.
5. Prüfen, drucken oder exportieren in Bilddateien, Sidecar-Dateien und Renderprotokolle oder in ein Erhaltungsarchiv.

Jeder Schritt lässt das Original unberührt und ergänzt Katalog und Bearbeitungsverlauf.

## Eingabe und Originale

### Dateien importieren

Der Standardweg. Er verarbeitet TIFF, JPEG, PNG und das Kamera-RAW, das Image I/O unter macOS lesen kann. Das eingebettete ICC und die Ausrichtung werden gelesen, und die ID des Originals kommt in den Katalog.

### Scannen

Ein installiertes Plug-in kann diese Fähigkeiten melden:

- Auflösung und Bittiefe
- Scanbereich und Vorschau
- Belichtung
- IR
- Verhalten von Stapel und Halter

Die App erfindet nie eine Fähigkeit aus einer Tabelle von Modellnamen. Ist ein Scan fertig, werden die vom Plug-in tatsächlich angewendeten Einstellungen und die Ausgabedatei erneut geprüft.

### ID des Originals

Ein Dateipfad allein identifiziert kein Original. Die Werte, die der aktuelle Vertrag braucht, werden festgehalten: Dateibeobachtungen, Bytezahl, Änderungszeit, SHA-256 und ein dauerhaftes Lesezeichen.

Wurde eine Datei verschoben, ändert sich der Pfad nur, wenn Sie sie selbst neu verknüpfen oder die Lesezeichen-Wiederherstellung gelingt.

## Katalog

Der Hauptspeicher ist `library.sqlite`. Das ältere `library.json` dient dazu, bestätigtes älteres Material zu übernehmen oder ein Backup zu schreiben, das zwischen Rechnern wandern kann. Beide Speicher werden nie gleichzeitig aktualisiert.

Was in SQLite kommt:

- Bilder und Originale
- Filme, Ordner, Sammlungen, Suchen
- Reihenfolge und Scanaufträge
- Entwicklungswerte und Bearbeitungsverlauf je Version

Was nicht:

- Originalpixel
- Miniaturen und Vorschauen
- GrainMend-Caches

### Übernahme aus JSON

1. Schema und Zustand des vorhandenen JSON prüfen.
2. Eine Wiederherstellungskopie behalten.
3. In einer Transaktion in eine temporäre SQLite-Datenbank schreiben.
4. Den Katalog vorher und nachher vergleichen.
5. SQLite-Integrität und die Sicherheitsbedingungen der App prüfen.
6. Den Hauptspeicher nur umstellen, wenn alles übereinstimmt.

Ein fehlgeschlagenes JSON gilt nicht als leerer Katalog. Die Zahlen stehen in [Katalogspeicherung](CATALOG_STORAGE.md).

## Mediathek

Ordnen:

- Ordner, Filme, manuelle Sammlungen, intelligente Sammlungen, gespeicherte Suchen, Stapel
- Sternebewertungen, Auswählen und Ablehnen, Farbetiketten
- Raster, Vergleich, Übersicht
- Prüfung von Duplikatkandidaten

In der Ordneransicht zeigt jeder Ordner ein Band mit Aufklappdreieck, Ordner, Name, Anzahl, Entwicklungsprozess, Ziel und Anwenden. Das Band klappt die Miniaturen darunter ein. Eingeklappte Ordner werden über Neustarts hinweg gemerkt, getrennt von der Dateiliste der Seitenleiste.

Die Ordneransicht nutzt ein einziges Raster, jeder Ordner ist ein Abschnitt, sein Band die Abschnittsüberschrift. Behalten Sie diese Struktur bei. Ein eigenes Raster je Ordner zu stapeln zwingt das Layout, die volle Höhe jedes sichtbaren Ordners zu berechnen und alle seine Karten auf einmal zu erzeugen, während ein einziges Raster die Karten zeilenweise erzeugt, wenn sie ins Bild kommen. So bleibt das Scrollen bei mehreren hundert Fotos flüssig.

Mehrere virtuelle Kopien können ein Original teilen. Verweise auf ein Original werden vor dem Löschen geprüft. Etwas aus der Mediathek zu entfernen ändert nur Katalogverweise, und der Papierkorb ist ein anderer Vorgang.

Bearbeitungen bleiben erhalten, wenn ein externer Datenträger getrennt wird. Das Original wird als offline markiert, und Sie verknüpfen es nach Datei oder Ordner neu. Ist die ID nicht die erwartete, wird nichts automatisch ausgetauscht.

Jeder registrierte physische Quellordner hat einen Dateisystem-Beobachter. Ereignisse werden kurz zusammengefasst, dann wird nur der geänderte Ordner neu geprüft. Die Neuverknüpfung über Lesezeichen erhält die Ordner-ID im Katalog, wenn der Finder eine Quelle verschiebt oder umbenennt, und neu hinzugekommene Bilder direkt im Ordner werden ohne Polling und ohne erneutes Durchsuchen der ganzen Mediathek importiert.

## Entwicklung und GrainMend

Jedes Bild trägt:

- ID des Originals und Filmart
- Filmbasis
- Entwicklungswerte
- GrainMend-Bearbeitungsverlauf
- Versionsverlauf
- Exportzustand

Während Sie anpassen, wird eine Vorschau niedrigerer Auflösung verwendet. Ein fertiges Ergebnis erreicht den Bildschirm nur, wenn Bild-ID und Bearbeitungsversion noch zur aktuellen Auswahl passen.

Die Wahl eines anderen Fotos startet dessen beruhigtes Rendern ohne die Bearbeitungspause. Unter macOS:

- Ist ein Kamera-RAW-Negativ beruhigt, kann das nächste sichtbare RAW im Hintergrund dekodiert werden. Vorbereitet wird nur ein Nachbar, innerhalb des vorhandenen Master-Caches (bis 160 MiB). Eine Bearbeitung, eine andere Auswahl oder Speicherdruck bricht diese Arbeit ab, und die Wahl des gerade vorbereiteten Fotos teilt dessen Dekodierung.
- Eine kalte Auswahl von Kamera-RAW entpackt die Sensordaten nur einmal. Erlaubt das Mosaik es, erscheint eine vorläufige Kamera-RGB-Vorschau, bevor das kanonische Demosaicing fertig ist. Der Master-Cache bleibt bei Speicherdruck ausgeschaltet, und das Verdrängen eines Bildes wirft auch seinen RAW-Master weg.
- Eine kalte TIFF-Auswahl teilt eine dekodierte Quelle zwischen interaktiver und beruhigter Vorschau und skaliert sie auf der GPU. Apple-RAW-Vorschauen, auch DNG, behalten einen `CIRAWFilter` für beide Durchläufe.
- Bereinigte RAW-TIFFs werden geschrieben, wenn ihre Pixelpuffer den Speicher verlassen, nicht nach jeder Bearbeitung. Die Datenträgerbereinigung behält neuere Dateien innerhalb einer Grenze, schützt Dateien in Benutzung und löscht beim nächsten Start die Caches der vorigen Sitzung. Bearbeitungsrezepte bleiben in Sidecar-Dateien.

Unter Windows nutzen JPEG-Miniaturen ein LRU-Bytebudget und BGRA-Vorschauen den Rest des verwalteten Anzeigebudgets, und kritischer Speicherdruck verwirft ungenutzte JPEGs. D3D-Staging-Puffer haben eine Cachegrenze, die Signale für wenig Speicher, das Ende eines Exports und das Zurücksetzen des Geräts freigeben.

Der Export speichert nicht die Vorschau-Bitmap auf dem Bildschirm. Er baut das Bild in voller Auflösung aus dem Original und den festgelegten Bearbeitungswerten neu auf.

GrainMend hält Automatisch, Geführt, Pinsel, Klonstempel und IR in einer geordneten Liste. Caches sind abgeleitete Dateien. Lässt sich ein Ergebnis nicht aus dem Original und dem Bearbeitungsverlauf wiederherstellen, scheitert der Export.

Mehr dazu in [GrainMend](../product/GRAINMEND.md).

## Versionen

- Verlauf und Schnappschuss: einen Entwicklungszustand selbst festhalten, dann vergleichen oder dorthin zurückkehren.
- Virtuelle Kopie: ein weiterer Zweig von Bearbeitungen, ohne die Originaldatei zu duplizieren.
- Kopieren/Einfügen: einen gewählten Bereich wie Tonwert, Farbe, Detail oder Geometrie einfügen. Bei Masken, die Originalkoordinaten brauchen, werden die Sicherheitsbedingungen geprüft.

## Export

Zu Beginn werden diese Werte zu einem Paket festgelegt:

- ID des Originals
- Entwicklungs- und GrainMend-Bearbeitungsverlauf
- Bytes und SHA-256 des Scannerprofils
- Ausgabeeinstellungen und Metadatenregeln
- Dateiname und Ziel

Ein angehaltener und fortgesetzter Export nutzt dasselbe Paket.

### Mehrere Ausgabedateien

Ein Export kann zugleich JPEG/TIFF, eine Sidecar-Datei, XMP und `-main-flat` erzeugen.

1. Ziel und Namenskonflikte vorab prüfen.
2. Alle Dateien in einen temporären Ordner schreiben.
3. Das Bild erneut öffnen und die Pixelgröße prüfen.
4. Bytezahlen und SHA-256 berechnen.
5. Sidecar-Datei und Renderprotokoll schreiben.
6. Einen Commit-Eintrag hinterlassen.
7. Das ganze Paket an den endgültigen Ort verschieben.
8. Bei einem Fehler zurückrollen oder beim nächsten Lauf aufräumen.

Ein unvollständiger Dateisatz wird nie als Erfolg markiert.

### Renderprotokoll v3

Es hält die SHA-256-Beziehungen fest zwischen:

- Den Bytes des Originals
- Der tatsächlich verwendeten Render-Eingabe
- Entwicklungs- und GrainMend-Verlauf
- Dem Scannerprofil
- Den Versionen von Decoder und Renderer
- Ausgabebytes, Pixelgröße, Format

Es gibt keine digitale Signatur und kein Zertifikat, deshalb ist es keine C2PA Content Credentials. Mehr dazu in [Render-Protokoll](../reference/RENDER_MANIFEST.md).

## Abzug und Softproof

Unterstützte Layouts:

- Einzelbild
- Kontaktbogen
- Bildpaket
- Eigenes Paket
- Cyanotypie
- Glasplatte
- Silbergelatine
- Wasserzeichen

Einzelbild und die drei historischen Layouts erzeugen je ausgewähltem Foto eine senkrecht gestapelte Seite. Kontaktbogen, Bildpaket und eigenes Paket melden und exportieren stattdessen ihre Zahl fertiger Seiten. Bei 39 Fotos ergibt das eine Kontaktbogenseite 6 × 7, 10 Seiten eines vierfachen Bildpakets, eine Seite des Standard-Pakets oder 39 einzelne Dateien.

Die Paketvorschau nutzt vorhandene Miniaturen und entwickelte Bilder wieder und erzeugt nur dann eine kleine schnelle Vorschau, wenn eine fehlt. Der endgültige Export berechnet die Platzierung aus den Metadaten, entwickelt nur die Pixel, die jede Zelle braucht, bereitet zwei bis vier verschiedene Quellen gleichzeitig vor, hält den Core-Image-Graphen bis zum Schreiben der Seite verbunden und setzt ein Budget von 512 MiB Quellraster pro Seite durch.

Jede Platzierung im Paket beachtet das ihr zugewiesene Bild. Das Druckerausgabe-ICC wird nach Abschluss des Layouts einmal auf die vollständige fertige Seite angewendet, sodass Pakete mit wiederholten und mit gemischten Quellen denselben Ausgabevertrag nutzen. Es ändert nie die Vorschau von Mediathek oder Entwickeln, und weder das ursprüngliche Scan-TIFF noch `-main-flat` erhalten ein Druckerprofil.

Ohne gültiges RGB-Drucker-ICC wird kein anderes Profil eingesetzt. Bytes und SHA-256 des gewählten Profils gehen in das Ausgabeprotokoll ein.

## Erhaltungsarchiv

Was in `.negaflowarchive` kommt:

- Das portable Katalog-JSON
- Originaldateien
- IR-Originale
- Der benötigte GrainMend-Verlauf
- Die Beziehung zwischen virtuellen Kopien und dem Original, das sie teilen

Miniaturen, Vorschauen, GrainMend-Caches und exportierte Dateien lassen sich wiederherstellen und bleiben daher draußen. Das Archiv nutzt die BagIt-Struktur nach RFC 8493 mit einer SHA-256-Liste, und jede Datei und jede Beziehung wird geprüft, bevor das Paket an den endgültigen Ort wandert.

- [Mediatheksarchiv](LIBRARY_ARCHIVE.md)
- [RFC 8493](https://www.rfc-editor.org/info/rfc8493/)
- [PREMIS](https://www.loc.gov/standards/premis/)

Langzeiterhaltung braucht außerdem andere Medien, eine externe Kopie und regelmäßige Hash-Prüfungen.

## Sicherheit der Scanner-Plug-ins

Wird ein Plug-in gefunden, wird geprüft:

- Ob es dem aktuellen Benutzer gehört
- Ob eine Gruppe oder ein anderer Benutzer es beschreiben kann
- Ob es ein symbolischer Link ist
- ID und SHA-256 von Eintrag und ausführbarer Datei
- Ob die ID, die Sie freigegeben haben, noch die ID vor Ihnen ist

Hat sich die Datei geändert, wird die frühere Freigabe nicht wiederverwendet.

Protokoll v2 nutzt eine Anfrage-ID und eine Sequenznummer und verlangt genau ein Endergebnis. Die Ausgabegröße hat eine Obergrenze, und nach einer Zeitüberschreitung oder einem Abbruch werden Prozess und Pipes aufgeräumt.

Ein Plug-in veröffentlicht nie selbst eine Datei am endgültigen Ort. Die App gibt ihm einen temporären Ort, prüft Format, Größe, ID und die tatsächlich angewendeten Einstellungen und verschiebt die Datei dann in den Speicher der App.

Der vollständige Vertrag steht in [Scanner-Plugin-Struktur](SCANNER_PLUGINS.md).

## Leistungsgrenzen

Bilder:

- Ein gemeinsamer `CIContext`
- Ein Bildgraph, der bei Bedarf berechnet wird
- Anpassung in niedriger Auflösung getrennt von der Ausgabe in voller Auflösung
- Abbruch, und Ablehnung veralteter Ergebnisse
- GrainMend, verarbeitet nach Bereich, Kachel und Patch
- Caches werden bei Speicherdruck verworfen

Katalog:

- SQLite-Transaktionen und Zeilen je Entität
- Backup über Replikation
- Integritätsprüfungen
- Gemessen bei 50.000 Bildern

Heute wird beim Start der gesamte Katalog in den Speicher geladen. Auf demselben Mac dauerte das Lesen von SQLite etwa 7,4 Sekunden, nahe an JSON. Nur die benötigten Zeilen über einen Index zu lesen ist der nächste Schritt.

Das Repository nutzt weite Leistungsgrenzen, um große Rückschritte zu fangen. Sie garantieren keine Reaktionsfähigkeit auf jedem unterstützten Mac.

## Was geprüft wird

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/run-app.sh build
```

Was automatische Prüfungen nicht entscheiden:

- Echte Scanner und Plug-ins
- Echte RGB/IR-Ausrichtung und Filmverträglichkeit
- GrainMend-Qualität bei 100 %
- Die Oberfläche, auch Bildschirmgröße und Barrierefreiheit
- Developer ID, Notarisierung, Gatekeeper
- Die Installation auf einem frischen Mac
- Die Leistung auf einem anderen Mac

## Dokumentenführer

| Was Sie wollen | Dokument |
|---|---|
| Invertierung und Entwicklung | [Chroma Engine](../product/CHROMA_ENGINE.md) |
| Defektreparatur | [GrainMend](../product/GRAINMEND.md) |
| Filmprofile | [Filmprofile](../product/FILM_PROFILES.md) |
| Einen Scanner anbinden | [Scanner-Plugin-Struktur](SCANNER_PLUGINS.md) |
| Freigabekriterien für Profile | [Qualitätsprüfung der Scannerprofile](../reference/PROFILE_QUALITY_GATE.md) |
| Erhaltungsarchiv | [Mediatheksarchiv](LIBRARY_ARCHIVE.md) |
| Hash-Beziehungen der Ausgabedateien | [Render-Protokoll](../reference/RENDER_MANIFEST.md) |
