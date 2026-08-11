# Projektstand

[Dokumentationsstart](../README.md)

Dieses Dokument hält fest, was gebaut und was geprüft ist.
Das README erklärt Produkt und Bedienung, die Dokumente unter docs tragen die genauen
Spezifikationen und Entscheidungen.

## Grunddaten

| Punkt | Aktueller Wert |
|---|---|
| Version | `1.0.6` |
| Build | `1` |
| Betriebssystem | macOS 14 oder neuer |
| Ablauf | Import oder Scan → Entwicklung → Export |
| Standardentwicklung | `main`, manuelle Korrektur |
| Originale | Originaldateien und fremde Sidecar-Dateien bleiben unverändert |

> [!WARNING]
> Die Angabe `1.0.6` und ein erfolgreicher Build heißen nicht, dass Scannerkompatibilität,
> endgültige Bildqualität, externe Signatur oder Notarisierung bestätigt sind. Echte Hardware und
> die Freigabe zur Auslieferung stehen getrennt in der Checkliste weiter unten.

## Gebaut und automatisch geprüft

- Nicht zerstörender Katalog, Sidecar-Dateien, virtuelle Kopien, Sammlungen, Filme, Bewertungen, Auswahl und Ausschluss
- Doppelter Import, Originale neu verknüpfen, aus der Bibliothek entfernen, Originale in den Papierkorb legen
- Katalogprüfung, Prozesssperre, Wiederherstellungssperre, Sicherungsgenerationen, Wiederherstellungsprobe, Neuentwicklung ausgewählter Bilder
- Gemeinsamer Pfad für Entwicklung und Export, Metadaten, Verarbeitungshistorie, Bearbeitungsverlauf, Ausgabe mehrerer Dateien
- JPEG ab 95 % Qualität ohne Chroma-Unterabtastung kodiert, PNG wahlweise mit 8 oder 16 Bit, und ein Schnellexport mit eigenen Kodiereinstellungen
- Notierte Kamera, Objektiv, Film und Belichtung werden in die Exportdatei geschrieben; in den EXIF hat die Aufnahmekamera Vorrang vor dem Scanner
- Rollennotizen füllen nur die leeren Felder eines Bildes, und Rollencode, Film und Kamera stehen als Dateinamen-Token bereit
- Ausgelagerte iCloud-Originale werden vor einem Export bereitgestellt, mit Exportprüfung in den Stufen Standard und Streng
- Bildauswahl in der Flachbett-Vorschau, festgehalten am Seitenverhältnis des gewählten Filmformats
- Eine niederfrequente Beobachtungsgrenze, die die Export-Schaltfläche mit Entwicklungs- und Nachbearbeitungsstand aktualisiert
- Finden und Freigeben von Scanner-Plugins, Fähigkeitsprüfung, Protokoll v1/v2, Abbruch, Zeitgrenzen, Ausgabeobergrenzen
- Prüfung von Eigentümer und Rechten des Plugins sowie der temporären Ausgabe
- Abgleich zwischen dem Scanner-JSON der CLI und den in der App gezeigten Fähigkeiten
- Bedienungshilfen, Auswahlzustand, Textgröße, Anpassung an Fenstergrößen, Wiederherstellen des Bildschirmzustands
- Vergleichs- und Übersichtsansicht, Fotostapel, Prüfung von Dublettenkandidaten
- BagIt-Erhaltungsarchiv mit Originalen, IR, GrainMend-Einträgen und Verknüpfungen virtueller Kopien
- Render-Protokoll v3, das Quelle und Ausgabe über SHA-256 verbindet
- IR-Ausrichtungsdiagnose und Grenzen der Filmverträglichkeit
- Wiederholte Messung des Scannerrauschens und die getrennte Prüfspezifikation
- Aufräumen des Bildcaches bei Speicherdruck
- Strenge Swift-Nebenläufigkeitsdiagnose in der CI
- Importfortschritt, standardmäßig ausgeschaltete automatische Entwicklung und gespeicherte Einstellung
- Gespeicherter Ordnerzustand, internes Scrollen der Fotoliste in Entwickeln und gleiches Entfernen aus der Bibliothek
- Verschieben zwischen importierten, von der App erstellten und Scannerordnern mit nummerierten Namen bei Kollision
- Finder-Ereignisse für Verschieben und Umbenennen, erneute Verknüpfung per Lesezeichen und Lesen nur geänderter Ordner
- Prozess und Ziel pro Ordner, auch für bereits entwickelte Fotos, mit Fortschrittsanzeige
- Vorgaben und Mehrfach-Kopieren/Einfügen einschließlich Prozess, Ziel, Korrekturen, Beschnitt und Ausrichtung
- Entwickelte Scanner-Vorschaubilder in Entwickeln und Druck für alle unterstützten Filmtypen
- Ohne Scanner-Plug-in bleibt die gemeinsame Seitenleiste verborgen, während erneute Suche und Simulator erreichbar bleiben
- Große Kataloge vermeiden lange automatische Sprünge, erzeugen Zeilen verzögert und bieten einen optionalen 2.000-Bilder-Echtpixel-Stresstest
- Profilvorschau für jede Paketplatzierung und Drucker-ICC-Umwandlung der ganzen zusammengesetzten Seite
- Trennung, die das C-Print-Proofprofil aus Entwickeln und Lieferdateien heraushält
- Sieben Drucklayouts: Einzelbild, Kontaktbogen, Bildpaket, Benutzerpaket, Cyanotypie, Glasplatte und Gelatinesilber
- Untereinander angezeigte Seiten für Mehrfachauswahl in Einzellayouts und gleiche historische Darstellung in Export und Schnellexport
- Fertige Seitenzahlen: 39 Fotos ergeben eine 6 × 7-Kontaktbogenseite, 10 Seiten mit je vier Bildern, eine voreingestellte Benutzerpaketseite oder 39 Einzeldateien
- Wiederverwendung der Vorschau, auf zwei bis vier Quellen begrenzte Vorbereitung, Core-Image-Graph bis zur Seite und 512 MiB Quellrasterbudget pro Seite
- Lokalisierter Info-Dialog mit fetter Niépce-Zweihundertjahrfeier zwischen Produktname und Version

