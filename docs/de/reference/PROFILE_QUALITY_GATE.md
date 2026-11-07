# Qualitätsprüfung der Scannerprofile

[Dokumentationsstart](../README.md)

`scripts/evaluate_profile_quality.py` (aus `negaflow-mac/` aufzurufen) prüft, ob eine Änderung an einem Scannerprofil schlechter abschneidet als die akzeptierte Basis. Es vergleicht zwei `SOURCE/summary.json`-Dateien, die `LUT_target/analyze_lut_target.py` erzeugt hat, und nur die Validierungsfälle, die von der Profilabstimmung ausgenommen blieben, zählen für die Entscheidung.

Das Werkzeug legt nicht fest, was gute Farbe ist. Welche Zahlen sinken oder steigen sollen und wie viel Bewegung zulässig ist, schreibt ein Mensch ins Korpus-Manifest. Es gibt keine Standard-Schwellen.

Dieses Repository enthält derzeit kein REAL/TARGET-Bildpaar (`LUT_target/REAL` und `LUT_target/TARGET` sind leer). Es gibt also kein echtes Korpus-Manifest, keine akzeptierte Basis und kein Bestehen-Ergebnis von einem echten Gerät. Die synthetischen Tests prüfen nur den Code des Prüfers.

> [!WARNING]
> Die Farbgenauigkeit eines Scanners lässt sich allein aus diesem Repository nicht freigeben. Eine Freigabeentscheidung braucht festgelegte REAL/TARGET-Paare, nicht zur Abstimmung genutzte Validierungsfälle und von einem Menschen gesetzte Toleranzen.

## Wie weit die App die aktuellen Profile nutzt

Wählen Sie das Ziel `HS` oder `SP` selbst, kann ein begrenzter relativer Unterschied aus der mitgelieferten `realOnly`-Gruppe verwendet werden.

Bedingungen:

- Filmart und Filmname stimmen überein.
- Die bereinigte Menge der Quell-Filmnamen stimmt überein.
- Die Bildzahl weicht um höchstens 15 % ab.

Die Quellprofile tragen weder eine Kennung je Bild noch einen SHA-256, und gleiche Filmnamen belegen nicht, dass dieselben Bilder gepaart wurden. Man kann das daher nicht dasselbe Ergebnis wie das der echten Maschine nennen.

Regeln für die Anwendung:

- Werte, die in den beiden Gruppen in entgegengesetzte Richtungen zeigen, werden nicht angewendet.
- Bei Schwarzweiß entfallen alle Farbanteile, nur der relative Tonwert bleibt.
- Die relative Korrektur wird nicht auf ein Diaprofil ohne passenden Film angewendet.
- Ohne gepaartes Material an derselben Stelle werden Scannertextur und Schärfung nicht angewendet.
- Der Tonwert wird einmal auf die Rec.709-Gammahelligkeit angewendet, Lab-`a*` und -`b*` bleiben erhalten.
- Der Farbgewinn wird im Logarithmusraum interpoliert, damit die Beziehung zwischen gegenüberliegenden Ankern erhalten bleibt.
- Stimmt der SHA-256 einer Datei oder des Manifests nicht, wird das gesamte Profilpaket abgelehnt.

## Was Herstellerunterlagen bestätigen können

