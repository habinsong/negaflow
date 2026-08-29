<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">negaflow, nativ für macOS entwickelt.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="Version 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-6E7781" alt="Apache 2.0"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <strong>Deutsch</strong>
</p>

<p align="center">
  <a href="../../README_de.md">Gemeinsame Dokumentation</a> ·
  <a href="../../negaflow-windows/docs/README_de.md">Windows</a>
</p>

---

## Voraussetzungen

Zum Ausführen:

- macOS 14.0 oder neuer
- Apple Silicon oder Intel
- 8 GB Arbeitsspeicher für Kleinbild, mit 16 GB arbeitet es sich im Mittelformat angenehmer

Zum Bauen:

- Xcode 26 für die App
- Swift 5.9 oder neuer für Engine und CLI

## Installation

Herunterladen unter [Releases](https://github.com/habinsong/negaflow/releases).

| Download | Mac |
|---|---|
| `negaflow-1.1.0-1-macOS-universal.pkg` | Apple Silicon und Intel |
| `negaflow-1.1.0-1-macOS-arm64.pkg` | Nur Apple Silicon |

Für die meisten passt das Universal-PKG. Öffnen, dem Installationsprogramm folgen, und die
App landet in `/Applications`. Auf derselben Seite liegen DMG und ZIP, falls Sie die App
lieber selbst verschieben.

Die App ist nicht notarisiert. Beim ersten Start blockiert macOS sie, und Sie geben sie in
den Systemeinstellungen unter Datenschutz und Sicherheit mit Trotzdem öffnen frei.

Bibliothek und Einstellungen liegen unter `~/Library/Application Support/negaflow`.

## Bauen

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Release bauen und starten
bash scripts/run-app.sh

# Nur bauen, nicht starten
bash scripts/run-app.sh build
```

`run-app.sh` ruft `xcodebuild` auf, setzt das App-Bundle zusammen und signiert lokal. Wer
nur an Engine oder CLI arbeitet, kommt mit `swift build` aus und braucht kein Xcode.

Für die Auslieferungsdateien:

```bash
bash negaflow-mac/scripts/build-release.sh
bash negaflow-mac/scripts/create-release-artifacts.sh
```

## Prüfungen

```bash
# Swift-Tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Release-Build der App
bash scripts/run-app.sh build

# Vollständige Prüfung des Repositorys
bash scripts/ci-gate.sh
```

## Kommandozeile

Die macOS-Version bringt neben der App eine vollständige CLI mit.

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

# Profile und Selbsttest der Engine
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

`negaflow` ohne Argumente zeigt alle Optionen.

## Scanner

Scanner-Bedienelemente bleiben verborgen, solange kein Plug-in installiert ist.
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) deckt
SANE-Geräte ab und wird separat installiert.

## Module

| Modul | Aufgabe |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, Profile, Export |
| `ScannerKit` | Scannerfähigkeiten prüfen und Plug-in anbinden |
| `negaflowApp` | Bibliothek, Entwicklung, Scan und Export |
| `negaflowCLI` | Entwickeln, scannen, messen, Selbsttest |

## Referenzbilder

Im Repository-Stammverzeichnis enthält `docs/verification/macos-golden` die Bilder, die
dieser Build gerendert hat. Die Tests der Windows-Engine lesen sie und vergleichen Pixel
für Pixel. So bleiben beide Versionen beieinander. Neu erzeugen sollten Sie sie nur, wenn
sich die macOS-Ausgabe absichtlich ändert.

## Verwandte Dokumente

- [Wo sich beide unterscheiden](../../docs/de/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/de/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/de/product/GRAINMEND.md)
- [Produktarchitektur](../../docs/de/architecture/PRODUCT_ARCHITECTURE.md)