## Katalog

Der Hauptspeicher ist `library.sqlite`.
Ein vorhandenes `library.json` wird schreibgeschützt geöffnet, auf Gesundheit geprüft, gesichert und
in ein temporäres SQLite überführt.
Erst wenn Inhalt beider Kataloge und SQLite-Integrität zusammenpassen, wird umgeschaltet.

Passt beim Fortsetzen unterbrochener Arbeit ein Beleg nicht, scheitert es im geschlossenen Zustand.
JSON bleibt das übertragbare Austauschformat für Sicherung und Archiv, aber zwei Hauptspeicher
laufen nie gleichzeitig.

Die Einzelheiten stehen in [Katalogspeicherung](../architecture/CATALOG_STORAGE.md).

## Scanner

In diesem Repository liegen nur ein geräteunabhängiger Host für externe Prozesse und die
JSON-Spezifikation.
SANE-Umsetzung, Abhängigkeiten, Konfiguration und Auslieferungsdateien gehören nicht dazu.
Dieser Code liegt im separaten GPL-Projekt
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).

Die App zeigt nur, was das installierte Plugin gemeldet hat.
Aus einem Modellnamen werden keine Fähigkeiten abgeleitet.
Solange Sie nicht die Demo wählen, springt kein erfundener Scanner ein.

Genaue Spezifikationen:

- [Scanner-Plugin-Struktur](../architecture/SCANNER_PLUGINS.md)
- [Scanner-CLI-JSON](../reference/CLI_JSON.md)

## Build und Auslieferung

<details>
<summary>Lokale Prüfungen und Auslieferungsbefehle</summary>

Lokale Prüfungen:

```bash
bash scripts/ci-gate.sh
bash scripts/run-app.sh build
bash scripts/run-gui-e2e.sh  # braucht den Automation Mode von macOS
```

Auslieferungsdateien bauen:

```bash
bash scripts/build-release.sh
```

</details>

`scripts/run-app.sh build` setzt nur die App zusammen. Es startet weder die App noch einen
UI-Test-Runner; GUI-Automatisierung beginnt nur über den getrennten Befehl
`scripts/run-gui-e2e.sh`.

Am 31. Juli 2026 bestand der aktuelle Arbeitsbaum den Swift-Build mit strenger Nebenläufigkeit,
1.800 parallele Tests und 9 zeitkritische serielle Tests. `scripts/run-app.sh build` erzeugte
außerdem eine neue arm64-Release-App; die UUIDs von Programm und dSYM stimmen überein. Dies ersetzt
keine Prüfung der GUI, echter Scanner, Developer-ID-Signatur oder Notarisierung.

Ein Lauf von `build-release.sh` baut die Apps für Apple Silicon (`arm64`) und Universal (`arm64`,
`x86_64`) und schreibt ZIP, PKG, DMG, dSYM und die SHA-256-Liste.
Lokal wird ad hoc signiert.
Für die echte Auslieferung braucht es sowohl eine Developer-ID-Application- als auch eine
Developer-ID-Installer-Signatur.

Der manuelle Workflow `Distribution` nutzt die geschützte Developer ID und den App-Store-Connect-
API-Schlüssel.
Er schickt App-Archiv, DMG und PKG an Apple, heftet das Notarisierungsticket an und prüft danach
Prüfsummen und Gatekeeper erneut.
Ohne echten Workflow-Lauf und Antwort von Apple wird nichts über externe Signatur und Notarisierung
behauptet.

## Leistungsmessungen

Die Leistungsprüfungen decken Katalog, Bibliothekssuche, Regelung bei hoher Auflösung,
GrainMend-Bereichsarbeit und einen Film mit echten Pixeln ab.

Jüngste Release-Messungen auf einem Mac:

| Vorgang | Ergebnis |
|---|---:|
| JSON-Lesen 50.000 Bilder p95 | etwa 7,4 s |
| SQLite-Lesen 50.000 Bilder p95 | etwa 7,4 s |
| SQLite-Commit 50.000 Bilder p95 | etwa 3,7 s |
| SQLite-Commit ohne Änderungen p95 | etwa 3,9 s |
| Filter und Namenssortierung bei 50.000 Bildern | etwa 158 ms |
| Schnellvorschau für 48 Bilder | etwa 10,6 s, max. RSS etwa 504 MiB |
| Entwicklung von 48 Bildern | etwa 20,9 s, max. RSS etwa 1.012 MiB |

