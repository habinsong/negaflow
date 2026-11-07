# Scanner-Plugin-Struktur

[Dokumentationsstart](../README.md)

Die Standardeingabe von negaflow ist der Bildimport. Ein echter Scanner wird nur angebunden, wenn ein externes Plug-in vorhanden ist.

> [!IMPORTANT]
> Die App rät Fähigkeiten nicht aus einem Scanner-Modellnamen. Nur was das Plug-in meldet, gelangt in die Oberfläche und die Anfragen, und das Demogerät erscheint nur, wenn Sie den Demomodus selbst wählen.

## Bestandteile

| Bestandteil | Aufgabe |
|---|---|
| Bildimport | Schickt RAW, DNG, TIFF, PNG und JPEG in den Entwicklungspfad. |
| Externes Plug-in | Läuft als eigener Prozess, steuert das echte Gerät und spricht JSON. |
| Demo-Scanner | Liefert `negaflow Scanner` und `negaflow Flatbed Scanner` für die Entwicklung. Zum Verwenden müssen Sie die Demo wählen. |
| ImageCaptureCore-Anbindung | Inaktiver Kompatibilitätscode für macOS-Bilderfassungsgeräte. |

In diesem Repository gibt es keine SANE-Implementierung. Dieser Code liegt in einem eigenen GPL-Projekt:

- <https://github.com/habinsong/negaflow-scanner-sane>

## Wie die Anbindung läuft

Die Oberfläche spricht mit `ScannerKit`, das auf eines von drei Backends verteilt:

1. `ExternalScannerBackend`, das das installierte externe Plug-in ausführt.
2. `MockScannerBackend`, das synthetische Bilder für die Entwicklung erzeugt.
3. `InactiveImageCaptureBackend`, derzeit inaktiv.

Die Oberfläche sieht nur `ScannerBackend`. Die Geräte-ID eines Plug-ins erscheint in der App als `plugin:<pluginId>:<deviceId>`.

Beim Ausführen des Plug-ins wird `plugin:<pluginId>:` entfernt und nur die eigene Geräte-ID des Plug-ins gesendet.

## Plug-ins finden

Der Standardordner ist `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json`. Für Tests und lokale Entwicklung verweist `NEGAFLOW_PLUGINS_DIR` auf einen anderen Ordner.

| Feld | Regel |
|---|---|
| `schemaVersion` | Derzeit genau `1` |
| `protocolVersion` | `1`, wenn weggelassen; `1` und `2` werden unterstützt |
| `id` | Eindeutige Plug-in-ID |
| `name` | Auf dem Bildschirm gezeigter Name |
| `kind` | Art des Plug-ins |
| `license` | Verbreitungslizenz |
| `homepage` | Projektadresse |
| `executable` | Pfad zur ausführbaren Datei |

`id` hat 1 bis 64 ASCII-Zeichen. Das erste ist ein Buchstabe oder eine Ziffer, die übrigen sind Buchstaben, Ziffern, `.`, `_` oder `-`. `:` trennt die Geräte-ID und ist daher nicht erlaubt.

Ein Plug-in öffnet sich nur, wenn Manifest und ausführbare Datei beide stimmen. Ältere oder künftige Schemata und unbekannte Protokolle werden nicht auf Verdacht gelesen.

### Dateisicherheitsprüfungen

> [!WARNING]
> Ändern sich die Bytes von Manifest oder ausführbarer Datei, verfällt die frühere Freigabe. Eigentümer, Rechte, Symlink-Status und SHA-256 werden unmittelbar vor der Ausführung erneut geprüft.

- Plug-in-Ordner, Manifest und ausführbare Datei müssen dem aktuellen Benutzer gehören.
- Für Gruppe oder andere beschreibbar wird abgelehnt.
- Symlinks werden abgelehnt.
- Der SHA-256 von Manifest und ausführbarer Datei wird festgehalten.
- Der Benutzer gibt das Plug-in bei der ersten Verwendung frei.
- Geänderte Dateibytes heben die Freigabe auf.
- Die IDs werden unmittelbar vor der Ausführung neu berechnet.

## Befehle

Das Plug-in läuft als eigener Prozess.

| Befehl | Ergebnis |
|---|---|
| `detect` | JSON-Geräteliste |
| `capabilities <deviceId>` | JSON-Liste der Fähigkeiten. Kann über stdin das von `detect` gemeldete JSON mit Geräte-ID, Hersteller und Modell annehmen |
| `scan` | Einstellungs-JSON über stdin; Fortschritts-NDJSON und Endergebnis über stdout |

## Scanprotokoll

### Version 1