- Die [Anleitung zum Fujifilm Frontier 570/SP-3000](https://www.photolabdigital.com/fuji_frontier570_en%5B1%5D.pdf) nennt Funktionen wie Flächen-CCD, Hyper-tone und Hyper-sharpness, veröffentlicht aber weder eine Übertragungsfunktion noch Einstellwerte.
- Die [Produktinformation zum Noritsu HS-1800](https://www.noritsu.eu/hardware/noritsu-film-scanner.html) führt unterstützte Formate, Auflösung und Durchsatz auf, nennt aber keine feste Farbübertragungsfunktion.
- Das [Noritsu-Patent US 7,589,863](https://patents.google.com/patent/US7589863/en) beschreibt den Minilab-Ablauf, bei dem ein Bediener Dichte, Gradation und Schärfung wählt.

Diese Unterlagen zeigen, dass sich die Verarbeitung mit Szene und Bediener ändert. Sie liefern keine Konstanten, um einen HS-1800 oder SP-3000 nachzubilden, und negaflow rät solche Werte nicht aus einem Produktnamen.

## Korpus-Manifest, Schema v1

Das Manifest liegt neben dem Eingangsmaterial, das es festlegt, zum Beispiel `LUT_target/quality/corpus-v1.json`. Pfade beziehen sich auf die Manifestdatei, bei angegebenem `--data-root` auf diesen Pfad.

<details>
<summary>Beispielmanifest</summary>

```json
{
  "schemaVersion": 1,
  "corpusVersion": "scanner-corpus-2026-07-10.1",
  "acceptedBaselineSHA256": "sha256:<64 lowercase hex>",
  "cases": [
    {
      "role": "calibration",
      "stem": "NORITSU/color nega/Portra 400/calibration-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/calibration-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    },
    {
      "role": "holdout",
      "stem": "NORITSU/color nega/Portra 400/holdout-01",
      "real": {
        "path": "REAL/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      },
      "target": {
        "path": "TARGET/NORITSU/color nega/Portra 400/holdout-01.tif",
        "sha256": "sha256:<64 lowercase hex>"
      }
    }
  ],
  "metrics": [
    {
      "name": "mean_delta_e2000",
      "direction": "lowerIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "similarity_score_0_100",
      "direction": "higherIsBetter",
      "allowedRegression": 0.0
    },
    {
      "name": "neutral_a_shift",
      "direction": "absoluteLowerIsBetter",
      "allowedRegression": 0.0
    }
  ]
}
```

</details>

Die Werte `0.0` sind keine Empfehlung. Legen Sie Einträge und Toleranzen passend zu Ihrer Messweise und Ihrer Freigaberichtlinie fest.

## Manifestregeln

- `schemaVersion` muss genau `1` sein. Unbekannte Versionen und unbekannte Felder werden abgelehnt.
- `corpusVersion` benennt eine feste Auswahl und Aufteilung des Materials.
- `acceptedBaselineSHA256` legt die genauen Bytes der akzeptierten `summary.json` fest.
- Jeder Fall ist entweder `calibration` oder `holdout`. Namen dürfen sich nicht wiederholen.
- Das Material darf nicht leer sein, und beide Rollen brauchen mindestens einen Fall.
- REAL- und TARGET-Dateien werden beide als `sha256:<64 Kleinbuchstaben-Hex>` festgelegt.
- Metriknamen dürfen sich nicht wiederholen.
- `allowedRegression` muss eine endliche Zahl größer oder gleich null sein. Boolesche Werte werden abgelehnt.
- Als Richtung werden nur `lowerIsBetter`, `higherIsBetter` und `absoluteLowerIsBetter` akzeptiert.

`absoluteLowerIsBetter` vergleicht den Abstand von null. Verwenden Sie es nur, wenn null die geprüfte Referenz ist.

## Kandidat und akzeptierte Basis vorbereiten

```bash
python3 LUT_target/analyze_lut_target.py
```

Bevor Sie eine Freigabe erteilen, bewahren Sie die gesamte `SOURCE/summary.json` des Kandidaten als nächste akzeptierte Basisdatei auf. Die vorhandene akzeptierte Datei wird erst überschrieben, wenn der Kandidat die Prüfung bestanden hat. Tragen Sie den genauen SHA-256 der akzeptierten Datei in `acceptedBaselineSHA256` ein.

Die Zusammenfassungen von Kandidat und Basis müssen jeden Fall des Manifests genau einmal enthalten. Ein fehlender Fall, ein Duplikat, ein Verarbeitungsfehler oder ein Fall außerhalb des Manifests ist ein Eingabefehler.

`calibration`-Fälle dürfen zur Anpassung des Profils dienen und zählen nicht für die Entscheidung. `holdout`-Fälle bleiben aus Abstimmung und Auswahl heraus. Validierungszahlen werden Fall für Fall verglichen, ein besserer Durchschnitt kann also nicht verbergen, dass ein Bild schlechter wurde.

## Ausführen

<details open>
<summary>Befehl der Qualitätsprüfung</summary>

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

</details>

Modi der Dateiprüfung:

| Wert | Wirkung | Als Freigabebeleg verwendbar |
|---|---|---|
| `all` | Prüft Pfad und SHA-256 jeder REAL/TARGET-Datei | Ja |
| `holdout` | Prüft nur die Validierungsdateien | Für schnelle Diagnose |
| `none` | Prüft keine Bilddateien | Nein |

Standard ist `all`. Der Bericht hält den verwendeten Modus, die Hashes von Manifest und Zusammenfassungen, das Ergebnis der Dateiprüfung sowie den Vergleich je Fall und die Zählung des Validierungssatzes fest. Dasselbe JSON geht nach stdout und in die `--report`-Datei, die atomar gespeichert wird.

Exitcodes:

- `0`: Eingabe gültig, nichts hat sich über die Toleranz hinaus verschlechtert
- `1`: Eingabe gültig, aber mindestens ein Validierungswert liegt außerhalb
- `2`: Schema, Material, Hash, Pfad oder Metrik ist falsch oder fehlt

## Den Prüfer testen

```bash
python3 -m unittest scripts/tests/test_evaluate_profile_quality.py
```

Die Tests nutzen temporäre synthetische Dateien für einen normalen Vergleich, eine Verschlechterung, einen geänderten Hash, ein falsches Schema und falsche Zahlen, doppelte, fehlende und fehlgeschlagene Fälle sowie leeres Material. Sie belegen nicht die Qualität echter Scannerausgabe.
