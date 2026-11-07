<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, nativ für Windows gebaut.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.2.6-EF8B26" alt="Version 1.2.6"></a>
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

## Voraussetzungen

Zum Ausführen:

- Windows 11 24H2 (Build 26100) oder neuer, 64 Bit
- 8 GB Arbeitsspeicher, für Mittelformat 16 GB empfohlen

Zum Bauen:

- Visual Studio 2026 mit der Workload Desktopentwicklung mit C++ (die Komponenten stehen in `.vsconfig`)
- Windows 11 SDK 10.0.26100 oder neuer
- .NET 10 SDK (`global.json` legt 10.0.302 fest)
- CMake 4.2 oder neuer (der Generator `Visual Studio 18 2026` verlangt es)
- Python 3 für die Icon- und Ressourcen-Skripte

Der Build hat auch Arm64-Presets. Veröffentlicht wird nur x64.

## Installation

Laden Sie `negaflow-1.2.6-win-x64.exe` von [Releases](https://github.com/habinsong/negaflow/releases) herunter und starten Sie die Datei. Standardmäßig installiert sie nach `%LOCALAPPDATA%\Negaflow\App` und verlangt keine Administratorrechte.

[negaflow-1.2.6-win-x64-setup.zip](https://github.com/habinsong/negaflow/releases/download/v1.2.6/negaflow-1.2.6-win-x64-setup.zip) enthält dasselbe Installationsprogramm samt Anleitung, Lizenzhinweisen und SHA-256-Prüfsummen. Entpacken Sie alle Dateien, bevor Sie das Installationsprogramm starten. Es ist ein Installationsarchiv, keine portable App.

Das Installationsprogramm ist nicht signiert. SmartScreen warnt beim ersten Start einmal: Klicken Sie auf Weitere Informationen und führen Sie es dann aus.

Deinstalliert wird über `Uninstall negaflow` im Startmenü oder die App-Liste in den Einstellungen. Mediathek und Fotos bleiben unberührt.

Beim Start fragt die App GitHub einmal nach der neuesten Veröffentlichung. Gibt es eine neuere Version, steht unten im ⋯-Menü oben rechts „Auf Version X.Y.Z aktualisieren“. Ein Klick öffnet die Release-Seite und lädt den Installer `win-x64.exe` in den Ordner „Downloads“, geprüft gegen die `SHA256SUMS.txt` des Releases. Installieren Sie es selbst. Ist die App aktuell, lautet der Eintrag „Sie haben die neueste Version.“ und öffnet die Projektseite. Schlägt die Prüfung fehl, etwa offline, erscheint der Eintrag nicht.

## Build

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# C++-Engine bauen
.\scripts\build.ps1 -Preset x64-release

# App bauen und starten
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` akzeptiert `x64-debug`, `x64-release`, `arm64-debug` und `arm64-release`.

Starten Sie die App während der Entwicklung nur mit `run-app.ps1`. Sie wird als MSIX-Paket gebaut, deshalb passiert beim direkten Start der exe im Build-Ordner nichts. Das Skript baut das Paket, registriert es für den aktuellen Benutzer und startet es über die App-ID.

Installationsprogramm bauen:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

Das Ergebnis liegt in `out\release\win-x64`.

## Prüfungen

```powershell
# C++-Engine-Tests
ctest --preset x64-release --output-on-failure

# App- und Katalogtests
.\scripts\test-managed.ps1

# Tests der Grenze zwischen Engine und App
.\scripts\test-interop.ps1

# Alles davon auf einmal
.\scripts\local-ci.ps1
```

Führen Sie `scripts\verify-installer.ps1` (auch von `local-ci.ps1` aufgerufen) in einer angemeldeten Desktop-Sitzung aus. In einer SSH-Sitzung kann die AppX-Registrierung mit `0x80070005` scheitern; das Skript hält dann an, bevor es die bestehende Installation anfasst.

Die CI führt nur die in sich geschlossenen Engine-Tests aus. Die macOS-Referenzdateien liegen außerhalb von Git. Für diese Vergleiche setzen Sie beim Konfigurieren von CMake `NEGAFLOW_MACOS_GOLDEN_ROOT` auf den Referenzordner. Er muss `task6-metadata-policy`, `task9-bw-slide`, `task7-coreimage-filters`, `task8-digital-film-look` und `vibrance` enthalten. Fehlende oder unlesbare Dateien lassen die gewählten Vergleiche scheitern. `ctest --preset x64-release -L external-golden` führt sie aus, die gewöhnlichen Unit-Tests bleiben aktiv.

## Eigene Farbziele

CS steht nach MAIN, HS, SP, F135 und HR in den Zielkapseln. Die Auswahl öffnet unten links eine zweispaltige Liste mit 18 Custom-Zielen in Gruppen zu 11, 4 und 3; die Look-Auswahl bleibt rechts. Beim Wechsel zu CS wird Emulsion gewählt, ein Foto mit Custom-Ziel behält sein Ziel.

Custom nutzt dieselben custom-3-Koeffizienten und String-IDs wie macOS. Das gewählte Ziel steht in den Fotoeinstellungen und im Katalog, Vorschau und Export durchlaufen dieselbe Stufe. Die Ordnerkopfzeile wendet das gewählte Ziel mit der vorhandenen Schaltfläche Anwenden auf den Ordner an.

## Engine über die Befehlszeile prüfen

`negaflow-cli.exe` lässt die Engine auf einer einzelnen Datei laufen. Es nimmt Optionen, keine Unterbefehle.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# Build-Informationen
& $cli --build-info

# Inhalt einer Scandatei
& $cli --probe-tiff scan.tif

# Entwickeln und als 16-Bit-TIFF speichern
& $cli --export-developed-tiff16 scan.tif out.tif

# Zeitverteilung eines Entwicklungsdurchlaufs
& $cli --develop-timing scan.tif

# Automatisch gemessene Filmbasis und gewählter Wert
& $cli --auto-base-probe scan.tif
```

Ohne Argumente zeigt es die vollständige Liste.

## Scanner

Scanner-Bedienelemente bleiben verborgen, bis ein Plug-in installiert ist. SANE-Geräte übernimmt [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), das separat installiert wird.

Das Plug-in spricht den Scanner über die Treiberwege an, die Windows ohnehin mitbringt. VueScan oder SilverFast können auf demselben Rechner installiert bleiben.

## Wenn etwas schiefgeht

Die App schreibt Textprotokolle nach `%LOCALAPPDATA%\Negaflow\Logs`.

| Datei | Was sie festhält |
|---|---|
| `export-trace.txt` | Export und Schnellexport, auch Fehler |
| `termination.txt` | Was beim Beenden der App geschah |
| `settings-change.txt` | Geänderte Einstellungen und wer sie geändert hat |

Diese drei sind immer aktiv. Zwei weitere sind standardmäßig aus:

- `preview-trace.txt`: Legen Sie im selben Ordner eine leere Datei `preview-trace.on` an.
- `stage-trace.txt`: Setzen Sie vor dem Start der App die Umgebungsvariable `NEGAFLOW_STAGE_TRACE=1`. Sie hält Pixelstatistiken nach jeder Entwicklungsstufe fest.

## Aufbau

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, Decodierung und Export (C++)
│   ├── Interop/       Die Schicht zwischen Engine und App (C#)
│   ├── Catalog.Core/  Mediathek-Speicherung (C#)
│   ├── Shell.Core/    Logik für Entwickeln, Abzug und Export (C#)
│   ├── Shell/         Ansichten für Mediathek, Entwickeln und Abzug (WinUI 3)
│   └── Cli/           Prüfwerkzeug für die Engine (C++)
├── scripts/           Skripte für Build, Test und Paketierung
├── tests/             Tests für Engine, App und Grenzschicht
└── Installer/windows/ NSIS-Installationsprogramm
```

## Weitere Dokumente

- [Wo sich die beiden Versionen unterscheiden](../../docs/de/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/de/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/de/product/GRAINMEND.md)
- [Produktstruktur](../../docs/de/architecture/PRODUCT_ARCHITECTURE.md)