Die ältere Kompatibilitätsspezifikation. Anfragen und NDJSON haben weder `protocolVersion` noch `requestID` noch `sequence`. Sie kann die tatsächlich angewendeten Einstellungen nicht melden, deshalb wird das Ergebnis als `.unknownLegacy(protocolVersion: 1)` festgehalten. Anfragewerte werden nicht übernommen, als wären sie geprüft.

### Version 2

Wird nur verwendet, wenn das Manifest `"protocolVersion": 2` trägt.

Eine Anfrage enthält:

- `protocolVersion: 2`
- Eine von der App erzeugte `requestID`-UUID

Eine `capabilities`-Antwort darf das optionale Feld `capabilityToken` zurückgeben. Die App deutet es nicht. Sie reicht den Wert unverändert an die nächste v2-`scan`-Anfrage für dasselbe Gerät weiter, sonst nirgends. In v1-Anfragen fehlt es, und Token werden nie zwischen Geräten gemischt. Format und Gültigkeit des Tokens muss das Plug-in selbst prüfen.

Um eine falsche Wiederverbindung zu einem anderen Modell desselben Backends zu verhindern, gibt die App `deviceID`, `vendor` und `model` des letzten `detect` als optionales stdin-JSON an `capabilities` zurück. Bestehende Plug-ins dürfen diese Eingabe ignorieren. Ein Plug-in, dessen Geräteadresse sich ändern kann, sollte diese Identität an den Fähigkeiten-Schnappschuss binden und beim nächsten `scan` erneut prüfen.

Jedes NDJSON-Ereignis wiederholt dieselbe Version und Anfrage-ID und trägt eine `sequence` von null oder mehr, die größer ist als die vorherige. Erlaubt sind nur `progress`, `result` und `error`. `result` und `error` sind Endereignisse, alles danach schlägt fehl. Ein Scan, der nicht mit einem Fehler endete, hat genau ein `result`.

All das scheitert geschlossen:

- Ein nicht lesbares Ereignis
- Eine fehlende oder abweichende Version oder Anfrage-ID
- Eine wiederholte oder ungeordnete Sequenz
- Ein unbekanntes Ereignis
- Ein doppeltes Ergebnis
- Zusätzliche Ausgabe nach dem Endereignis
- Ungültiges UTF-8

Eine Verletzung der v2-Spezifikation beendet das Plug-in sofort, ohne die übliche Zeitgrenze abzuwarten.

### Tatsächlich angewendete Einstellungen

Ein v2-`result` muss `appliedOptions` tragen:

- `deviceID`, `resolutionDPI`, `bitDepth`, `colorMode`, `filmType`
- `scanArea`: `originXMM`, `originYMM`, `widthMM`, `heightMM`, der Bereich, den das Plug-in tatsächlich an das Backend gesendet hat. Ein Plug-in darf ihn um weniger als 1 mm anpassen, um ein Backend zu umgehen, das die Scangröße falsch berechnet. Die App prüft die zurückgegebene Pixelgröße gegen diesen Bereich, ein Abschreiben der Anfrage würde die Prüfung aushebeln.
- `infrared`, `multiExposure`
- `hardwareExposureTime`, `brightnessAdjustment`, `contrastAdjustment`
- `outputRawTIFF`

Bei den letzten drei Anpassungen müssen die Schlüssel auch dann vorhanden sein, wenn der Wert `null` ist.

`resolutionDPI: 0` bedeutet Vorschau. Eine Vorschau ungleich 0 oder ein vollständiger Scan gleich 0 wird abgelehnt. Unbekannte Werte, ein anderes Gerät und eine Auflösung, Bittiefe oder ein IR-Zustand, die zwischen Ergebniskopf und `appliedOptions` abweichen, werden ebenfalls abgelehnt.

Bestehen die Prüfungen, hält die App statt der Plug-in-ID ihre eigene Scanner-ID und die Anfrage-ID fest und behält den endgültigen Ausgabepfad. Erst dann wird das Ergebnis als `.verified(options)` markiert.

In v1 dürfen `ScanResult.resolution` und `bitDepth` auf die angeforderten Werte zurückfallen. Die Felder, die die Herkunft zeigen, `reportedResolution` und `reportedBitDepth`, übernehmen nur richtige Werte, die das Ergebnis selbst gemeldet hat.

## Positionierter Scanbereich am Flachbettscanner

Die Vorschau dieses Ablaufs fordert eine ausdrückliche Auflösung an, den unterstützten Wert, der 300 dpi am nächsten liegt, statt sie dem Gerät zu überlassen. Ein Gerätestandard kann bis auf 25 dpi sinken, viel zu grob, um Bilder zu platzieren oder zu erkennen. Eine Vorschau mit Auflösung ist ein gewöhnlicher Scan und nutzt deshalb nicht den Vorschaupfad des Plug-ins.

