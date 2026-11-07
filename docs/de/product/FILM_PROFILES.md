# Filmprofile

[Dokumentationsstart](../README.md)

Die mitgelieferten Scannerprofile entstehen aus Filmbildern, die der Projektautor fotografiert, auf Laborscannern gescannt und analysiert hat, und liegen als JSON vor.

| Eintrag | Aktueller Wert |
|---|---:|
| Standardwerte je Filmart | 27 |
| Kreative Looks | 6 |
| Scannerprofile | 15 |
| Film-Beobachtungen | 25 |
| Bilder | 928 |
| Prüfstatus | alle `realOnly` |

> [!NOTE]
> `928` ist die Zahl der Filmbilder, die der Projektautor fotografiert und auf Laborscannern gescannt hat.

## Drei getrennte Arten von Daten

| Daten | Format | Verwendung | Anzahl |
|---|---|---|---:|
| Filmart | Swift | Dmin/Dmax und Standardwerte je Filmart | 27 |
| Look-Vorgabe | JSON | Kreative Looks, die Sie wählen | 6 |
| Scannerprofil | JSON | Relative Tonwert- und Farbstatistik aus echten Scans | 15 |

27 Filmnamen sind keine 27 Profile zur Farbgenauigkeit, und die 6 Looks sind etwas anderes als Scannerprofile. Im Folgenden geht es nur um die dritte Art.

## Was heute mitgeliefert wird

`Sources/Chromabase/ScannerProfiles/` enthält 15 Profile.

<details>
<summary>Alle 15 Profile ansehen</summary>

| Scanner | Filmart | Film | Film-Beobachtungen | Bilder | Status |
|---|---|---|---:|---:|---|
| NORITSU | Farbnegativ | Fuji C200 | 3 | 111 | `realOnly` |
| NORITSU | Farbnegativ | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| NORITSU | Farbnegativ | Kodak Portra 160 | 1 | 37 | `realOnly` |
| NORITSU | Farbnegativ | Kodak Portra 400 | 2 | 75 | `realOnly` |
| NORITSU | Farbnegativ | Kodak Portra 800 | 1 | 38 | `realOnly` |
| NORITSU | Farbnegativ | Kodak Pro Image 100 | 1 | 37 | `realOnly` |
| NORITSU | Farbnegativ | Kodak UltraMax 400 | 1 | 38 | `realOnly` |
| NORITSU | Farbnegativ | Kodak Vision3 250D | 1 | 37 | `realOnly` |
| NORITSU | Farbnegativ | Kodak Vision3 50D | 1 | 38 | `realOnly` |
| NORITSU | Farbdia | Kodak Ektachrome 100 | 1 | 38 | `realOnly` |
| NORITSU | Farbdia | Kodak Ektachrome 100D | 5 | 181 | `realOnly` |
| SP-3000 | Farbnegativ | Kodak Ektar 100 | 2 | 76 | `realOnly` |
| SP-3000 | Farbnegativ | Kodak Portra 160 | 1 | 38 | `realOnly` |
| SP-3000 | Farbnegativ | Kodak Vision3 250D | 2 | 71 | `realOnly` |
| SP-3000 | Farbdia | Kodak Ektachrome 100D | 1 | 37 | `realOnly` |
| **Summe** |  |  | **25** | **928** | **15 `realOnly`** |

</details>

25 ist die Summe der Film-Beobachtungen je Profilgruppe und keine Zahl eindeutiger Filme. 928 ist die Zahl der Bilder.

## Wie sie entstehen

1. Aufnahme und Sortierung. Die Quellen werden nach Scanner, Filmart, Filmname und Filmbezeichnung getrennt. Drehung und Dateiparsing werden vor der Analyse bestätigt, leere oder nicht lesbare Dateien zählen nicht.
2. Bildmessung. Je Bild werden Helligkeitsperzentile und Beschnitt an beiden Enden, die Kanalbeziehungen in Tiefen, Mitten und Lichtern, die Verteilung von Sättigung und Farbton, die Lab-Neutralachse schwach gesättigter Pixel sowie Gradient, Schärfe und ein Kornreferenzwert gemessen. Das sind Szenenbeobachtungen. Belichtung oder Motiv eines einzelnen Bildes werden nie zur festen Eigenschaft des Scanners erklärt.
3. Szenengruppen. Szenen werden nach Helligkeit, Kontrast, Sättigung und Farbtonbereich gruppiert. Anzahl und Verteilung je Gruppe werden festgehalten, damit eine einzige Szenenart das Profil nicht beherrscht.
4. Repräsentative Bilder. Das kontrastreichste Bild, das schärfste Bild, das Bild mit dem höchsten Kornreferenzwert und Bilder, die den Helligkeits- und Sättigungsbereich vertreten, werden gesondert festgehalten, damit sich ein Mensch zur Quelle zurückverfolgen kann.
5. Aggregation nach Film und Gruppe. `scripts/compile_scanner_profiles.py` fasst die Daten je Film zu Film- und Scannergruppen zusammen. Leere Klassen werden nicht als Beobachtungen mit Wert null dargestellt, alle Werte müssen endlich sein und die Stichprobenzahlen echt.
6. JSON und Hashes. Die fertige Datei trägt Schema, ID, Quellzahlen, Quellpfade, aggregierte Statistik, Prüfstatus und `profileHash`. Der Prüfer kontrolliert Felder, Zahlen, Endlichkeit, Dateiname gegen ID, Quellzahlen und den Hash.

