# Herkunft von Code und Ressourcen

[Dokumentationsstart](../README.md)

Hier steht der Apache-2.0-Auslieferungsumfang der Negaflow-App. Das ist kein Rechtsgutachten,
sondern ein Herkunftsnachweis, damit Repository und Release-Artefakte erneut geprüft werden
können.

## Code

`Sources`, `Tests` und `scripts` sind Swift-, Python- und Shell-Code, geschrieben für Negaflow.
Die App enthält keinen C/C++/Objective-C-Quelltext, kein externes Paket, keine statische oder
dynamische Bibliothek und keinen fremden Quellbaum. Gebunden werden nur die Systemframeworks,
die Apple mit macOS ausliefert.

Die Filmumkehr nutzt die veröffentlichten Begriffe der Sensitometrie: Dichte, Fuß, Geradenteil,
Schulter. Kurven und Koeffizienten stammen aus den vier photometrischen Ankerpunkten von
Negaflow, nicht aus Formeln oder Konstanten eines fremden Programms. Gleichungen und Herleitung
stehen in [feste Printantwort](../reference/PRINT_RESPONSE.md).

GrainMend IR arbeitet in dieser Reihenfolge.

1. Den ganzzahligen Versatz zwischen RGB und IR eigenständig schätzen.
2. Getrimmte IR-Mittelwerte je `log(red)`-Intervall interpolieren und daraus eine nichtparametrische Kurve des Szenendurchschlags bauen.
3. Den Szenendurchschlag abziehen und den relativen Kontrast zum lokalen Mittelwert berechnen.
4. Die Defektmaske aus getrimmter lokaler Rauschschwelle, Zusammenhangskomponenten und Richtung bauen.

Dieser Code bindet und portiert die IR-Korrektur von SANE nicht. Veröffentlichte Literatur und
Produktseiten dienen als Hintergrund, um die physikalischen Grenzen von Film und Infrarot zu
bestätigen. Eine Methode oder ein Prinzip zu übernehmen ist das eine, die Ausdrucksform von Code
zu kopieren das andere. Das U.S. Copyright Office zieht dieselbe Grenze zwischen Methoden und
Systemen und ihrer konkreten Ausdrucksform.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## Grenze zum SANE-Plugin

Die App hat kein `scanimage`, keine SANE-Header, keine Backend-Konfiguration und keinen
gerätespezifischen Verarbeitungscode. Sie spricht mit dem installierten externen Programm nur
über einen versionierten JSON/NDJSON-Vertrag. Die eigentliche SANE-Arbeit erscheint als eigenes
Repository und eigene ausführbare Datei unter GPL-2.0-or-later.

Ein getrennter Prozess klärt die Lizenzfrage nicht allein. Die GNU-FAQ schreibt, Kommunikation
über Pipes oder Kommandozeile sehe meist nach getrennten Programmen aus, die Antwort könne sich
aber ändern, wenn die Kommunikation zu eng wird. Der Vertrag tauscht deshalb nur
geräteunabhängige Anfragen, Fähigkeiten, Fortschritt und Angaben zu Ergebnisdateien aus und
teilt keine SANE-Datenstrukturen.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [Scanner-Plugin-Struktur](../architecture/SCANNER_PLUGINS.md)

Die Release-Prüfung bestätigt noch einmal, dass weder Plugin noch SANE-Programm oder Bibliothek
ins App-Bundle gerutscht sind. Die Plugin-Seite liefert eigene `LICENSE`, `COPYING`, den
vollständigen zugehörigen Quelltext und Fremdhinweise.

## Mitgelieferte Ressourcen

[`Config/bundled-resource-provenance-v1.json`](../../../Config/bundled-resource-provenance-v1.json)
legt erklärte Herkunft, Lizenz und SHA-256 jeder Ressource fest, die in App und Quellbaum geht.

| Gruppe | Herkunft | Was ausgeliefert wird |
|---|---|---|
| ScannerKit-TIFF | Vom Betreuer aufgenommenes und aufbereitetes Layoutmaterial | 4 TIFF-Dateien |
| App-Symbol | Projektgrafik vom Betreuer | Quell-PNG, Build-PNG, ICNS |
| Look-Presets | Für Negaflow geschriebene Werte | 6 JSON-Dateien |
| Scannerprofile | Aus Scanmessungen des Betreuers erzeugt | Numerische Profile, ohne die Quellscans |

Die Kamera- und Farbraum-Metadaten in den TIFF-Dateien sind Containerangaben aus Aufnahme und
Kodierung. `sourceProfiles` in einem Scannerprofil ist der logische Pfad des lokalen
Messmaterials zum Zeitpunkt der Erzeugung, und diese Quellaufnahmen werden nicht ausgeliefert.

FILM-R-v2-Material wird nur während der Qualitätsmessung heruntergeladen. Die Bilder gelangen
weder ins Repository noch in die App. DOI-Version, CC BY 4.0, Dateigrößen und Hashes stehen fest
in [`Config/defect-corpus-film-r-v2.json`](../../../Config/defect-corpus-film-r-v2.json).

## Namen und Interoperabilität

Namen von Filmen, Scannern, Farbräumen, XMP-Namespaces und Produkten kennzeichnen Ziele und
halten Dateien interoperabel. Markenrechte oder eine Verbindung werden nicht behauptet. Der
volle Umfang steht in [`TRADEMARKS.md`](../../../TRADEMARKS.md).

## Automatische Prüfungen und ihre Lücken

`python3 scripts/ci/verify-provenance.py` schlägt bei jedem dieser Punkte fehl.

- Eine mitgelieferte Ressource ohne Eintrag oder mit geändertem Hash
- C/C++/Objective-C, externe Pakete, Binärarchive oder ein Vendor-Baum in der App
- SANE-eigene Namen oder Spuren einer geprüften Fremdimplementierung im App-Code
- Eine Änderung, die das Release-Skript das SANE-Plugin in die App legen lässt
- FILM-R-Bildmaterial im Repository

Die Prüfung stoppt offensichtliche Rückschritte im aktuellen Baum. Sie belegt weder Ähnlichkeit
gegenüber dem ganzen Internet noch Rechte an fotografischen oder Profil-Eingaben, Patente,
Marken oder rechtliche Bewertungen einzelner Länder. Ändert sich eine Herkunft, prüfen Sie
Erklärung und Hash zusammen. Ist etwas unklar, nehmen Sie die Ressource aus der Auslieferung und
fragen Sie den Rechteinhaber oder eine Fachperson.
