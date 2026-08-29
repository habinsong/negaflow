<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow App-Symbol">
</p>

<h1 align="center">negaflow</h1>

<p align="center">Eine App für den Analogfilm-Ablauf, vom Scan über die Entwicklung bis zum Druck. Nativ auf macOS und auf Windows.</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/de/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="Website"></a>
  <a href="#install"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="Version 1.1.0"></a>
  <a href="negaflow-mac/docs/README_de.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer"></a>
  <a href="negaflow-windows/docs/README_de.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/de/">Website</a> ·
  <a href="https://habinsong.github.io/negaflow-site/de/camera-scanning/">Anleitung zum Abfotografieren</a> ·
  <a href="https://habinsong.github.io/negaflow-site/de/faq/">FAQ</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/de/develop-dark.webp">
    <img src="docs/images/de/develop-light.webp" alt="negaflow Entwicklung">
  </picture>
</p>

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
> **Diesem Sommer gewidmet, zweihundert Jahre seit Niépces erster Fotografie.**

---

## Zwei Apps, getrennt gebaut

negaflow läuft auf macOS und auf Windows. Die beiden Apps teilen sich keinen Code.

| | macOS | Windows |
|---|---|---|
| Oberfläche | SwiftUI | WinUI 3 |
| Engine | Swift und Core Image | C++ und Direct3D |
| Farbmanagement | ColorSync | Windows ICM |

Dasselbe Foto ergibt auf beiden Seiten dasselbe Bild. Referenzbilder aus dem macOS-Build
liest die Windows-Testsuite zurück und vergleicht sie Pixel für Pixel.

Jede Fassung ist für ihre eigene Plattform geschrieben statt portiert, was bedeutet, alles
zweimal zu bauen. Dafür verhalten sich beide so, wie man es auf dem jeweiligen System
erwartet.

- [macOS-Dokumentation](negaflow-mac/docs/README_de.md)
- [Windows-Dokumentation](negaflow-windows/docs/README_de.md)
- [Wo sich beide unterscheiden](docs/de/platform/PLATFORM_DIFFERENCES.md)

---

## Installation