## Form des JSON

<details>
<summary>Beispiel eines Profil-JSON</summary>

```json
{
  "schemaVersion": 2,
  "id": "noritsu__color-nega__kodak-portra-400",
  "displayName": "NORITSU · color nega · Kodak Portra 400",
  "scanner": "NORITSU",
  "kind": "color nega",
  "filmKey": "kodak portra 400",
  "validationStatus": "realOnly",
  "rollCount": 2,
  "imageCount": 75,
  "singleRollLimited": false,
  "sourceProfiles": [],
  "tone": {},
  "color": {},
  "neutralAxis": {},
  "neutralAxisBins": [],
  "hueResponse": [],
  "texture": {},
  "sceneBuckets": [],
  "coverageCandidates": [],
  "profileHash": "sha256:..."
}
```

</details>

## Wichtige Einträge

| Eintrag | Inhalt | Zu beachten |
|---|---|---|
| `tone` | Helligkeitsverteilung und Beschnitt an beiden Enden | Die Belichtung eines Bildes ist keine Geräteeigenschaft |
| `color` | Kanäle und Sättigung in Tiefen, Mitten, Lichtern | Eine beobachtete Verteilung, keine absolute Farbmatrix |
| `neutralAxis` | Lab-`a*` und -`b*` schwach gesättigter Pixel | Manche Szenen haben kein neutrales Objekt, deshalb gehören die Stichprobenzahlen dazu |
| `hueResponse` | Sättigungsänderung und Farbtondrehung je Farbtonklasse | Relativer Vergleich nur, wenn die Daten beider Geräte zusammenpassen |
| `texture` | Gradient, Schärfe, Kornreferenzwert | Nicht direkt als Schärfungswert des Geräts verwendet |
| `sceneBuckets` | Statistik je Szene und repräsentative Bilder | Erlaubt es, die Quelle wieder zu verfolgen |

Die Schärfung des Helligkeitskanals im Ziel `HS` ist keine aus `texture` gemessene Gerätekonstante und erzeugt kein neues Korn. `SP`, `MAIN` und `PRINT` enthalten diese Schärfung nicht.

## Belegstatus

| Status | Bedeutung | Wo verwendbar |
|---|---|---|
| `draft` | Daten oder Schema unfertig | Weder für die Auslieferung noch für automatische Nutzung |
| `realOnly` | Echte Scans liegen vor, aber kein getrenntes Referenzmaterial | Nur manuelle Auswahl, keine Genauigkeitsaussage |
| `pairedSmoke` | Gepaartes Material bestätigt nur den Verarbeitungsweg | Als Qualitätsbeleg nicht verwendbar |
| `pairedValidated` | Hat Kalibrier- und Validierungsmaterial sowie Regressionsprüfungen bestanden | Automatische Auswahl erlaubt, wenn die Richtlinie es zulässt |

Alle 15 sind heute `realOnly`. Man kann bestätigen, dass sie aus Beobachtungen echten Materials stammen, nicht aber, dass sie dasselbe Ergebnis liefern wie die Maschine.

Eine Aussage zur Geräte-Genauigkeit braucht mehr Material:

- Eine ID, die dasselbe physische Bild bestätigt
- Von der Kalibrierung getrenntes Validierungsmaterial
- Die Bedingungen, unter denen die Referenzbilder entstanden
- Scannereinstellungen und Entscheidungen des Bedieners
- Charge des Targets, Beleuchtung und Messmethode
- Ein Bestehenskriterium je Bild

## Wie die App sie nutzt

### Manuelle Auswahl

Aus einem Modellnamen oder Dateiinformationen wird nichts automatisch ausgewählt. Das Ziel `HS` oder `SP` und das Profil wählen Sie selbst. Automatisches Zuordnen ist nur für `pairedValidated` erlaubt und gilt daher nicht für das aktuelle Paket.