Ein Flachbettscan mit gewählter Position wird nur aktiv, wenn das Plug-in all dies meldet:

- Vorschau
- `supportsPositionedScanArea`
- `scanOriginXRange` und `scanOriginYRange` in mm
- `scanWidthRange` und `scanHeightRange` in mm

Die App erweitert den gewählten Bereich nach außen auf die Schrittweite des Plug-ins und erzeugt je Bereich einen vollständigen Scanauftrag. Das wird nie aus einem Modellnamen geraten. Ältere Plug-ins ohne die optionalen Felder behalten den Ablauf mit festen Bildern.

## Prozessgrenzen und Abbruch

- Obergrenze für stdout: 4 MiB
- Obergrenze für stderr: 1 MiB

Wird die Grenze überschritten, endet der Prozess mit einem Fehler. Beim Aufräumen werden nur die bereits eingetroffenen Bytes gelesen. Auch wenn ein Kindprozess die Pipe geerbt hat, wartet nichts auf EOF.

`cancelScan()` kehrt erst zurück, wenn das Plug-in beendet ist, die Pipe-Handler geschlossen sind und der Platz für den nächsten Auftrag frei ist.

## Scandatei veröffentlichen

Das Plug-in schreibt das Quellbild genau in den `outputPath`, den die App vorgegeben hat, und liefert denselben Pfad im Ergebnis zurück. Dieser Pfad liegt an einem temporären Ort auf demselben Datenträger wie der Zielordner. Der Ablauf:

1. Die App sendet das Einstellungs-JSON und den `outputPath` an das Plug-in.
2. Das Plug-in schreibt die Scandatei in den temporären Ordner.
3. Das Plug-in liefert ein Ergebnis mit demselben `outputPath`.
4. Die App prüft Format, Größe und Pfad.
5. Bestehen die Prüfungen, veröffentlicht die App die Datei atomar im endgültigen Scanordner. Bei Abbruch, Fehler oder falscher Ausgabe löscht sie das temporäre Material.

Die App bestätigt:

- Eine reguläre Datei, die nicht leer ist
- Ein Bild, das ImageIO lesen kann
- Das erwartete Format und die erwartete Pixelgröße
- Denselben Pfad in Anfrage und Ergebnis

Bei Abbruch, Zeitüberschreitung, falscher Ausgabe oder Plug-in-Fehler wird der temporäre Ordner gelöscht, und es wird kein unvollständiger Scan veröffentlicht.

Auch eine v2-IR-Datei muss im von der App vorgegebenen temporären Ordner liegen. Dateityp, Lesbarkeit und Pixelgröße werden geprüft. v1 kann zur Kompatibilität mit bereits verbreiteten Plug-ins einen externen IR-Pfad annehmen.

## Die SANE-Grenze

Die SANE-Implementierung, ihre Abhängigkeiten, Konfiguration, die gerätespezifische Verarbeitung, Tests und Release-Dokumentation liegen alle im getrennten Repository [`negaflow-scanner-sane`](https://github.com/habinsong/negaflow-scanner-sane).

Dieses Projekt veröffentlicht ein Standard-Installationsprogramm für macOS 14+ mit dem Standard-SANE von Homebrew und ein eigenes Coolscan-Installationsprogramm für macOS 26+, das das offizielle SANE 1.4.0 mit der minimalen Upstream-Korrektur der Speicherzuweisung in `coolscan2`/`coolscan3` baut. Der Standardweg blockiert Coolscan nicht vorab, enthält diese Korrektur aber nicht.

Dieses Repository dokumentiert und prüft nur die geräteunabhängige Spezifikation für externe Prozesse. Wer nur Bilddateien importiert, braucht kein Scanner-Plug-in.

Die negaflow-App bindet die SANE-Implementierung nicht ein und legt sie nicht in die App-Verbreitung. Das Plug-in hat sein eigenes Repository, seine eigene ausführbare Datei, Quellverbreitung und GPL-Lizenz. Dieses Dokument hält die Struktur fest und entscheidet nicht, ob etwas ein abgeleitetes Werk ist. Vor einem echten Release werden die Dateien beider Artefakte und der Kommunikationsvertrag erneut geprüft.

## Prüfungen

Die App-Tests führen ein gefälschtes externes Plug-in als echten Prozess aus und bestätigen:

- Das Finden von Plug-ins
- Das Finden von Geräten
- Die Verdrahtung der Fähigkeiten
- Fortschrittsereignisse
- Das Endergebnis
- Das Aufräumen nach Abbruch und Fehler

Die SANE-Implementierung wird getrennt geprüft, in den SwiftPM-Tests und im Release-Build des Plug-in-Repositorys.