Am 31. Juli 2026 verwendete der optionale `PrintExportPerformanceTests`-Lauf auf diesem Mac
39 getrennte TIFF-Quellen mit 4.000 × 3.000 Pixeln und 300-DPI-JPEG-Ausgabe:

| Druckausgabe | Export | Schnellexport |
|---|---:|---:|
| 6 × 7-Kontaktbogen, 39 Fotos → 1 Datei | 1,177 s | — |
| Einzelbild, 39 Fotos → 39 Dateien | — | 5,234 s |
| Cyanotypie, 39 Fotos → 39 Dateien | 5,467 s | 5,659 s |
| Glasplatte, 39 Fotos → 39 Dateien | 5,960 s | 6,278 s |
| Gelatinesilber, 39 Fotos → 39 Dateien | 6,732 s | 6,697 s |

Für andere Macs sagen diese Werte nichts zu. Neue Messungen entstehen mit diesem Befehl.

```bash
bash scripts/run-performance-suite.sh
```

Die Grenzen für macOS 26 arm64 in `Config/performance-budget-v1.json` sind weite Obergrenzen, um
große Rückschritte zu fangen.
Sie einzuhalten heißt nicht, dass sich jede Verzögerung gut anfühlt.

## GrainMend-Messungen

Das FILM-R-v2-Material ist über DOI, 44 Paare, 437.570.872 Byte und die MD5-Angaben von Figshare
festgelegt.

Der automatische Pfad der Auslieferung läuft mit Empfindlichkeit 0.7 und einer Sicherheitslinie
gegen Überdetektion.
Hier gegen die bisherige Regressionsbasis 3.0.

| Kennzahl | Bisherige Basis 3.0 | Sicheres Auto 0.7 |
|---|---:|---:|
| Gewichtete verschlechterte Pixel | 0,792 % | 0,017 % |
| Gewichtete geänderte Pixel | 0,794 % | 0,043 % |
| Mittlere PSNR-Änderung | -1,688 dB | +0,466 dB |
| Schlechteste PSNR-Änderung | -18,952 dB | -1,338 dB |
| Bilder besser / schlechter / gleich | 11 / 33 / 0 | 34 / 6 / 4 |

Neben der beobachteten Regressionsprüfung gelten absolute Untergrenzen: mittlerer und medianer PSNR
bei 0 dB oder besser, höchstens 10 verschlechterte Bilder und ein schlechtester Fall von
-1,5 dB oder besser. Die automatische Sicherheitslinie stoppte die Reparatur bei 3 Bildern; in
diesem Fall verweist die App auf Guided.

FILM-R prüft allein den automatischen Pfad von GrainMend RGB.
Es taugt nicht als Beleg für Gleichwertigkeit mit Hardware-IR oder für die RGB/IR-Ausrichtung eines
echten Scanners.

Der manuelle Workflow `GrainMend corpus` holt die 44 Paare, führt den Release-Standardpfad aus,
macht die Regressionsprüfung und lädt den Bericht hoch.

## Was automatische Prüfungen nicht klären

- Endgültige Oberflächenprüfung bei unterstützten Fenstergrößen und Bedienungshilfen
- Echte Plugins und Scanner
- Echte Negative und IR-Bildqualität
- Developer ID, Notarisierung, Gatekeeper, Installation auf einem frischen Mac
- Leistung auf allen unterstützten Macs

Das Endergebnis auf dem Bildschirm und die echte Hardware liegen beim Nutzer.
Ein erfolgreicher Build ersetzt das nicht; die Ergebnisse gehören in die
[Checkliste für echte Geräte](../validation/REAL_QA_CHECKLIST.md).

## Welches Dokument gilt wofür

| Thema | Maßgebliches Dokument |
|---|---|
| Aktuelle Umsetzung und Prüfungen | Dieses Dokument |
| Bibliothek, Ordnerentwicklung, Einstellungsübertragung und Print | [Von der Bibliothek zum Print](WORKFLOW.md) |
| Spezifikation des Scanner-Hosts | [Scanner-Plugin-Struktur](../architecture/SCANNER_PLUGINS.md) |
| Scanner-CLI-JSON | [Scanner-CLI-JSON](../reference/CLI_JSON.md) |
| Art der Katalogspeicherung | [Katalogspeicherung](../architecture/CATALOG_STORAGE.md) |
| Freigabekriterien für Scannerprofile | [Qualitätsprüfung der Scannerprofile](../reference/PROFILE_QUALITY_GATE.md) |
| Umsetzung und Grenzen von GrainMend | [GrainMend](GRAINMEND.md) |
| Freigabe von Endergebnis und echter Hardware | [Checkliste für echte Geräte](../validation/REAL_QA_CHECKLIST.md) |
| Installation und Bedienung | Die README-Dateien im Wurzelverzeichnis |
