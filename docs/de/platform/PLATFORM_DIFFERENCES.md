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
- Benennung der Exportdateien, EXIF-Schreiben und Metadatenregeln
- Das Katalogformat (`library.sqlite`)

## Was sich unterscheidet

### Farbmanagement

macOS nutzt ColorSync, Windows nutzt ICM. Beide übernehmen dieselben ICC-Profile und liefern im Rahmen der Rundung dieselben Zahlen. Die Paritätstests decken das ab, weil sich gerade dieser Teil am leichtesten unbemerkt verschiebt.

### Grafik

macOS führt die Entwicklungskette auf Core Image aus. Windows führt sie auf Direct3D-Compute-Shadern aus, mit CPU-Rückfall, wo der GPU-Pfad nicht verfügbar ist.

### Wo Dateien liegen

| | macOS | Windows |
|---|---|---|
| App | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Mediathek und Einstellungen | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |

### Installation und Entfernen

macOS liefert ein PKG, das die App nach `/Applications` legt; zum Entfernen ziehen Sie die App in den Papierkorb. Windows liefert ein Installationsprogramm, das ohne Administratorrechte in Ihren Benutzerordner schreibt. Entfernt wird über `Uninstall negaflow` im Startmenü oder über die Einstellungen, dabei verschwinden App-Ordner, Startmenüeintrag und Paketregistrierung.

### Befehlszeile

macOS liefert `negaflow`, eine vollständige CLI, die Scanner erkennt, Dateien entwickelt, GrainMend ausführt und Benchmarks fährt. Windows liefert `negaflow-cli.exe`, ein kleineres Diagnosewerkzeug, das prüft, was die Engine mit einer einzelnen Datei macht. Es nimmt Optionen, keine Unterbefehle.

### Signierung

Keine der beiden Versionen ist mit einem kostenpflichtigen Entwicklerzertifikat signiert, deshalb warnen beide Systeme beim ersten Start. Die Mac-Version ist ad hoc signiert und nicht notarisiert: Erlauben Sie sie unter Datenschutz & Sicherheit mit Trotzdem öffnen. Das Windows-Installationsprogramm ist nicht signiert: Klicken Sie in SmartScreen auf Weitere Informationen und führen Sie es dann aus.

## Scanner

Das Scanner-Plug-in ist ein eigenständiges GPL-Projekt, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), und es gibt es für beide Systeme. Es läuft als eigener Prozess und spricht JSON, deshalb enthält negaflow auf keiner Plattform SANE-Code. Unter Windows nutzt es den Scanner-Treiberpfad, den Windows ohnehin mitbringt, VueScan und SilverFast funktionieren auf demselben Rechner also weiter.

## Beide gleich halten

Jede Funktion kommt zuerst auf macOS und dann auf Windows, gemessen am tatsächlichen macOS-Verhalten. Wo sich die Ausgabe messen lässt, entscheiden die macOS-Referenzbilder, ob Windows stimmt. Weichen beide voneinander ab, hat macOS recht und der Fehler liegt auf der Windows-Seite.
