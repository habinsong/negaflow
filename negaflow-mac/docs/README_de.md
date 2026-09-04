<p align="center">
  <img src="../Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for macOS</h1>

<p align="center">negaflow, nativ für macOS gebaut.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.4-EF8B26" alt="Version 1.1.4"></a>
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

## Was Sie brauchen

Zum Ausführen:

- macOS 14.0 oder neuer
- Apple Silicon oder Intel
- 8 GB Arbeitsspeicher für Kleinbild, mit 16 GB arbeitet es sich im Mittelformat angenehmer

Zum Bauen:

- Xcode 26 für die App
- Swift 5.9 oder neuer für Engine und CLI

## Installation

Laden Sie es von [Releases](https://github.com/habinsong/negaflow/releases) herunter.

| Datei | Unterstützte Macs |
|---|---|
| `negaflow-1.1.4-mac-universal.pkg` | Apple Silicon, Intel |
| `negaflow-1.1.4-mac-arm64.pkg` | Nur Apple Silicon |

Für die meisten passt das Universal-PKG. Es installiert nach `/Applications`. Wer selbst verschieben will, nimmt das DMG oder das ZIP von derselben Seite.

Die App ist nicht notarisiert, deshalb blockt macOS sie beim ersten Start. Erlauben Sie sie in den Systemeinstellungen unter Datenschutz und Sicherheit mit Trotzdem öffnen.

Bibliothek und Einstellungen liegen unter `~/Library/Application Support/negaflow`.

## Bauen

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow/negaflow-mac

# Release bauen und starten
bash scripts/run-app.sh

# Nur bauen, nicht starten
bash scripts/run-app.sh build
```

`run-app.sh` ruft `xcodebuild` auf, setzt das App-Bundle zusammen und signiert es lokal. Für Engine oder CLI allein genügt `swift build`.

Um Distributionsdateien zu erzeugen:

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

# Prüfung des gesamten Repositorys
bash scripts/ci-gate.sh
```

## Kommandozeile

Die macOS-Version bringt eine CLI mit.

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

# Profilliste und Selbsttest der Engine
.build/debug/negaflow list-scanner-profiles
.build/debug/negaflow selftest
```

`negaflow` ohne Argumente aufgerufen zeigt alle Optionen.

## Scanner

Die Scanner-Bedienelemente erscheinen erst, wenn ein Plug-in installiert ist. SANE-Geräte übernimmt [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), separat zu installieren.

## Module

| Modul | Aufgabe |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, Profile und Export |
| `ScannerKit` | Prüfung der Scannerfähigkeiten und Anbindung externer Plug-ins |
| `negaflowApp` | Bildschirme für Bibliothek, Entwickeln, Scannen und Export |
| `negaflowCLI` | Befehle für Entwickeln, Scannen, Benchmark und Selbsttest |

## Referenzbilder

`docs/verification/macos-golden` im Wurzelverzeichnis enthält die Bilder, die dieser Build erzeugt hat. Die Windows-Engine-Tests lesen sie und vergleichen Pixel für Pixel. Erzeugen Sie sie nur neu, wenn sich die macOS-Ausgabe ändern soll.

## Verwandte Dokumente

- [Unterschiede zwischen macOS und Windows](../../docs/de/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/de/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/de/product/GRAINMEND.md)
- [Produktarchitektur](../../docs/de/architecture/PRODUCT_ARCHITECTURE.md)
