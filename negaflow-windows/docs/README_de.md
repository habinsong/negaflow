<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, nativ für Windows gebaut.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.3-EF8B26" alt="Version 1.1.3\"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 oder neuer"></a>
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
  <a href="../../negaflow-mac/docs/README_de.md">macOS</a>
</p>

---

## Was Sie brauchen

Zum Ausführen:

- Windows 11 24H2 (Build 26100) oder neuer, 64 Bit
- 8 GB Arbeitsspeicher für Kleinbild, mit 16 GB arbeitet es sich im Mittelformat angenehmer

Zum Bauen:

- Visual Studio 2022 mit der Workload Desktopentwicklung mit C++
- Windows 11 SDK (10.0.26100 oder neuer)
- .NET 10 SDK
- CMake 3.28 oder neuer
- Python 3.11 oder neuer für die Icon- und Ressourcenskripte

Auf Arm64-Rechnern läuft es ebenfalls. Arm64-Releases sind weniger geprüft als x64.

## Installation

Laden Sie `negaflow-1.1.3-win-x64.exe` von [Releases](https://github.com/habinsong/negaflow/releases) und starten Sie es.

Administratorrechte sind nicht nötig. SmartScreen warnt beim ersten Start einmal. Klicken Sie auf Weitere Informationen und führen Sie es aus.

Entfernt wird es über `negaflow deinstallieren` im Startmenü oder die App-Liste in den Einstellungen. Bibliothek und Fotos bleiben unangetastet.

## Bauen

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# C++-Engine bauen
.\scripts\build.ps1 -Preset x64-release

# App bauen und starten
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` nimmt `x64-debug`, `x64-release`, `arm64-debug` und `arm64-release` entgegen.

Während der Entwicklung startet die App nur über `run-app.ps1`. Die App wird als MSIX-Paket gebaut, das Ausführen der exe im Build-Ordner bewirkt also nichts. Das Skript baut das Paket, registriert es für den aktuellen Benutzer und startet es über die App-ID.

Um den Installer zu bauen:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

Das Ergebnis entsteht in `out\release\win-x64`.

## Prüfungen

```powershell
# Tests der C++-Engine
ctest --preset x64-release --output-on-failure

# Tests von App und Katalog
.\scripts\test-managed.ps1

# Grenztests zwischen Engine und App
.\scripts\test-interop.ps1

# Alles auf einmal
.\scripts\local-ci.ps1
```

Die Engine-Tests enthalten einen Vergleich mit Referenzbildern. Sie lesen die aus dem macOS-Build gewonnenen Dateien und prüfen, ob die Windows-Engine dieselben Pixel liefert.

## Die Engine über die Kommandozeile prüfen

`negaflow-cli.exe` zeigt, wie die Engine eine einzelne Datei behandelt. Es nimmt Flags statt Unterbefehlen.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# Prüfen, um welchen Build es sich handelt
& $cli --build-info

# Ansehen, was in einer Scandatei steckt
& $cli --probe-tiff scan.tif

# Entwickeln und als 16-Bit-TIFF sichern
& $cli --export-developed-tiff16 scan.tif out.tif

# Sehen, wo die Zeit in einem Entwicklungsdurchlauf hingeht
& $cli --develop-timing scan.tif

# Die Filmbasis automatisch suchen und sehen, was gewählt wurde
& $cli --auto-base-probe scan.tif
```

Ohne Argumente aufgerufen zeigt es die vollständige Liste.

## Scanner

Die Scanner-Bedienelemente erscheinen erst, wenn ein Plug-in installiert ist. SANE-Geräte übernimmt [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), separat zu installieren.

Das Plug-in spricht mit dem Scanner über die Treiberpfade, die Windows ohnehin bereitstellt. VueScan oder SilverFast lassen sich auf derselben Maschine weiter benutzen.

## Wenn etwas schiefgeht

Die App schreibt Textprotokolle nach `%LOCALAPPDATA%\Negaflow\Logs`.

| Datei | Was festgehalten wird |
|---|---|
| `export-trace.txt` | Export und Schnellexport, Fehlschläge eingeschlossen |
| `termination.txt` | Was beim Schließen der App geschah |
| `settings-change.txt` | Geänderte Einstellungen und wer sie geändert hat |

Diese drei sind immer an. Zwei weitere schalten Sie nur ein, wenn Sie einem bestimmten Problem nachgehen.

- `preview-trace.txt`. Legen Sie im selben Ordner eine leere Datei namens `preview-trace.on` an, um es einzuschalten.
- `stage-trace.txt`. Setzen Sie vor dem Start der App die Umgebungsvariable `NEGAFLOW_STAGE_TRACE=1`. Es hält je Entwicklungsschritt Pixelstatistiken fest.

## Ordneraufbau

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, Dekodierung und Export (C++)
│   ├── Interop/       Schicht zwischen Engine und App (C#)
│   ├── Catalog.Core/  Speicher der Bibliothek (C#)
│   ├── Shell.Core/    Logik für Entwickeln, Drucken und Export (C#)
│   ├── Shell/         Bildschirme für Bibliothek, Entwickeln und Abzug (WinUI 3)
│   └── Cli/           Werkzeug zur Engine-Prüfung (C++)
├── scripts/           Skripte für Bauen, Testen und Paketieren
├── tests/             Tests für Engine, App und Grenze
└── Installer/windows/ NSIS-Installer
```

## Verwandte Dokumente

- [Unterschiede zwischen macOS und Windows](../../docs/de/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/de/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/de/product/GRAINMEND.md)
- [Produktarchitektur](../../docs/de/architecture/PRODUCT_ARCHITECTURE.md)
