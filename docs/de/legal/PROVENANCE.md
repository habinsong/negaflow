# Herkunft von Code und Ressourcen

[Dokumentationsstart](../README.md)

Hier steht der Apache-2.0-Auslieferungsumfang der negaflow-App. Es ist ein Herkunftsnachweis zur Überprüfung von Repository und Release-Artefakten und stellt kein Rechtsgutachten dar.

## Code

Der Swift-, Python- und Shell-Integrationscode in `negaflow-mac` wurde für negaflow geschrieben. Kamera-RAWs von Negativen werden mit einer festgelegten LibRaw-Revision als austauschbare `libraw.dylib` unter CDDL-1.0 dekodiert. Beide Plattformen ändern zwei LibRaw-Dateien: `src/demosaic/xtrans_demosaic.cpp` behält die Reihenfolge der Fuji-X-Trans-Kacheln bei und verarbeitet die Zeilen innerhalb einer Kachel parallel; `src/postprocessing/mem_image.cpp` kopiert die Zeilen der Ausgabebitmap parallel. Die Patches sind [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch) und [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch). Bei den getesteten RAW-Dateien stimmen die Pixel mit dem ungepatchten seriellen Build überein. Der frühere parallele X-Trans-Build konnte bei jedem Lauf andere Pixel erzeugen. Unter macOS wird LLVM OpenMP (libomp 20.1.8, Apache License v2.0 with LLVM Exceptions) statisch eingebunden. Die App enthält Quellarchiv, Patches, Build-Skript sowie Copyright- und Lizenztexte in `Contents/Resources/licenses/libraw/`. LibRaw-Code wird nicht in den Apache-Quellbaum übernommen. Windows verwendet dieselben Patches und dieselbe Revision; die übrigen Komponenten stehen in [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md). Die Testdatei `CameraNativeRaw.dng` stammt aus Eintrag 2204 von raw.pixls.us unter CC0-1.0. Die benachbarte JSON-Datei nennt die Quelle; die DNG-Datei wird nicht mit der App ausgeliefert.

Fehlt die zusätzliche Hinweisdatei, werden Build und Paketierung mit einer Warnung fortgesetzt. Die ursprünglichen Lizenzdateien und der zugehörige Quelltext bleiben enthalten.

Die Filmumkehr nutzt die veröffentlichten Begriffe der Sensitometrie: Dichte, Fuß, Geradenteil, Schulter. Kurven und Koeffizienten stammen aus den vier photometrischen Ankerpunkten von negaflow, nicht aus Formeln oder Konstanten eines fremden Programms. Gleichungen und Herleitung stehen in [feste Printantwort](../reference/PRINT_RESPONSE.md).

Veröffentlichte Hersteller-Datenblätter fließen in drei Gruppen ausgelieferter Filmkonstanten ein: die Dmin- und Dmax-Presets je Filmsorte (`FilmStockDmin`), die Schwarzweiß-Spektral- und Kennlinien-Presets (`BWFilmProfile`) sowie die physikalischen Korn- und MTF-Parameter (`DigitalFilmPhysics`). Diese Zahlen sind Näherungen aus den Kennlinien der Hersteller-Datenblätter, und `FilmStockDmin` markiert jeden Eintrag als `datasheetCurve` oder `estimated`, damit die Herkunft sichtbar bleibt. Eine aus einem veröffentlichten Diagramm abgelesene Zahl ist eine Tatsache über den Film und keine Kopie fremden Codes oder Textes; eine am Scan gemessene Filmbasis geht diesen Werten immer vor.

GrainMend IR arbeitet in dieser Reihenfolge.

1. Den ganzzahligen Versatz zwischen RGB und IR eigenständig schätzen.
2. Getrimmte IR-Mittelwerte je `log(red)`-Intervall interpolieren und daraus eine nichtparametrische Kurve des Szenendurchschlags bauen.
3. Den Szenendurchschlag abziehen und den relativen Kontrast zum lokalen Mittelwert berechnen.
4. Die Defektmaske aus getrimmter lokaler Rauschschwelle, Zusammenhangskomponenten und Richtung bauen.

Dieser Code bindet und portiert die IR-Korrektur von SANE nicht. Veröffentlichte Literatur und Produktseiten dienen als Hintergrund, um die physikalischen Grenzen von Film und Infrarot zu bestätigen. Eine Methode oder ein Prinzip zu übernehmen ist das eine, die Ausdrucksform von Code zu kopieren das andere. Das U.S. Copyright Office zieht dieselbe Grenze zwischen Methoden und Systemen und ihrer konkreten Ausdrucksform.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## Grenze zum SANE-Plugin

Die App hat kein `scanimage`, keine SANE-Header, keine Backend-Konfiguration und keinen gerätespezifischen Verarbeitungscode. Sie spricht mit dem installierten externen Programm nur über einen versionierten JSON/NDJSON-Vertrag. Die eigentliche SANE-Arbeit erscheint als eigenes Repository und eigene ausführbare Datei unter GPL-2.0-or-later.

