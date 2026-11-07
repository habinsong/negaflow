# Herkunft von Code und Ressourcen

[Dokumentationsstart](../README.md)

Dieses Dokument hält den Umfang der Apache-2.0-Verbreitung der negaflow-App fest. Es ist ein Herkunftsnachweis zur Prüfung von Repository und Release-Artefakten, keine Rechtsberatung.

## Code

Die Swift-, Python- und Shell-Integration in `negaflow-mac` ist für negaflow geschrieben.

Die Dekodierung von Negativ-Kamera-RAW nutzt eine festgelegte LibRaw-Revision, gebaut als austauschbare `libraw.dylib` unter CDDL-1.0. Beide Plattformen wenden dieselben drei Patches an:

- [`xtrans-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/xtrans-parallel-rows.patch): in `src/demosaic/xtrans_demosaic.cpp` hält Fuji-X-Trans-Kacheln in serieller Reihenfolge, verarbeitet die Zeilen innerhalb jeder Kachel parallel und führt den Grün-Grenzen-Durchlauf in Zeilengruppen aus, die sich nicht berühren
- [`mem-image-parallel-rows.patch`](../../../negaflow-mac/scripts/libraw/mem-image-parallel-rows.patch): in `src/postprocessing/mem_image.cpp` kopiert die Zeilen der Ausgabe-Bitmap parallel
- [`raw-decoders-parallel.patch`](../../../negaflow-mac/scripts/libraw/raw-decoders-parallel.patch): in `src/decoders/decoders_dcraw.cpp` gibt einfache verlustfreie JPEG-Daten (CR2) und Nikon-NEF-Daten an parallele Huffman-Decoder und dekodiert Sony-ARW2-Zeilen parallel

Die gepatchten Builds stimmen bei den getesteten RAW-Dateien mit dem ungepatchten seriellen Build überein.

Unter macOS ist LLVM OpenMP (libomp 20.1.8, Apache License v2.0 with LLVM Exceptions) statisch in die Bibliothek gelinkt. Die App enthält Quellarchiv, Patches, Build-Skript sowie Urheberrechts- und Lizenzdateien in `Contents/Resources/licenses/libraw/`. `native-preview-bridge.cpp` (Negaflow contributors, CDDL-1.0) enthält eine LibRaw-Unterklasse, die drei Pixelschleifen parallel mit byteidentischer Ausgabe ausführt, und die parallelen Huffman-Decoder, die der Decoder-Patch aufruft. Es wird kein LibRaw-Quelltext in den Apache-Quellbaum übernommen.

Windows verwendet dieselbe Upstream-Revision und dieselben Patches. Seine `native-preview-bridge.cpp` (CDDL-1.0) ergänzt Windows-spezifische Funktionen für lineare DNGs, seine übrigen Komponenten stehen in [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../../negaflow-windows/THIRD-PARTY-NOTICES.md). Die nur für Tests gedachte `CameraNativeRaw.dng` ist CC0-1.0-Material aus Eintrag 2204 von raw.pixls.us, durch die danebenliegende Quell-JSON erkennbar, und aus der Anwendung ausgeschlossen. Fehlt die ergänzende Hinweisdatei, warnen Build und Paketierung und laufen weiter. Die Upstream-Lizenzdateien und der zugehörige Quelltext bleiben enthalten.

Die Filminvertierung nutzt die veröffentlichten sensitometrischen Begriffe Dichte, Fuß, gerader Teil und Schulter. Die Kurven und Koeffizienten stammen aus negaflows vier photometrischen Ankern, nicht aus Formeln oder Konstanten eines fremden Programms. Gleichungen und Herleitung stehen in [Negativantwort](../reference/PRINT_RESPONSE.md).

Veröffentlichte Herstellerdatenblätter liegen drei Gruppen ausgelieferter Filmkonstanten zugrunde: den Dmin- und Dmax-Vorgaben je Filmart (`FilmStockDmin`), den spektralen und Kennlinien-Vorgaben für Schwarzweiß (`BWFilmProfile`) und den physikalischen Korn- und MTF-Parametern (`DigitalFilmPhysics`). Diese Zahlen sind ungefähre Ablesungen oder Anpassungen aus veröffentlichten technischen Datenblättern, und `FilmStockDmin` kennzeichnet jeden Eintrag als `datasheetCurve` oder `estimated`, damit die Herkunft sichtbar bleibt. Eine aus einem veröffentlichten Diagramm abgelesene Zahl ist eine Tatsache über den Film, keine Kopie fremden Codes oder Textes, und eine aus dem Scan gemessene Filmbasis hat immer Vorrang.

GrainMend IR läuft in dieser Reihenfolge:

1. Den ganzzahligen Versatz zwischen RGB und IR selbst schätzen.
2. Beschnittene IR-Mittelwerte je `log(red)`-Klasse interpolieren und daraus eine nichtparametrische Szenen-Streulichtkurve bilden.
3. Das Szenen-Streulicht abziehen, dann den relativen Kontrast zum lokalen Mittel berechnen.
4. Die Defektmaske aus einem beschnittenen lokalen Rauschschwellwert, zusammenhängenden Komponenten und der Ausrichtung bilden.

Dieser Code bindet die IR-Korrektur von SANE weder ein noch portiert er sie. Veröffentlichte Arbeiten und Produktseiten sind Hintergrund, um die physikalischen Grenzen von Film und Infrarot zu bestätigen. Eine Methode oder ein Prinzip zu übernehmen ist etwas anderes, als den Ausdruck von Code zu kopieren. Das U.S. Copyright Office zieht dieselbe Linie zwischen Methoden und Systemen und ihrem konkreten Ausdruck.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## Grenze zum SANE-Plug-in

Die App hat kein `scanimage`, keine SANE-Header, keine Backend-Konfiguration und keinen gerätespezifischen Verarbeitungscode. Sie spricht mit dem installierten externen Programm nur über einen versionierten JSON/NDJSON-Vertrag. Die eigentliche SANE-Arbeit wird als eigenes GPL-2.0-or-later-Repository und eigene ausführbare Datei ausgeliefert.

Ein eigener Prozess klärt die Lizenzfrage nicht von allein. Die GNU-FAQ sagt, Kommunikation per Pipe oder Befehlszeile sehe meist nach getrennten Programmen aus, die Antwort könne sich aber ändern, wenn die Kommunikation zu eng ist. Der Vertrag tauscht daher nur geräteunabhängige Anfragen, Fähigkeiten, Fortschritt und Ergebnisdateiinformationen aus und teilt keine SANE-Datenstrukturen.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [Scanner-Plugin-Struktur](../architecture/SCANNER_PLUGINS.md)

Die Release-Prüfung bestätigt erneut, dass sich kein Plug-in, keine SANE-Programmdatei und keine SANE-Bibliothek in das App-Bundle verirrt hat. Die Plug-in-Seite liefert ihre eigenen `LICENSE`, `COPYING`, den vollständigen zugehörigen Quelltext und die Hinweise zu Drittkomponenten mit.

## Mitgelieferte Ressourcen

[`Config/bundled-resource-provenance-v1.json`](../../../negaflow-mac/Config/bundled-resource-provenance-v1.json) legt die erklärte Herkunft, die Lizenz und den SHA-256 jeder Ressource fest, die in App und Quellbaum gelangt.

| Gruppe | Herkunft | Was ausgeliefert wird |
|---|---|---|
| ScannerKit TIFF | Vom Maintainer fotografiertes und aufbereitetes Layoutmaterial | 4 TIFF-Dateien |
| App-Symbol | Projektgrafik des Maintainers | Quell-PNG, Build-PNG, ICNS |
| Look-Vorgaben | Für negaflow geschriebene Werte | 6 JSON-Dateien |
| Scannerprofile | Aus Scanmessungen gebaut, die der Maintainer aufbewahrt | Zahlenprofile, ohne die Quellscans |

Die in den TIFF-Dateien sichtbaren Kamera- und Farbraum-Metadaten sind Containerangaben aus Aufnahme und Kodierung. `sourceProfiles` in einem Scannerprofil ist der logische Pfad des lokalen Messmaterials zur Build-Zeit, und diese Quellfotos werden nicht ausgeliefert.

FILM-R-v2-Material wird nur während der Qualitätsmessung heruntergeladen. Die Bilder gelangen nie in das Repository oder die App. DOI-Version, CC BY 4.0, Dateigrößen und Hashes sind in [`Config/defect-corpus-film-r-v2.json`](../../../negaflow-mac/Config/defect-corpus-film-r-v2.json) festgelegt.

## DNG-Export

Die DNG-Schreiber (`DNGLinearWriter` in `negaflow-mac`, `dng_linear_export` in `negaflow-windows`) sind aus den Tag-Nummern und dem Farbmodell der veröffentlichten Digital Negative Specification 1.6 von Adobe geschrieben. Sie enthalten keinen Code des Adobe DNG SDK und keinen Code aus LibRaw oder einem anderen DNG-Schreiber. Die Farbmatrizen werden aus den veröffentlichten Farbwerten von sRGB, Display P3 und Adobe RGB (1998) berechnet.

Adobe bietet eine lizenzgebührenfreie Patentlizenz für Software an, die DNG-Dateien liest oder schreibt. Dieses Produkt nutzt sie, und die Lizenz verlangt den folgenden Hinweis.

This product includes DNG technology under license by Adobe.

DNG ist eine Marke von Adobe Inc. Der Name bezeichnet nur das Dateiformat.

## Transformieren und Geraderichten

Der Bereich Transformieren und das Geraderichten an einer Linie sind für negaflow geschrieben und enthalten keinen fremden Code.

- Gerade Segmente entstehen, indem Pixel mit übereinstimmender Gradientenrichtung gruppiert werden und jede Gruppe entlang ihrer Hauptachse eine Gerade erhält. Kantenpixel nach Richtung zu gruppieren ist seit den 1980er Jahren veröffentlichte Technik.
- Der Löser behält Segmente innerhalb von 30° zur Senkrechten oder Waagerechten und dreht eine Kamera mit fester Brennweite, bis sie so nah an senkrecht und waagerecht liegen, wie der Modus erlaubt. Er minimiert mit dem Nelder-Mead-Simplexverfahren eine Summe von Winkelfehlern, in der Ausreißer weniger zählen. Kamerainterne Parameter, Manhattan-Richtungen und Fluchtpunkte schätzt er nicht.
- Der Modus Geführt nutzt nur die Hilfslinien, die der Benutzer zieht.

Adobe hält zwei gültige US-Patente zur automatischen Perspektivkorrektur von Fotos. Beide haben den Prioritätstag 27. April 2012, und Google Patents erwartet ihr Auslaufen 2033.

- [US 9,519,954](https://patents.google.com/patent/US9519954B2/en) beansprucht, eine Matrix interner Parameter, eine Orientierungsmatrix und Fluchtpunkte gemeinsam durch Optimierung einer Energiefunktion zu schätzen. negaflow schätzt nichts davon.
- [US 9,582,855](https://patents.google.com/patent/US9582855B2/en) hat breitere unabhängige Ansprüche: eine Homographie oder ebene Transformation zu berechnen, die Linien an den Bildachsen ausrichtet, gestützt zumindest teilweise auf Kriterien menschlicher Wahrnehmung. Auch der Löser von negaflow richtet Linien an den Bildachsen aus. Die Idee war vor 2012 öffentlich. ShiftN von Marcus Hebel erschien 2006 und erreichte im Oktober 2008 Version 3.4. Es suchte fast senkrechte gerade Kanten und optimierte eine Perspektivtransformation, die sie parallel und am Rahmen ausgerichtet machte ([ShiftN](https://www.shiftn.de/ShiftN_functionality.html), [Versionsgeschichte](https://newsgroup.xnview.com/viewtopic.php?p=57759)). Code von ShiftN wurde nicht verwendet.

Ob ein Anspruch eine bestimmte Umsetzung erfasst, ist eine Rechtsfrage, die dieses Dokument nicht entscheidet.

## Namen und Interoperabilität

Film-, Scanner-, Farbraum-, XMP-Namensraum- und Produktnamen bezeichnen Ziele und halten Dateien interoperabel. Die von der Windows-Engine erzeugten Ausgabe-ICC-Profile tragen beschreibende Bezeichnungen (`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`) und eine `CC0 1.0 Universal`-Widmung, sodass exportierte Nutzerbilder keine Urheberrechtsbeschränkung des Profils tragen. Es wird weder Markeninhaberschaft noch eine Verbindung beansprucht. Der vollständige Umfang steht in [`TRADEMARKS.md`](../../../TRADEMARKS.md).

## Automatische Prüfungen und was sie übersehen

`python3 scripts/ci/verify-provenance.py` (aus `negaflow-mac/` aufzurufen) schlägt in jedem dieser Fälle fehl:

- Eine mitgelieferte Ressource, die nicht eingetragen ist oder deren Hash sich geändert hat
- C/C++/Objective-C, externe Pakete, Binärarchive oder ein Vendor-Baum in der App
- Nur bei SANE vorkommende Namen oder Spuren einer geprüften externen Implementierung im App-Code
- Eine Änderung, durch die das Release-Skript das SANE-Plug-in in die App legt
- FILM-R-Bildmaterial im Repository

Die Prüfung stoppt offensichtliche Rückschritte im aktuellen Baum. Sie belegt weder Ähnlichkeit mit dem gesamten Internet noch Rechte an Foto- oder Profileingaben, noch Patente, Marken oder rechtliche Ergebnisse in irgendeinem Land. Ändert sich eine Herkunft, prüfen Sie die Erklärung zusammen mit dem Hash. Ist sie unklar, nehmen Sie die Ressource aus dem Release und fragen den Rechteinhaber oder einen Fachmann.
