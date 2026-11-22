# Wo sich die macOS- und die Windows-Version unterscheiden

[Dokumentationsstart](../README.md)

negaflow gibt es zweimal, einmal für macOS und einmal für Windows. Die beiden teilen keinen Quellcode, und jede ist so geschrieben, wie es auf ihrem System üblich ist.

## Warum zwei Versionen

Eine gemeinsame plattformübergreifende Codebasis hieße, ein Toolkit mit seinen Kompromissen auf beiden Systemen hinzunehmen: Menüs und Dateidialoge, die sich seltsam verhalten, eine zusätzliche Farbumrechnungsschicht, Fenster, die nicht zum System passen. Jede Seite nativ zu schreiben verdoppelt etwa den Aufwand, weil jede Funktion zweimal gebaut und getestet wird. Dafür verhält sich jede Version so, wie man es auf seinem System erwartet.

## Was identisch ist

Das Bild. Derselbe Scan liefert auf beiden Systemen dasselbe Ergebnis.

Die macOS-Version rendert eine Reihe von Referenzbildern nach `docs/verification/macos-golden`. Git ignoriert diesen Ordner, die Bilder liegen also nur dort, wo sie erzeugt wurden. Die Windows-Engine-Tests lesen Kopien davon und vergleichen Pixelwerte, eine Abweichung der Windows-Engine lässt die Tests daher scheitern.

Dasselbe gilt für:

- Messung der Filmbasis und Invertierung
- Alle Entwicklungsziele: `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`, `CS`
- Tonwerte, Kurven, HSL, Farb-Grading, Schwarzweißtonung
- GrainMend-Erkennung und -Reparatur, einschließlich des Infrarotpfads
- Abzugslayouts und Seitengeometrie
- Benennung der Exportdateien über alle Formate hinweg sowie EXIF-Schreiben und Metadatenregeln bei JPEG, TIFF und DNG (unter Windows enthält der PNG-Export DPI und ICC-Profil ohne EXIF-Metadaten)
- Das Katalogformat (`library.sqlite`)

## Was sich unterscheidet

### Farbmanagement

macOS nutzt ColorSync, Windows nutzt ICM. Beide übernehmen dieselben ICC-Profile und liefern im Rahmen der Rundung dieselben Zahlen. Die Paritätstests decken das ab, weil sich gerade dieser Teil am leichtesten unbemerkt verschiebt.

Auf dem Bildschirm zeichnet macOS über das ColorSync-Profil des Displays. Windows tut das nur, wenn Advanced Color eingeschaltet ist. Ist es aus, schickt Windows die Pixel der App als sRGB an das Display. Deshalb wendet negaflow unmittelbar vor dem Zeichnen die 33³-LUT des Monitor-ICC-Profils auf die Entwicklungsfläche und die Druckvorschau (einschließlich kleiner Kontaktbogen-Kacheln) an und aktualisiert sie automatisch beim Monitorwechsel oder bei der Rückkehr ins Fenster nach geänderten Anzeigeeinstellungen. Miniaturen und die übrige Oberfläche werden als sRGB gezeichnet.

### Grafik

macOS führt die Entwicklungskette auf Core Image standardmäßig in 16-Bit-Half-Float-Linearpräzision (`RGBAh`) aus. Windows führt sie auf Direct3D-11-Compute-Shadern aus, mit CPU-Rückfall, wo der GPU-Pfad nicht verfügbar ist, und arbeitet auf beiden Pfaden mit 32-Bit-Gleitkommazahlen (`RGBA32F`).

### Wo Dateien liegen

| | macOS | Windows |
|---|---|---|
| App | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Katalog, Defekt-Sidecars, Rezepte, Druckvorlagen | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| App-Einstellungen | `UserDefaults` (`~/Library/Preferences/com.songhabin.negaflow.plist`) | `%LOCALAPPDATA%\Negaflow` |

### Installation und Entfernen

macOS liefert ein PKG, das die App nach `/Applications` legt; zum Entfernen ziehen Sie die App in den Papierkorb. Das Windows-Installationsprogramm schreibt nach `%LOCALAPPDATA%\Negaflow\App` und fragt nur dann einmalig nach einer Administratorbestätigung, wenn Windows die Registrierung unsignierter loser Anwendungspakete (`AllowDevelopmentWithoutDevLicense`) noch nicht erlaubt. Entfernt wird über `Uninstall negaflow` im Startmenü oder über die Einstellungen, dabei verschwinden App-Ordner, Startmenüeintrag und Paketregistrierung.

### Befehlszeile

Die GUI-Release-Installationspakete enthalten kein Befehlszeilenprogramm; stattdessen stellt der jeweilige Quellcode-Build eine CLI bereit. Auf macOS erzeugt `swift build` das Werkzeug `negaflow`, das Scanner erkennt, Dateien entwickelt, GrainMend ausführt und Benchmarks fährt. Unter Windows erzeugt der CMake-Build `negaflow-cli.exe`, ein kleineres Diagnosewerkzeug, das prüft, was die Engine mit einer einzelnen Datei macht und Optionen statt Unterbefehlen entgegennimmt.

### Signierung

Keine der beiden Versionen ist mit einem kostenpflichtigen Entwicklerzertifikat signiert, deshalb warnen beide Systeme beim ersten Start. Die Mac-Version ist ad hoc signiert und nicht notarisiert: Erlauben Sie sie unter Datenschutz & Sicherheit mit Trotzdem öffnen. Das Windows-Installationsprogramm ist nicht signiert: Klicken Sie in SmartScreen auf Weitere Informationen und führen Sie es dann aus.

## Scanner

Das Scanner-Plug-in ist ein eigenständiges GPL-Projekt, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), und es gibt es für beide Systeme. Es läuft als eigener Prozess und spricht JSON, deshalb enthält negaflow auf keiner Plattform SANE-Code. Unter Windows nutzt es den Scanner-Treiberpfad, den Windows ohnehin mitbringt, VueScan und SilverFast funktionieren auf demselben Rechner also weiter.

## Beide gleich halten

Jede Funktion kommt zuerst auf macOS und dann auf Windows, gemessen am tatsächlichen macOS-Verhalten. Wo sich die Ausgabe messen lässt, entscheiden die macOS-Referenzbilder, ob Windows stimmt. Weichen beide voneinander ab, hat macOS recht und der Fehler liegt auf der Windows-Seite.