Ein getrennter Prozess klärt die Lizenzfrage nicht allein. Die GNU-FAQ schreibt, Kommunikation über Pipes oder Kommandozeile sehe meist nach getrennten Programmen aus, die Antwort könne sich aber ändern, wenn die Kommunikation zu eng wird. Der Vertrag tauscht deshalb nur geräteunabhängige Anfragen, Fähigkeiten, Fortschritt und Angaben zu Ergebnisdateien aus und teilt keine SANE-Datenstrukturen.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [Scanner-Plugin-Struktur](../architecture/SCANNER_PLUGINS.md)

Die Release-Prüfung bestätigt noch einmal, dass weder Plugin noch SANE-Programm oder SANE-Bibliothek ins App-Bundle gerutscht sind. Die Plugin-Seite liefert eigene `LICENSE`, `COPYING`, den vollständigen zugehörigen Quelltext und Fremdhinweise.

## Mitgelieferte Ressourcen

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) legt erklärte Herkunft, Lizenz und SHA-256 jeder Ressource fest, die in App und Quellbaum geht.

| Gruppe | Herkunft | Was ausgeliefert wird |
|---|---|---|
| ScannerKit-TIFF | Vom Betreuer aufgenommenes und aufbereitetes Layoutmaterial | 4 TIFF-Dateien |
| App-Symbol | Projektgrafik vom Betreuer | Quell-PNG, Build-PNG, ICNS |
| Look-Presets | Für negaflow geschriebene Werte | 6 JSON-Dateien |
| Scannerprofile | Aus Scanmessungen des Betreuers erzeugt | Numerische Profile, ohne die Quellscans |

Die Kamera- und Farbraum-Metadaten in den TIFF-Dateien sind Containerangaben aus Aufnahme und Kodierung. `sourceProfiles` in einem Scannerprofil ist der logische Pfad des lokalen Messmaterials zum Zeitpunkt der Erzeugung, und diese Quellaufnahmen werden nicht ausgeliefert.

FILM-R-v2-Material wird nur während der Qualitätsmessung heruntergeladen. Die Bilder gelangen weder ins Repository noch in die App. DOI-Version, CC BY 4.0, Dateigrößen und Hashes stehen fest in [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json).

## DNG-Export

Die DNG-Schreiber (`DNGLinearWriter` in `negaflow-mac`, `dng_linear_export` in `negaflow-windows`) sind nach den Tag-Nummern und dem Farbmodell der von Adobe veröffentlichten Digital Negative Specification 1.6 neu geschrieben. Sie enthalten keinen Code aus dem Adobe DNG SDK und keinen Code aus LibRaw oder einem anderen DNG-Schreiber. Die Farbmatrizen werden aus den veröffentlichten Farbörtern von sRGB, Display P3 und Adobe RGB (1998) berechnet. Adobe bietet für Software, die DNG-Dateien liest oder schreibt, eine lizenzgebührenfreie Patentlizenz an. Dieses Produkt nutzt sie, und die Lizenz verlangt den folgenden Hinweis.

This product includes DNG technology under license by Adobe.

DNG ist eine Marke von Adobe Inc. Der Name bezeichnet nur das Dateiformat.

## Namen und Interoperabilität

Namen von Filmen, Scannern, Farbräumen, XMP-Namespaces und Produkten kennzeichnen Ziele und halten Dateien interoperabel. Von der Windows-Engine erzeugte Ausgabe-ICC-Profile tragen beschreibende Bezeichnungen (`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`) und eine `CC0 1.0 Universal`-Freigabe, damit exportierte Bilder keinen Profil-Urheberrechtsbeschränkungen unterliegen. Markenrechte oder eine Verbindung werden nicht behauptet. Der volle Umfang steht in [`TRADEMARKS.md`](../../../TRADEMARKS.md).

## Automatische Prüfungen und ihre Lücken

`python3 scripts/ci/verify-provenance.py` schlägt bei jedem dieser Punkte fehl.

- Eine mitgelieferte Ressource ohne Eintrag oder mit geändertem Hash
- C/C++/Objective-C, externe Pakete, Binärarchive oder ein Vendor-Baum in der App
- SANE-eigene Namen oder Spuren einer geprüften Fremdimplementierung im App-Code
- Eine Änderung, die das Release-Skript das SANE-Plugin in die App legen lässt
- FILM-R-Bildmaterial im Repository

Die Prüfung stoppt offensichtliche Rückschritte im aktuellen Baum. Sie belegt weder Ähnlichkeit gegenüber dem ganzen Internet noch Rechte an fotografischen oder Profil-Eingaben, Patente, Marken oder rechtliche Bewertungen einzelner Länder. Ändert sich eine Herkunft, prüfen Sie Erklärung und Hash zusammen. Ist etwas unklar, nehmen Sie die Ressource aus der Auslieferung und fragen Sie den Rechteinhaber oder eine Fachperson.
