<p align="center">
  <img src="Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow App-Symbol">
</p>

<h1 align="center">negaflow</h1>

<p align="center">Eine macOS-App für den gesamten Scan- und Entwicklungsprozess analoger Filme</p>

<p align="center">
  <a href="docs/product/PROJECT_STATUS.md"><img src="https://img.shields.io/badge/status-1.0.0%20release-EF8B26" alt="Veröffentlichungsstatus"></a>
  <a href="#voraussetzungen"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 oder neuer"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache-2.0-Lizenz"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <strong>Deutsch</strong>
</p>

---

negaflow ist eine macOS-App zum Importieren, Invertieren und Entwickeln von Filmscans und Kamera-Reproduktionen.<br>
Sie verarbeitet Farb- und Schwarzweißfilm, Negative und Positive.<br>
Bearbeitungen werden getrennt von der Originaldatei gespeichert.<br>
Die App begleitet den digitalen Film-Workflow von der Bibliothek über die Entwicklung bis zum Druck.

Die Entwicklungs-Engine heißt **Chroma Engine**.<br>
Die Staub- und Kratzerreparatur heißt **GrainMend**.<br>
Für Entwicklung und Export reicht eine importierte Bilddatei.<br>
Scanner-Funktionen erscheinen nur, wenn ein separates Plug-in installiert ist.

> Die Technik entwickelt sich weiter, doch der Ablauf rund um die analoge Fotografie ist stehen geblieben, obwohl Film wieder beliebter wird.<br>
> Ohne einen klassischen Dunkelkammerabzug muss Film erst digitalisiert werden, bevor die meisten von uns das Bild sehen und teilen können.<br>
> Genau dieser Teil wird kleiner, weil Labore und Entwicklungsdienste verschwinden und damit auch die Auswahl.
> <br>
> Das Projekt entstand aus Problemen, die mir in verschiedenen Arbeitsabläufen begegnet sind, und aus Funktionen, die ich dort vermisst habe.<br>
> Meine Erfahrungen mit Kleinbild- und Mittelformatfilm bilden die Grundlage; jeden Teil habe ich selbst von Grund auf entwickelt.<br>
> Anfangs war es ein kleines Projekt nur für mich.<br>
> Inzwischen ist **negaflow** mehr daraus geworden.<br>
> So ein Werkzeug muss vor allem zuverlässig sein, leicht von der Hand gehen, schnell reagieren und Routinearbeit ordentlich erledigen.<br>
> **negaflow** wird unabhängig als native macOS-App entwickelt und verbindet Abläufe aus Filmlaboren mit der Arbeit zu Hause.
>
> Abgeschlossene Prüfungen stehen im [Projektstatus](docs/product/PROJECT_STATUS.md). <br>
> **Für diesen Sommer, 200 Jahre nach Niépces erster Fotografie.**

---

## Installation

