# Wo sich die macOS- und die Windows-Version unterscheiden

[Dokumentationsstart](../README.md)

negaflow gibt es zweimal. Die macOS-Version ist Swift und SwiftUI auf Core Image. Die Windows-Version ist C# und WinUI 3 mit einer C++-Engine auf Direct3D. Beide teilen sich keinen Quellcode.

Diese Seite sagt, was das in der Praxis heißt: was gleich ist, was anders aussieht und was nur eine Seite kann.

## Gründe für zwei

Eine gemeinsame Codebasis hätte bedeutet, ein Toolkit zu wählen und es auf beiden Systemen hinzunehmen. Menüs an der falschen Stelle, Dateidialoge mit seltsamem Verhalten, Farbe, die noch durch eine Übersetzungsschicht läuft, und ein Fenster, das nie ganz dazugehört.

Jede Seite in ihrer eigenen Sprache zu schreiben kostet ungefähr doppelt so viel Arbeit, und jede Funktion wird zweimal gebaut und zweimal geprüft. Dafür verhalten sich beide Versionen so, wie man es auf dem jeweiligen System erwartet.

## Was gleich ist

Das Bild. Derselbe Scan ergibt auf beiden Seiten dasselbe Ergebnis.

Das ist kein Versprechen auf dem Papier. Der macOS-Build rendert eine Reihe von Referenzbildern, die im Repository unter `docs/verification/macos-golden` liegen. Die Tests der Windows-Engine lesen sie zurück und vergleichen die Pixelwerte. Weicht eine Änderung an der Windows-Engine vom macOS-Ergebnis ab, schlagen die Tests fehl.

Dasselbe gilt für:

- Messung der Filmbasis und Umkehrung
- Alle Entwicklungsziele: `MAIN`, `PRINT`, `HS`, `SP`, `F135`, `HR`, `EXPIRED`
- Tonwerte, Kurven, HSL, Farbgradierung, Schwarzweiß-Tonung
- Erkennung und Reparatur mit GrainMend, einschließlich Infrarotpfad
- Drucklayouts und Seitengeometrie
- Dateibenennung beim Export, EXIF-Eintrag und Metadatenregeln
- Das Katalogformat, sodass eine auf einem System angelegte Bibliothek auf dem anderen gelesen wird

## Was sich unterscheidet

### Farbmanagement

macOS nutzt ColorSync, Windows nutzt ICM. Beide nehmen dieselben ICC-Profile und liefern bis auf Rundung dieselben Werte. Das ist der Teil, der am ehesten unbemerkt abdriftet, deshalb schauen die Referenztests genau hier hin.

### Grafik

macOS lässt die Entwicklungskette über Core Image laufen. Windows nutzt Compute-Shader unter Direct3D und fällt auf die CPU zurück, wo der GPU-Weg nicht verfügbar ist.

Das Tempo hängt eher an der Maschine als an der Plattform. Ein Apple-Silicon-Mac und ein PC mit dedizierter GPU verarbeiten einen 35-mm-Scan beide ohne Wartezeit.

### Wo die Dateien liegen

| | macOS | Windows |
|---|---|---|
| App | `/Applications/negaflow.app` | `%LOCALAPPDATA%\Negaflow\App` |
| Bibliothek und Einstellungen | `~/Library/Application Support/negaflow` | `%LOCALAPPDATA%\Negaflow` |
| Protokolle | Konsole und Support-Ordner | `%LOCALAPPDATA%\Negaflow\Logs` |

### Installieren und Entfernen

macOS liefert ein PKG, das die App nach `/Applications` legt. Zum Entfernen ziehen Sie die App in den Papierkorb, wie bei jeder Mac-App.

Windows liefert ein Installationsprogramm, das ohne Administratorrechte in Ihren Benutzerordner schreibt. Das Entfernen läuft über `negaflow deinstallieren` im Startmenü oder über die Einstellungen und nimmt App-Ordner, Startmenüeintrag und Paketregistrierung mit.

### Kommandozeile

macOS liefert `negaflow`, eine vollständige CLI, die Scanner findet, Dateien entwickelt, GrainMend ausführt und Messungen macht. Sie ist zum Benutzen gedacht.

Windows liefert `negaflow-cli.exe`, ein kleineres Werkzeug, um zu sehen, was die Engine mit einer Datei tut. Es nimmt Schalter statt Unterbefehlen und dient der Fehlersuche, nicht der täglichen Arbeit.

### Signatur

Keine der beiden Fassungen ist mit einem bezahlten Entwicklerzertifikat signiert, deshalb warnen beide Systeme beim ersten Start. Unter macOS klicken Sie in Datenschutz und Sicherheit auf Trotzdem öffnen. Unter Windows klicken Sie bei SmartScreen auf Weitere Informationen und dann auf Trotzdem ausführen.

## Scanner

Das Scanner-Plug-in ist ein eigenes GPL-Projekt, [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane), und es gibt es ebenfalls für beide Systeme. Das Plug-in läuft als eigener Prozess und spricht JSON, sodass negaflow selbst auf keiner der beiden Plattformen SANE-Code enthält.

Unter Windows nutzt das Plug-in den Scanner-Treiberpfad, den Windows ohnehin bereitstellt. Es wird nichts ersetzt, also laufen VueScan und SilverFast auf derselben Maschine weiter.

## Wie beide zusammenbleiben

Jede Funktion kommt zuerst auf macOS und dann auf Windows, ausgerichtet am tatsächlichen Verhalten von macOS statt an einer geschriebenen Spezifikation. Wo sich die Ausgabe messen lässt, entscheiden die macOS-Referenzbilder, ob die Windows-Seite stimmt.

Wenn beide auseinandergehen, hat macOS recht und Windows einen Fehler.
