<p align="center">
  <img src="negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png" width="128" alt="negaflow App-Symbol">
</p>

<h1 align="center">negaflow</h1>

<p align="center">Vom Film zum fertigen Foto. Läuft auf macOS und Windows jeweils nativ.</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/de/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="Website"></a>
  <a href="#download"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="Version 1.1.1"></a>
  <a href="negaflow-mac/docs/README_de.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer"></a>
  <a href="negaflow-windows/docs/README_de.md"><img src="https://img.shields.io/badge/Windows-11%2024H2+-0078D4?logo=windows&logoColor=white" alt="Windows 11 24H2 oder neuer"></a>
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
  <a href="https://habinsong.github.io/negaflow-site/de/camera-scanning/">Abfotografieren mit der Kamera</a> ·
  <a href="https://habinsong.github.io/negaflow-site/de/faq/">FAQ</a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/de/develop-dark.webp">
    <img src="docs/images/de/develop-light.webp" alt="negaflow, Ansicht Entwickeln">
  </picture>
</p>

**negaflow** ist eine App, die Film, den Sie gescannt oder mit der Kamera abfotografiert haben, hereinnimmt und entwickelt. Farbe wie Schwarzweiß, Negativ wie Positiv, alles geht. Von der Bibliothek über das Entwickeln bis zum Abzug ist alles in einer App erledigt. Die Bearbeitungswerte werden getrennt vom Original gespeichert, die Originaldatei bleibt also, wie sie ist.

Die Entwicklungs-Engine heißt **Chroma Engine**, die Reparatur von Staub und Kratzern heißt **GrainMend**. Es macht nichts, wenn Sie keinen Scanner haben. Auch wenn Sie nur Bilddateien importieren, können Sie entwickeln und exportieren. Die Scanner-Verbindung öffnet sich erst, wenn Sie ein Plug-in separat installieren.

> Anders als das Wachstum der analogen Mode in letzter Zeit steckt der Prozess der analogen Fotografie derzeit fest. Solange man den Film nicht analog vergrößert, muss er den Weg der Umwandlung ins Digitale gehen, damit er uns endlich vor Augen kommt.
>
> Doch dieser ganze Ablauf kommt zum Stillstand. Filmlabore und Entwicklungsdienste verschwinden nach und nach, und die Unterstützung durch die Hersteller und für deren Produkte nimmt ab.
>
> Dieses Projekt begann mit den Unannehmlichkeiten, die ich beim Arbeiten auf die eine und die andere Weise gespürt habe, und mit dem Gedanken, dass es schön wäre, wenn es eine solche Funktion gäbe. Auf Grundlage der Erfahrung und des Wissens, die ich beim Arbeiten mit Kleinbild und Mittelformat gewonnen habe, habe ich von eins bis zehn alles selbst entwickelt. Anfangs war es ein Spielzeugprojekt, an dem ich für mich allein herumgebaut habe, doch inzwischen ist negaflow etwas mehr als das geworden.
>
> Am Ende zählt vor allem, dass es „gut“ läuft und bequem zu benutzen ist, dass es schnell sein muss, und dass am Ende ein Ergebnis steht, das von allein ordentlich gemacht wurde. Eigenständig entwickelt, läuft **negaflow** auf macOS und Windows jeweils nativ, und ich habe die Arbeitsabläufe der Filmlabore wie die der Einzelnen alle hineingeschmolzen.
>
>
> **Diesem Sommer gewidmet, dem zweihundertsten Jahr seit Niépces erster Fotografie.** 25. Juli 2026.
## negaflow for macOS and Windows


| | macOS | Windows |
|---|---|---|
| Oberfläche | SwiftUI | WinUI 3 |
| Engine | Swift + Core Image | C++ + Direct3D |
| Farbmanagement | ColorSync | Windows ICM |

Die beiden Apps sind native Apps, in unterschiedlichen Sprachen und auf unterschiedliche Weise entwickelt, und trotzdem sind Funktionen und Ergebnisse gleich.

Der Engine-Code liegt unter macOS im Modul `Chromabase` und unter Windows im Modul `Native`.

Es gibt einen Weg, beide auf einmal zu bauen (plattformübergreifend), aber dabei werden beide langsam und laufen nicht richtig. Deshalb habe ich den Code je Betriebssystem auf dessen eigene Art von vorn geschrieben. Was gleich ist und was nicht, steht [hier](docs/de/platform/PLATFORM_DIFFERENCES.md).

## Download