Die aktuelle Version gibt es bei [GitHub Releases](https://github.com/habinsong/negaflow/releases).

### macOS

| Download | Mac |
|---|---|
| `negaflow-1.1.0-1-macOS-universal.pkg` | Apple Silicon und Intel |
| `negaflow-1.1.0-1-macOS-arm64.pkg` | Nur Apple Silicon |

Für die meisten Macs passt das Universal-PKG.

1. Laden Sie das PKG für Ihren Mac herunter.
2. Öffnen Sie es und folgen Sie dem Installationsprogramm.
3. Starten Sie **negaflow** aus `/Applications`.

Auf derselben Seite liegen DMG und ZIP, falls Sie lieber von Hand installieren.
Die App ist nicht notarisiert. Beim ersten Start öffnen Sie die Systemeinstellungen,
gehen zu Datenschutz und Sicherheit und klicken auf Trotzdem öffnen.

### Windows

| Download | PC |
|---|---|
| `negaflow-1.1.0-x64-setup.exe` | Windows 11 (x64) |

1. Installationsprogramm herunterladen und starten.
2. Sprache wählen und den Schritten folgen.
3. **negaflow** über das Startmenü öffnen.

Alles landet in Ihrem Benutzerordner, Administratorrechte sind nicht nötig.
Zum Entfernen nehmen Sie `negaflow deinstallieren` im Startmenü oder die App-Liste
in den Einstellungen.
Das Installationsprogramm ist nicht signiert, deshalb warnt SmartScreen einmal.
Klicken Sie auf Weitere Informationen und dann auf Trotzdem ausführen.

> Für einen echten Scanner brauchen Sie ein separates Plug-in.<br>
> SANE-Scanner übernimmt [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), verfügbar für macOS und Windows.

---

## Funktionen

- Messung der Filmbasis und Invertierung von Farb- oder Schwarzweißfilm
- Belichtung, Kontrast, Kurven, HSL, Farbkorrektur und Schwarzweiß-Tonung
- Schärfung, Rauschminderung, Korn, Vignette und Halation
- Staub- und Kratzerreparatur mit GrainMend, samt GrainMend IR über einen Infrarotdurchgang des Scanners
- Filme, Ordner, Sammlungen, Bewertungen, Stapel und virtuelle Kopien
- Zoom, Zuschnitt, Drehung, Vergleichsansichten, Histogramm und Beschnittwarnung
- Kamera, Objektiv, Film und Belichtung als Notiz, geschrieben in die EXIF der Exportdatei
- Aufnahmedaten je Rolle und Suche in der Bibliothek nach Kamera, Objektiv oder Film
- JPEG- und 16-Bit-TIFF-Export, ICC-Profile und Drucklayouts
- Layoutbezogene Bögen in Schwarz/Grau/Weiß, gemeinsame Vorschau für Matt/Glänzend/Lustre/Seide,
  Foto-/ISO-Formate und optionale in/cm-Lineale
- C-Print-Angaben zu Labor und Papier mit ICC-Softproof
- Importfortschritt, Entwicklung pro Ordner mit Prozess, Ziel und Fortschrittsanzeige
- Gespeicherte Ordnerzustände, Verschieben per Drag-and-drop und Finder-Synchronisierung
- Vorgaben und Kopieren/Einfügen einschließlich Prozess, Ziel, Korrekturen, Beschnitt und Ausrichtung
- Sieben Abzugslayouts: Einzelbild, Kontaktbogen, Bildpaket, Benutzerpaket, Cyanotypie,
  Glasplatte und Silbergelatine
- Seitenbezogener Abzugs- und Schnellexport: Ein 6 × 7-Kontaktbogen mit 39 Fotos wird zu einer
  zusammengesetzten Datei, Einzelbildlayouts zu 39 Dateien, mit linearem Fortschritt und Prozent


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
Die Reihenfolge von Invertierung und Farbverarbeitung steht unter [Chroma Engine](docs/de/product/CHROMA_ENGINE.md).

## GrainMend

**GrainMend repariert Filmfehler: Staub, Pinholes, Kratzer und Emulsionsschäden.** <br>


| GrainMend RGB | Aufgabe |
|---|---|
| Auto | Findet und repariert Fehler im ganzen Bild. |
| Geführt | Sucht Fehler in einem markierten Bereich. |
| Pinsel | Lässt die zu reparierende Stelle direkt übermalen. |
| Kopierstempel | Kopiert Pixel von einem gewählten Quellpunkt. |


Auto und Geführt in **GrainMend RGB** füllen einen Fehler mit Textur aus der Umgebung und <br>
prüfen dabei Richtung und benachbarte Strukturen, damit Linien oder Gitter im Motiv nicht als Kratzer verschwinden. <br>
Jedes Ergebnis bleibt als GrainMend-Ebene erhalten. <br><br>
> Auto beseitigt die üblichen Fehler eines Bildes. Werden die Kandidaten zu dicht, um sie sicher anzuwenden, stoppt es ohne Bildänderung und verweist auf Geführt. <br>
> Geführt ist für die unterschiedlichen Staubspuren gedacht, die beim Scannen entstehen. Der Pinsel repariert, was die automatischen Durchgänge übersehen haben, und der Kopierstempel überträgt die selbst gewählten Quellpixel. <br>
Bei jeder **GrainMend RGB**-Ebene lassen sich Stärke ändern, Maske ansehen sowie einzeln deaktivieren oder löschen.


Liefert das Scanner-Plug-in einen Infrarotkanal, ergänzt **GrainMend IR** seine Erkennung in derselben Bearbeitungshistorie.<br><br>

**GrainMend RGB** ist ein eigenständiges Softwareverfahren und unterscheidet sich von hardwarebasierter Infrarotreinigung; <br>
**GrainMend IR** nutzt den Infrarotkanal des Scanners und ist keine Implementierung oder Kompatibilitätsfunktion für Digital ICE, iSRD oder SRDx.

Umsetzung sowie Qualitäts- und Leistungskontrollen stehen unter [GrainMend](docs/de/product/GRAINMEND.md).

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
Daten und Erzeugung sind unter [Filmprofile](docs/de/product/FILM_PROFILES.md) beschrieben.

## Grundlegender Ablauf

1. Bilddatei importieren oder mit einem installierten Plug-in scannen.
2. Filmtyp wählen und Filmbasis messen.
3. Farbe und Ton in Chroma Engine einstellen.
4. GrainMend auf die benötigten Bilder anwenden.
5. Ergebnis in Vergleichsansichten und Histogramm prüfen und anschließend drucken oder exportieren.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/de/library-dark.webp">
    <img src="docs/images/de/library-light.webp" alt="negaflow Mediathek">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/de/print-dark.webp">
    <img src="docs/images/de/print-light.webp" alt="negaflow Druck">
  </picture>
</p>

Die Oberfläche ist für Menschen gebaut, die wirklich mit Fotos arbeiten, nicht als beliebiger KI-generierter Entwurf.<br>
Wer Fotografie als Hobby betreibt, soll sich darin ohne Umwege zurechtfinden.

## Von der Bibliothek zum Druck

Ein Import startet standardmäßig keine Entwicklung. negaflow legt zuerst das Quellvorschaubild und
den Ordner an. Die Entwicklung beginnt, wenn Prozess und Ziel auf einen Ordner angewendet werden
oder wenn Entwickeln geöffnet wird. Die automatische Entwicklung lässt sich in den
Arbeitsablauf-Einstellungen einschalten und ist standardmäßig aus.

Eingeklappte Ordner bleiben nach einem Neustart eingeklappt. Fotos können zwischen Ordnern
verschoben werden. Existiert der Dateiname bereits, ergänzt negaflow eine Nummer, statt die Datei
zu überschreiben. Verschieben oder Umbenennen im Finder aktualisiert die Bibliothek, wobei nur der
geänderte Ordner neu gelesen wird.

Kopieren/Einfügen von Entwicklungseinstellungen und Benutzervorgaben umfassen Prozess, Ziel,
Filmbasis, Ton, Farbe, Details, Beschnitt, Drehung, Spiegelung und Ausrichtung. Bei einer
Mehrfachauswahl gilt das Einfügen für alle ausgewählten Fotos.

Das Drucker-Ausgabeprofil im Druckbereich wird auf die zusammengesetzte Seite angewendet. Dadurch
erhalten wiederholte Platzierungen und Pakete mit mehreren Fotos dieselbe Ausgabeumwandlung. Die
Vorschau in Entwickeln bleibt davon unberührt.

Einzelheiten stehen unter [Von der Bibliothek zum Druck](docs/de/product/WORKFLOW.md).

## Aus dem Quellcode bauen

Werkzeuge und Befehle unterscheiden sich je nach Plattform. Ausführlich steht es in der jeweiligen Dokumentation.

**macOS**

```bash
git clone https://github.com/habinsong/negaflow.git
cd negaflow

# Release bauen und starten
bash scripts/run-app.sh

# Nur bauen, nicht starten
bash scripts/run-app.sh build
```

Sie brauchen macOS 14 oder neuer und Xcode 26. Für Engine und CLI allein genügt `swift build`.
Mehr steht in der [macOS-Dokumentation](negaflow-mac/docs/README_de.md).

**Windows**

```powershell
git clone https://github.com/habinsong/negaflow.git
cd negaflow\negaflow-windows

# Engine bauen
.\scripts\build.ps1 -Preset x64-release

# App bauen und starten
.\scripts\run-app.ps1 -Architecture x64 -Configuration Release
```

Sie brauchen Windows 11, Visual Studio 2022 und das .NET 10 SDK.
Mehr steht in der [Windows-Dokumentation](negaflow-windows/docs/README_de.md).

## Scanner

negaflow leitet Funktionen nicht aus einem Scanner-Modellnamen ab.<br>
Es verwendet nur Auflösungen, Bittiefen, Scanbereiche, Belichtungssteuerung und IR-Unterstützung, die das Plug-in meldet.

SANE-Geräte betreut das separate GPL-Projekt [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).<br>
Das Plug-in läuft in einem eigenen Prozess und spricht über JSON mit der App.<br>
Die Haupt-App enthält und verlinkt keinen SANE-Code.

## Repository

```
negaflow/
├── negaflow-mac/       macOS-App und Engine (Swift)
├── negaflow-windows/   Windows-App und Engine (C#, C++)
└── docs/               gemeinsame Dokumentation
```

**macOS**

| Modul | Aufgabe |
|---|---|
| `Chromabase` | Chroma Engine, GrainMend, Profile, Export |
| `ScannerKit` | Scannerfähigkeiten prüfen und Plug-in anbinden |
| `negaflowApp` | Bibliothek, Entwicklung, Scan und Export |
| `negaflowCLI` | Entwickeln, scannen, messen, Selbsttest |

**Windows**

| Modul | Aufgabe |
|---|---|
| `Native` | Chroma Engine, GrainMend, Export (C++) |
| `Interop` | Die Brücke zwischen Engine und App |
| `Catalog.Core` | Speicher der Bibliothek |
| `Shell.Core` | Logik für Entwicklung, Druck und Export |
| `Shell` | Bibliothek, Entwicklung und Druck (WinUI 3) |

Wie die Daten zwischen den Modulen laufen, steht in der [Produktarchitektur](docs/de/architecture/PRODUCT_ARCHITECTURE.md).

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [Chroma Engine](docs/de/product/CHROMA_ENGINE.md) | Filmbasis, Umkehrung, Farbverarbeitung, Reihenfolge |
| [GrainMend](docs/de/product/GRAINMEND.md) | Defekterkennung und Reparatur, IR, Bearbeitungsverlauf, Qualität und Tempo |
| [Filmprofile](docs/de/product/FILM_PROFILES.md) | Auswertung des Materials und Profilerstellung |
| [Von der Bibliothek zum Druck](docs/de/product/WORKFLOW.md) | Import, Ordnerabgleich, Stapelentwicklung, Druckprofil |
| [Produktarchitektur](docs/de/architecture/PRODUCT_ARCHITECTURE.md) | App, Engine, Scanner, Speicher, Export |
| [Wo sich beide unterscheiden](docs/de/platform/PLATFORM_DIFFERENCES.md) | Was gleich ist und was nicht |
| [macOS-Dokumentation](negaflow-mac/docs/README_de.md) | Installation, Bauen, CLI unter macOS |
| [Windows-Dokumentation](negaflow-windows/docs/README_de.md) | Installation, Bauen, Engine-Prüfungen unter Windows |

## Lizenz

Das negaflow-Hauptprojekt wird unter der [Apache License 2.0](LICENSE) veröffentlicht.

negaflow ist weder mit Kodak, Fujifilm, Noritsu, LaserSoft Imaging noch mit anderen Markeninhabern verbunden oder von ihnen unterstützt.<br>
Produktnamen dienen nur zur Benennung eines Mess- oder Kompatibilitätsziels.<br>
Siehe [Markenhinweis](TRADEMARKS.md).
