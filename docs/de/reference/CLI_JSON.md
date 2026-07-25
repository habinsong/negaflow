# Scanner-CLI-JSON

[Dokumentationsstart](../README.md)

So liest ein Skript oder ein anderes Programm die Scannerangaben. Das bleibt getrennt von der
Scannerimplementierung. Die CLI wandelt nur die Geräteangaben und Fähigkeiten, die `ScannerKit`
erhalten hat, in JSON um.

| Punkt | Vertrag |
|---|---|
| Unterstützte Befehle | `detect --json`, `capabilities <scannerID> --json` |
| stdout | Ein JSON-Dokument und ein abschließender Zeilenumbruch |
| stderr | Diagnoseprotokoll |
| Aktuelles Schema | `negaflow.scanner-cli`, Version `1` |

## Befehle

```bash
negaflow detect [--demo] --json
negaflow capabilities <scannerID> [--demo] --json
```

Vorerst funktioniert `--json` nur bei diesen beiden lesenden Befehlen. An `scan` oder
`develop`, die Dateien ändern oder Fortschritt melden, endet es mit dem Fehler
`unsupported_json_command`.

## Gemeinsame Form

Erfolg und Fehler schreiben je ein JSON-Dokument nach stdout, mit Zeilenumbruch am Ende.

<details>
<summary>Beispiel für eine Erfolgsantwort</summary>

```json
{
  "schema": "negaflow.scanner-cli",
  "schemaVersion": 1,
  "command": "capabilities",
  "status": "ok",
  "payload": {},
  "error": null
}
```

</details>

Bei einem Fehler ist `status` gleich `error` und `payload` gleich `null`. In `error` stehen ein
unveränderlicher Maschinencode und eine Beschreibung für Menschen. Diagnoseprotokolle gehen nach
stderr. Protokolle und Fortschritt kommen nie in stdout.

## Fähigkeitsangaben

Das `payload` von `capabilities` führt immer alle diese Felder.

- `resolutionsDPI`, `modes`, `bitDepths`
- `sourceModes`, `transparencyModes`
- `supportsPreview`, `supportsTransparency`, `supportsInfrared`
- `supportsMultiExposure`, `supportsScanArea`, `supportsPositionedScanArea`
- `supportsLampWarmupStatus`
- `brightnessRange`, `contrastRange`, `hardwareExposureRange`
- `scanOriginXRange`, `scanOriginYRange`, `scanWidthRange`, `scanHeightRange`
- `disabledReasons`
- `minScanArea`, `maxScanArea`, `scanAreaUnit`
- `outputFormats`, `estimatedScanSpeeds`

Werte, die das Gerät nicht gemeldet hat, werden nicht geraten. Je nach Wert stehen dort `null`,
ein leeres Array, `false` oder die vom Plugin gesendeten `disabledReasons`.

`estimatedScanSpeeds` ist ein Array dieses Objekts, aufsteigend nach DPI.

```json
{ "dpi": 3600, "seconds": 42.0 }
```

App-Oberfläche und CLI lesen dieselben `ScannerCapabilities`. Die Abgleichprüfung bestätigt,
dass die auf dem Bildschirm geöffneten Bedienelemente denselben Werten folgen wie die
JSON-Felder.

## Versionsregeln

- Bedeutung und Typ eines vorhandenen Feldes ändern sich nicht.
- Ein neues optionales Feld kommt nur dazu, wenn ältere Programme unbekannte Felder ignorieren können.
- Ein Feld zu entfernen, umzubenennen oder seinen Typ zu ändern hebt `schemaVersion` an.
- Auflösungen, Modi und Bittiefen behalten die Reihenfolge des Plugins.
- Nur die geschätzten Geschwindigkeiten werden nach DPI sortiert.