Laden Sie die aktuelle Version unter [GitHub Releases](https://github.com/habinsong/negaflow/releases) herunter.<br>
Für die meisten Macs ist das Universal-PKG vorgesehen.

| Download | Unterstützte Macs |
|---|---|
| `Negaflow-1.0.0-1-macOS-universal.pkg` | Apple Silicon und Intel |
| `Negaflow-1.0.0-1-macOS-arm64.pkg` | Nur Apple Silicon |

1. Laden Sie das passende PKG herunter.
2. Öffnen Sie es und folgen Sie Installer.
3. Starten Sie **Negaflow** aus `/Applications`.

Das PKG installiert `Negaflow.app` direkt unter `/Applications`.<br>
DMG- und ZIP-Dateien für die manuelle Installation stehen auf derselben Release-Seite bereit.<br>
Auf GitHub veröffentlichte Dateien werden mit einer Developer ID signiert und von Apple notarisiert.

> Für einen echten Scanner ist ein separates Scanner-Plug-in erforderlich.<br>
> SANE-Scanner verwenden [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).

## Funktionen

- Messung der Filmbasis und Invertierung von Farb- oder Schwarzweißfilm
- Belichtung, Kontrast, Kurven, HSL, Farbkorrektur und Schwarzweiß-Tonung
- Schärfung, Rauschminderung, Korn, Vignette und Halation
- Staub- und Kratzerreparatur mit GrainMend
- Filme, Ordner, Sammlungen, Bewertungen, Stapel und virtuelle Kopien
- Zoom, Zuschnitt, Drehung, Vergleichsansichten, Histogramm und Clipping-Anzeige
- JPEG- und 16-Bit-TIFF-Export, ICC-Profile und Drucklayouts

## Chroma Engine

Chroma Engine ist die Film-Invertierungs- und Entwicklungs-Engine im Modul `Chromabase`.<br>
Vor der Invertierung eines Negativs misst sie die unbelichtete Filmbasis.<br>
Falls die automatische Messung nicht passt, kann ein Bereich mit der Pipette gewählt oder ein RGB-Wert eingegeben werden.

Der Ausgangszustand ist `MAIN` mit manuellen Korrekturen.<br>
Automatischer Tonwert, automatischer Weißabgleich, automatische Tonwertspreizung und automatische Farbe werden nur auf ausdrücklichen Aufruf angewendet.

Entwicklungsziele:

- `MAIN`: normale Entwicklung
- `PRINT`: Ausgabe über ein Drucker-ICC-Profil
- `HS`, `SP`: Entwicklung im Minilab-Stil
- `F135`, `HR`: Stile der entsprechenden Gerätefamilien
- `EXPIRED`: Rettung alten Films

Die Ausgabe unterstützt sRGB, Display P3, Adobe RGB und eigene RGB-ICC-Profile.<br>
Die Reihenfolge von Invertierung und Farbverarbeitung steht unter [Chroma Engine](docs/product/CHROMA_ENGINE.md).

## GrainMend

GrainMend repariert Staub, Pinholes, Kratzer und Emulsionsschäden.<br>
Der Name `GrainMend` bleibt in allen Sprachen gleich; nur Werkzeugnamen und Hilfetexte werden übersetzt.

| Werkzeug | Aufgabe |
|---|---|
| Auto | Findet und repariert Fehler im ganzen Bild. |
| Geführt | Sucht Fehler in einem markierten Bereich. |
| Pinsel | Lässt den zu reparierenden Bereich direkt übermalen. |
| Kopierstempel | Kopiert Pixel von einem gewählten Quellpunkt. |

Auto und Geführt füllen Fehler mit Textur aus der Umgebung.<br>
Dabei prüfen sie auch Richtung und benachbarte Strukturen, damit Linien oder Gitter im Motiv nicht als Kratzer verschwinden.<br>
Jedes Ergebnis bleibt als GrainMend-Ebene erhalten.<br>
Stärke, Maskenanzeige, Aktivierung und Löschen lassen sich einzeln steuern.

Auto beseitigt die üblichen Fehler im ganzen Bild.<br>
Werden zu viele Kandidaten erkannt, stoppt Auto ohne Bildänderung und verweist auf einen kleineren Bereich mit Geführt.<br>
Geführt ist für die unterschiedlichen Staubspuren gedacht, die beim Scannen entstehen.<br>
Der Pinsel kümmert sich um übersehene Stellen; der Kopierstempel überträgt eine selbst gewählte Quelle direkt an das Ziel.

Wenn das Scanner-Plug-in einen Infrarotkanal liefert, kommt auch dessen Erkennung in dieselbe Bearbeitungshistorie.<br>
GrainMend RGB arbeitet anders als hardwarebasierte Infrarotreinigung.<br>
GrainMend IR ist keine Implementierung oder Kompatibilitätsfunktion für Digital ICE, iSRD oder SRDx.

Umsetzung sowie Qualitäts- und Leistungskontrollen stehen unter [GrainMend](docs/product/GRAINMEND.md).

## Filmprofile

Die App enthält 15 Scannerprofile aus Filmmaterial, das der Projektentwickler selbst aufgenommen hat.<br>
Zusammen enthalten sie 928 Bildbeobachtungen.<br>
Alle Profile haben derzeit den Stand `realOnly`: Sie beruhen auf echten Scans, haben aber noch keine unabhängige Genauigkeitsprüfung mit Referenzpaaren bestanden.

Ein Profil wird nicht allein anhand des Scanner-Namens angewendet.<br>
Es muss manuell gewählt werden.<br>
Die App prüft außerdem die SHA-256-Werte jedes Profils und des Manifests.

`928` ist die Summe der Beobachtungen aller Profilgruppen, nicht die Zahl unterschiedlicher Fotos.<br>
Derselbe Film kann in mehreren Scannergruppen gezählt sein.<br>
Ich habe alle 928 Ausgangsscans selbst geprüft und Dateien mit Fehl- oder Nichterkennungen vor der Messung ausgeschlossen.<br>
Daten und Erzeugung sind unter [Filmprofile](docs/product/FILM_PROFILES.md) beschrieben.

## Grundlegender Ablauf

1. Bilddatei importieren oder mit einem installierten Plug-in scannen.
2. Filmtyp wählen und Filmbasis messen.
3. Farbe und Ton in Chroma Engine einstellen.
4. GrainMend auf die benötigten Bilder anwenden.
5. Ergebnis in Vergleichsansichten und Histogramm prüfen und anschließend drucken oder exportieren.

Die Oberfläche ist für Menschen gebaut, die wirklich mit Fotos arbeiten, nicht als beliebiger KI-generierter Entwurf.<br>
Wer Fotografie als Hobby betreibt, soll sich darin ohne Umwege zurechtfinden.

## Aus dem Quellcode bauen

### Voraussetzungen

- macOS 14.0 oder neuer
- GUI-App: Xcode 26
- Engine und CLI: Swift 5.9 oder neuer
- Hardware-Scan: separates Scanner-Plug-in

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Release-App bauen und starten
bash scripts/run-app.sh

# Nur bauen, nicht starten
bash scripts/run-app.sh build
```

Die GUI-App wird mit `xcodebuild` gebaut.<br>
`scripts/run-app.sh` baut den Code, erstellt das App-Bundle und signiert es lokal.<br>
Für Engine und CLI allein genügt `swift build`.

## CLI

```bash
swift build

# Scanner finden
.build/debug/negaflow detect
.build/debug/negaflow capabilities <scannerID>

# Entwickeln
.build/debug/negaflow develop in.tiff out.jpg --look rich-neutral --target main

# GrainMend
.build/debug/negaflow develop scan.tif out.jpg --defects 1
.build/debug/negaflow defect-bench ./scans --out ./report

# Profile auflisten und Engine prüfen
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

Alle Optionen erscheinen, wenn `negaflow` ohne Argumente ausgeführt wird.

## Scanner

negaflow leitet Funktionen nicht aus einem Scanner-Modellnamen ab.<br>
Es verwendet nur Auflösungen, Bittiefen, Scanbereiche, Belichtungssteuerung und IR-Unterstützung, die das Plug-in meldet.

SANE-Geräte betreut das separate GPL-Projekt [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).<br>
Das Plug-in läuft in einem eigenen Prozess und spricht über JSON mit der App.<br>
Die Haupt-App enthält und verlinkt keinen SANE-Code.

## Repository

| Modul | Aufgabe |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, Profile und Export |
| `ScannerKit` | Scanner-Funktionen und Verbindung externer Plug-ins |
| `negaflowApp` | Oberfläche für Bibliothek, Entwicklung, Scan und Export |
| `negaflowCLI` | Befehle für Entwicklung, Scan, Benchmarks und Selbsttest |

Der Datenfluss zwischen den Modulen steht in der [Produktarchitektur](docs/architecture/PRODUCT_ARCHITECTURE.md).

## Entwicklungsprüfungen

```bash
# Swift-Tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# GUI-Release-Build
bash scripts/run-app.sh build

# Vollständige Repository-Prüfung
bash scripts/ci-gate.sh
```

Automatisierte Tests prüfen Codeverhalten und Regressionen.<br>
Scanner-spezifisches Verhalten, endgültige Bildqualität, Signatur und Notarisierung werden getrennt geprüft.

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [Chroma Engine](docs/product/CHROMA_ENGINE.md) | Filmbasis, Invertierung, Farbe und Entwicklungsfolge |
| [GrainMend](docs/product/GRAINMEND.md) | Erkennung, Reparatur, IR, Historie, Leistung und Qualität |
| [Filmprofile](docs/product/FILM_PROFILES.md) | Analyse der Quelldaten und Profilerzeugung |
| [Produktarchitektur](docs/architecture/PRODUCT_ARCHITECTURE.md) | App, Engine, Scanner, Speicher und Export |
| [Projektstatus](docs/product/PROJECT_STATUS.md) | Implementierung, Messwerte und offene Prüfungen |
| [Checkliste für reale QA](docs/validation/REAL_QA_CHECKLIST.md) | Prüfungen an echter Hardware und am Bildschirm |

## Lizenz

Das negaflow-Hauptprojekt wird unter der [Apache License 2.0](LICENSE) veröffentlicht.

Negaflow ist weder mit Kodak, Fujifilm, Noritsu, LaserSoft Imaging noch mit anderen Markeninhabern verbunden oder von ihnen unterstützt.<br>
Produktnamen dienen nur zur Benennung eines Mess- oder Kompatibilitätsziels.<br>
Siehe [Markenhinweis](TRADEMARKS.md).
