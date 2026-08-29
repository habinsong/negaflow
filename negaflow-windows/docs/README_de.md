<p align="center">
  <img src="../../negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow">
</p>

<h1 align="center">negaflow for Windows</h1>

<p align="center">negaflow, nativ für Windows entwickelt.</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="Version 1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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

- Windows 11 (Build 26100 oder neuer), 64 Bit
- 8 GB Arbeitsspeicher für Kleinbild, mit 16 GB arbeitet es sich im Mittelformat angenehmer

Zum Bauen:

- Visual Studio 2022 mit der Workload Desktopentwicklung mit C++
- Windows 11 SDK (10.0.26100 oder neuer)
- .NET 10 SDK
- CMake 3.28 oder neuer
- Python 3.11 oder neuer für die Icon- und Ressourcenskripte

Die App läuft auch auf Arm64-Rechnern. Diese Builds sind allerdings weniger geprüft als die
x64-Builds.

## Installation

Laden Sie `negaflow-1.1.0-x64-setup.exe` unter
[Releases](https://github.com/habinsong/negaflow/releases) herunter und starten Sie es.

Administratorrechte sind nicht nötig. SmartScreen warnt beim ersten Start. Klicken Sie auf
Weitere Informationen und dann auf Trotzdem ausführen.

Zum Entfernen nehmen Sie `negaflow deinstallieren` im Startmenü oder suchen negaflow in den
Einstellungen unter Apps. Bibliothek und Fotos bleiben unberührt.

## Bauen

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# C++-Engine bauen
.\scripts\build.ps1 -Preset x64-release

# App bauen und starten
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

`build.ps1` nimmt `x64-debug`, `x64-release`, `arm64-debug` oder `arm64-release`.

Während der Entwicklung ist `run-app.ps1` der einzige Weg, die App zu starten. Sie wird als
MSIX-Paket gebaut, deshalb läuft die lose EXE aus dem Build-Ordner nicht von selbst. Das
Skript packt sie, registriert sie für Ihr Benutzerkonto und startet sie über die App-ID.
Das ist derselbe Weg wie beim Installationsprogramm, nur ohne die Installation.

Für das Installationsprogramm:

```powershell
.\scripts\build-release.ps1 -Architecture x64
```

Das Ergebnis liegt in `out\release\win-x64`.

## Prüfungen

```powershell
# Tests der C++-Engine
ctest --preset x64-release --output-on-failure

# Tests von App und Katalog
.\scripts\test-managed.ps1

# Tests an der Grenze zwischen Engine und App
.\scripts\test-interop.ps1

# Alles davon auf einmal
.\scripts\local-ci.ps1
```

Zu den Engine-Tests gehören Vergleiche mit Referenzbildern. Sie lesen Dateien, die die
macOS-Version erzeugt hat, und prüfen, ob die Windows-Engine dieselben Pixel liefert.

## Die Engine über die Kommandozeile prüfen

`negaflow-cli.exe` ist ein kleines Werkzeug, um zu sehen, was die Engine mit einer Datei
macht. Es ist zum Nachprüfen gedacht und nicht für die tägliche Arbeit, deshalb nimmt es
Schalter statt Unterbefehlen.

```powershell
$cli = "out\build\native\x64-release\Release\negaflow-cli.exe"

# Um welchen Build es sich handelt
& $cli --build-info

# Einen Scan lesen und melden, was in der Datei steht
& $cli --probe-tiff scan.tif

# Entwickeln und als 16-Bit-TIFF schreiben
& $cli --export-developed-tiff16 scan.tif out.tif

# Wo bei einem Entwicklungsdurchlauf die Zeit hingeht
& $cli --develop-timing scan.tif

# Die Filmbasis automatisch suchen und melden, was gewählt wurde
& $cli --auto-base-probe scan.tif
```

Ohne Argumente aufgerufen zeigt es die vollständige Liste.

## Scanner

Scanner-Bedienelemente bleiben verborgen, solange kein Plug-in installiert ist.
[`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane) deckt
SANE-Geräte unter Windows ab und wird separat installiert.

Das Plug-in nutzt den Scanner-Treiberpfad, den Windows ohnehin bereitstellt, deshalb laufen
VueScan und SilverFast auf derselben Maschine weiter.

## Wenn etwas nicht stimmt

Die App schreibt einfache Textprotokolle nach `%LOCALAPPDATA%\Negaflow\Logs`.

| Datei | Was darin steht |
|---|---|
| `export-trace.txt` | Jeder Export und Schnellexport, auch die fehlgeschlagenen |
| `termination.txt` | Was beim Schließen der App passiert ist |
| `settings-change.txt` | Geänderte Einstellungen und was sie geändert hat |

Diese drei laufen immer mit. Wenn Sie ein Problem melden, erklärt meist die passende Datei,
was los war.

Zwei weitere sind standardmäßig aus und dienen der Suche nach einem bestimmten Problem:

- `preview-trace.txt`, eingeschaltet durch eine leere Datei namens `preview-trace.on` im
  selben Ordner
- `stage-trace.txt`, eingeschaltet über die Umgebungsvariable `NEGAFLOW_STAGE_TRACE=1` vor
  dem Start. Sie hält nach jedem Schritt eines Entwicklungsdurchlaufs Pixelstatistiken
  fest, womit sich finden lässt, ab welchem Schritt Vorschau und Export auseinandergehen.

## Aufbau

```
negaflow-windows/
├── src/
│   ├── Native/        Chroma Engine, GrainMend, Dekodierung und Export (C++)
│   ├── Interop/       Die Brücke zwischen Engine und App (C#)
│   ├── Catalog.Core/  Speicher der Bibliothek (C#)
│   ├── Shell.Core/    Logik für Entwicklung, Druck und Export (C#)
│   ├── Shell/         Bibliothek, Entwicklung und Druck (WinUI 3)
│   └── Cli/           Werkzeug zur Engine-Prüfung (C++)
├── scripts/           Skripte zum Bauen, Testen und Packen
├── tests/             Tests für Engine, App und Grenze
└── Installer/windows/ NSIS-Installationsprogramm
```

## Verwandte Dokumente

- [Wo sich beide unterscheiden](../../docs/de/platform/PLATFORM_DIFFERENCES.md)
- [Chroma Engine](../../docs/de/product/CHROMA_ENGINE.md)
- [GrainMend](../../docs/de/product/GRAINMEND.md)
- [Produktarchitektur](../../docs/de/architecture/PRODUCT_ARCHITECTURE.md)