Sie holen es sich bei [GitHub Releases](https://github.com/habinsong/negaflow/releases).

| Datei | Umgebung |
|---|---|
| `negaflow-1.1.1-mac-universal.pkg` | macOS 14 oder neuer, Apple Silicon und Intel |
| `negaflow-1.1.1-mac-arm64.pkg` | macOS 14 oder neuer, nur Apple Silicon |
| `negaflow-1.1.1-win-x64.exe` | Windows 11 24H2 oder neuer, x64 |

Für die meisten Macs genügt das Universal-PKG. Natürlich liegen die Datei für Silicon sowie ein DMG und ein ZIP auf derselben Seite. Beim ersten Start müssen Sie in den Systemeinstellungen unter Datenschutz und Sicherheit einmal auf Trotzdem öffnen klicken.

Die Windows-Installation endet innerhalb Ihres Benutzerordners und fragt nicht nach Administratorrechten. Da es keine Signatur gibt, blockt SmartScreen einmal. Klicken Sie auf Weitere Informationen und führen Sie es aus. Entfernen können Sie es über die Systemsteuerung.

Um einen echten Scanner anzuschließen, braucht es ein separates Plug-in, und für SANE-Scanner gibt es [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane). Selbstverständlich läuft es auf macOS wie auf Windows.

## Funktionen
> Alles, was analogen Film zu einem fertigen Foto macht, steckt darin.
- Angefangen bei der Messung der Filmbasis und der Entwicklung von Farb- und Schwarzweißnegativen und -positiven
- Alles, was die Korrektur braucht: Belichtung, Kontrast, Kurven, HSL, Colorgrading
- Zusatzoptionen wie Schärfung, Rauschminderung, Korn, Vignette, Halation
- GrainMend, das Fotos wiederherstellt, indem es Staub und Kratzer entfernt.
- Eine Bibliothek mit Filmen, Ordnern, Sammlungen, Bewertungen, Stapeln, virtuellen Kopien und Suche nach Kamera, Objektiv oder Film
- Vorgaben und Kopieren/Einfügen, die Entwicklungsprozess, Ziel, Tonwert, Farbe, Detail, Ausschnitt und Ausrichtung gemeinsam mitnehmen
- Export als JPEG und 16-Bit-TIFF, ICC-Profile, und Angaben wie Kamera, Objektiv und Film ins EXIF geschrieben
- Sieben Abzugslayouts und Papiervorschauen, Foto- und ISO-Papiere, bis hin zur C-Print-Funktion.

## Chroma Engine

**Chroma Engine** übernimmt Invertierung und Entwicklung des Films.

Bevor ein Negativ entwickelt wird, misst sie zuerst die Filmbasis. Sie liest den Wert aus einem Bereich, den das Licht nie erreicht hat. Wo die automatische Messung danebenliegt, tippen Sie einfach mit der Pipette oder passen die RGB-Werte an.

Voreingestellt sind `MAIN` und manuelle Korrekturen. Auto-Tonwert, Auto-Weißabgleich, Auto-Tonwertkorrektur und Auto-Farbe laufen nur, wenn Sie sie drücken.

Die übrigen Ziele sind diese. `PRINT`, das über ein Drucker-ICC ausgibt, `HS` und `SP` aus der Minilab-Familie, `F135` und `HR` aus der Familie der Laborgeräte, `EXPIRED`, das alten Film zurückzuholen versucht. Bei der Ausgabe wählen Sie zwischen sRGB, Display P3, Adobe RGB und einem eigenen RGB-ICC.

Die Reihenfolge von Invertierung und Farbverarbeitung steht in der [Chroma-Engine-Dokumentation](docs/de/product/CHROMA_ENGINE.md).

## GrainMend

> **GrainMend** repariert Staub, Pinholes, Kratzer und Emulsionsschäden.

**GrainMend RGB** ist ein Software-Verfahren und unterscheidet sich damit vom Hardware-IR. <br> <br>
`Automatisch` geht das ganze Foto durch. Einfach, aber Fehlerkennungen wird es geben. <br>
`Geführt` sieht sich nur den angegebenen Bereich an. Auf Staub, der beim Scannen dazukommt, wirkt es am besten. <br>
`Pinsel` ist das Werkzeug, um die von Automatisch übersehenen Stellen selbst zu übermalen, und der Klonstempel überträgt die Pixel einer gewählten Position unverändert.<br>
`Klonstempel` ist eine Stempelfunktion, bei der Sie die gewünschte Textur auswählen und selbst auftragen. <br>

Automatisch und Geführt füllen Defekte, indem sie die umgebende Textur ansehen. Vor dem Füllen sehen sie zuerst Richtung und umgebende Struktur an. Hält man ein Geländer oder eine Fliesenfuge im Foto für einen Kratzer und löscht sie, dann ist das keine Wiederherstellung, sondern ein Schaden.

Das Ergebnis der Korrekturen bleibt als Ebenen erhalten. Sie können die Stärke ändern, die Maske prüfen und einzelne abschalten oder löschen.<br>
**GrainMend IR** fügt die Erkennungsergebnisse aus dem Infrarotkanal, den ein Scanner-Plug-in übergibt, demselben Verlauf hinzu.



**GrainMend IR** nutzt den Infrarotkanal (IR) des Scanners, ist aber weder eine Implementierung noch ein Kompatibilitätsmodus von Digital ICE, iSRD oder SRDx. Die Arbeitsweise sowie die Qualitäts- und Leistungsmaßstäbe stehen in der [GrainMend-Dokumentation](docs/de/product/GRAINMEND.md).

## Vom Import zum Abzug

1. Bilddateien importieren oder mit einem installierten Plug-in scannen.
2. Die Art des Entwicklungsprozesses wählen und das Scanziel angeben.
3. Farbe und Tonwert in der Chroma Engine anpassen.
4. GrainMend auf die Fotos anwenden, die es brauchen.
5. Mit Vorher/Nachher-Ansicht und Histogramm prüfen, dann drucken oder exportieren.

Nur zu importieren entwickelt nichts. Es beginnt, wenn Sie für einen Ordner Prozess und Ziel wählen und **Anwenden** drücken, oder wenn Sie die Ansicht Entwickeln öffnen. Es gibt auch eine eigene Einstellung, die das automatisch erledigt, und deren Standard ist aus.

Was jede Aktion mit Ihren Originaldateien macht, ist als Tabelle in [Von der Bibliothek zum Abzug](docs/de/product/WORKFLOW.md) zusammengestellt.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/de/library-dark.webp">
    <img src="docs/images/de/library-light.webp" alt="negaflow, Ansicht Bibliothek">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/de/print-dark.webp">
    <img src="docs/images/de/print-light.webp" alt="negaflow, Ansicht Abzug">
  </picture>
</p>

## Scanner und Filmprofile

negaflow selbst schaltet keine Funktionen anhand eines Scanner-Modellnamens frei.<br> Es benutzt nur Auflösung, Bittiefe, Scanbereich, Belichtung und IR-Unterstützung, wie das Plug-in sie meldet. Rät man vom Namen aus, gehen Funktionen an, die das Gerät gar nicht hat.

SANE-Geräte übernimmt [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), ein eigenständiges GPL-Projekt. Das Plug-in läuft als eigener Prozess, das Austauschformat ist JSON. In **negaflow** steckt kein SANE-Code, und es wird auch keiner eingebunden.

Im Paket sind 15 Scannerprofile enthalten. Sie sind aus Film entstanden, den ich selbst fotografiert habe, und die Zahl der erfassten Daten beträgt 928.

Der Status ist überall `realOnly`. Das heißt, sie wurden zwar aus echten Scans gebaut, sind aber nicht so weit, dass die Genauigkeit gegen eine unabhängige Referenz geprüft wäre. Ich wollte Ungeprüftes nicht als geprüft hinschreiben. Profile greifen nicht automatisch anhand eines Scannernamens, Sie müssen sie selbst wählen.

Näheres steht in der [Filmprofil-Dokumentation](docs/de/product/FILM_PROFILES.md).

## Dokumentation

- [Chroma Engine](docs/de/product/CHROMA_ENGINE.md) | Filmbasis, Invertierung, Farbverarbeitung und Entwicklungsreihenfolge
- [GrainMend](docs/de/product/GRAINMEND.md) | Defekterkennung und Reparatur, IR, Bearbeitungsverlauf
- [Filmprofile](docs/de/product/FILM_PROFILES.md) | Materialanalyse und Profilerzeugung
- [Von der Bibliothek zum Abzug](docs/de/product/WORKFLOW.md) | Import, Ordnerabgleich, Stapelentwicklung, Abzug
- [Produktarchitektur](docs/de/architecture/PRODUCT_ARCHITECTURE.md) | Struktur von App, Engine, Speicherung und Export
- [Die ganze Dokumentation](docs/de/README.md) | mehrsprachig (6 Sprachen)

## Selbst bauen

Werkzeuge und Befehle unterscheiden sich je Plattform. Der vollständige Ablauf steht in der jeweiligen Dokumentation. [macOS](negaflow-mac/docs/README_de.md) braucht macOS 14 oder neuer und Xcode 26, [Windows](negaflow-windows/docs/README_de.md) braucht Windows 11 24H2, Visual Studio 2022 und das .NET 10 SDK. Die Arbeitsregeln für das Repository stehen in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Lizenz

**negaflow** wird unter der [Apache-Lizenz 2.0](LICENSE) veröffentlicht. Es steht in keiner Verbindung zu Kodak, Fujifilm, Noritsu, LaserSoft Imaging oder einem anderen Markeninhaber und wird von ihnen nicht gesponsert. Produktnamen werden nur benutzt, um zu benennen, womit etwas kompatibel ist oder woran es gemessen wurde. Die [Markenhinweise](TRADEMARKS.md) führen es genauer aus.