### Der relative Unterschied zwischen zwei Scannern

Absolute Szenenstatistik wird nicht unverändert verwendet. Es wird nur der Unterschied zwischen passenden Gruppen beider Geräte genutzt, und nur eingeschränkt:

- Die bereinigte Menge der Filmnamen muss übereinstimmen.
- Die Bildzahl darf um höchstens 15 % abweichen.
- Eine Farbtonklasse braucht auf beiden Seiten Stichprobenzahlen über dem Schwellwert.
- Werte, deren Richtung kippt, werden nicht angewendet.
- Werte zwischen gegenläufigen Gewinnen werden im Logarithmusraum berechnet.
- Der Tonwert wird einmal auf die Rec.709-Gammahelligkeit angewendet, die Lab-Farbanteile bleiben erhalten.

Die Quellprofile tragen keinen SHA-256 je Bild, und gleiche Filmnamen belegen nicht, dass dieselben Bilder gepaart wurden.

### Schwarzweiß und Positiv

Bei Schwarzweiß entfallen die Farbanteile, nur der relative Tonwert wird genutzt. Bei Positiv wird die absolute Helligkeit eines Films nicht auf ein anderes Foto übertragen. Die Basisstile von `HS` und `SP` wirken auf Positive jedoch mit halber Stärke, das Ergebnis ist also nicht immer dasselbe wie bei `MAIN`.

### Textur

Ohne gepaartes Material desselben Bildes wird `texture` nicht als gerätespezifischer Schärfungs- oder Kornwert genutzt. Fokus, Motiv, JPEG-Verarbeitung und die Entscheidungen des Laborbedieners sind in diese Zahlen alle eingeflossen.

## Dateiintegrität

`ScannerProfileRegistry` öffnet nie nur einen Teil der 15:

1. Das Manifestschema lesen.
2. Bestätigen, dass jede Datei existiert, und ihren SHA-256 prüfen.
3. `profileHash` in jedem JSON neu berechnen.
4. ID, Dateiname, Schema, Status, Zahlen und Endlichkeit prüfen.
5. Stimmt etwas nicht, das ganze Paket ablehnen.
6. Nur einen schreibgeschützten Schnappschuss zwischenspeichern, bei dem alles stimmte.

Das Exportprotokoll hält die ID und den SHA-256 des tatsächlich verwendeten Profils fest.

## Prüfbefehle

Aus `negaflow-mac/` aufzurufen. Der erste prüft den Profilvertrag, der zweite baut die Profile neu, der dritte ist die REAL/TARGET-Qualitätsprüfung.

```bash
python3 scripts/validate_scanner_profiles.py \
  --mode profile-contract \
  --profiles Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/compile_scanner_profiles.py \
  --source LUT_target/SOURCE \
  --out LUT_target/PROFILES \
  --resource-out Sources/Chromabase/ScannerProfiles
```

```bash
python3 scripts/evaluate_profile_quality.py \
  --manifest LUT_target/quality/corpus-v1.json \
  --candidate-summary LUT_target/SOURCE/summary.json \
  --baseline-summary LUT_target/quality/accepted-summary-v1.json \
  --data-root LUT_target \
  --verify-files all \
  --report build/profile-quality-report.json
```

Das Repository enthält kein REAL/TARGET-Manifest und keine akzeptierte Basis, die eine Freigabeaussage stützen. Die synthetischen Tests bestätigen nur die Fehlerbedingungen des Prüfcodes, nicht die Genauigkeit der Profile.

## Quellen

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)
- [darktable negadoctor](https://docs.darktable.org/usermanual/4.6/en/module-reference/processing-modules/negadoctor/)

Aus diesen Quellen wurden keine Profilzahlen übernommen. Sie dienten als Hintergrund dafür, warum Filmbasis, Szenentonwert und Gerätestil getrennt behandelt werden müssen. Die JSON-Werte stammen aus dem für dieses Projekt fotografierten Material und dem Analysecode im Repository.

## Code und verwandte Dokumente

- `Sources/Chromabase/ScannerProfiles/`
- `Sources/Chromabase/Profiles/ScannerProfile/`
- `Sources/Chromabase/Profiles/ScannerTargetGrade/`
- `scripts/compile_scanner_profiles.py`
- `scripts/validate_scanner_profiles.py`
- `scripts/evaluate_profile_quality.py`
- [Qualitätsprüfung der Scannerprofile](../reference/PROFILE_QUALITY_GATE.md)
- [IT8-Farbprüfung](../reference/IT8_COLOR_VALIDATION.md)
- [Chroma Engine](CHROMA_ENGINE.md)
