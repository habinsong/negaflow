# IT8-Farbprüfung

[Dokumentationsstart](../README.md)

Farbgenauigkeit braucht Messungen, nicht nur Augenschein. Ein IT8-Bild wird mit der Referenzdatei seines physischen Targets gepaart, und für jedes Feld werden Zahlenergebnisse festgehalten.

> [!IMPORTANT]
> Öffentliches IT8-Material kann Regressionen im Prüfer und in der Farbrechnung bestätigen. Es kann weder die Genauigkeit eines echten Scanners noch die von Farbnegativfilm beweisen. Um ein Gerät zu beurteilen, braucht es ein bestätigtes physisches Target und echte Messungen an diesem Gerät.

## Arten von Belegen

| Name | Was er bestätigt | Was er nicht bestätigt |
|---|---|---|
| `algorithmRegression` | Dateiparsing, ICC-Umrechnung, Feldflächen, Lab, CIEDE2000 | Die Genauigkeit eines echten Scanners |
| `deviceCharacterization` | Ein bestätigtes physisches Target, an einem echten Gerät gemessen | Die Genauigkeit eines anderen Targets oder Geräts |
| `syntheticModel` | Die mathematische Hin- und Rückrechnung eines unabhängigen synthetischen Modells | Die Genauigkeit echten Films oder Geräts |

`deviceCharacterization` braucht Hersteller, Material, Seriennummer und Charge des physischen Targets. Weicht eines davon vom Kopf der Referenzdatei ab, wird nichts ausgewertet.

Durchlicht-Targets nach IT8.7/1 und ISO 12641-1 sind für positive Durchsichtsvorlagen gedacht. Ihre Ergebnisse sagen nichts über die orange Maske von Farbnegativen, Farbstoffwechselwirkung, C-41-Schwankungen oder die Ausgabegenauigkeit von HS und SP. Solche Aussagen brauchen gepaartes Material desselben Farbnegativs über beide Pfade sowie einen getrennten Validierungssatz.

Das öffentliche FADGI-OpenDICE-Paar aus Bild und Referenz wurde an 264 Feldern gemessen: Median ΔE00 9,8815, p95 13,2745, Maximum 15,5996. Eine unabhängige LittleCMS-Umrechnung wich höchstens um 0,105 Lab-Einheiten vom Auswerter ab. Diese Beobachtungen bestehen keine Prüfung der Filmgenauigkeit: Der Scan ist ein positives IT8, seine physische Seriennummer ist ungeprüft, und es hängt keine Messung von Kamera, Licht und Film eines Negativs daran.

Auch öffentliche Negativ-Datensätze wurden geprüft. Die FADGI-Negativreferenzen enthalten nur Dichte, keine gemessenen Farbfelder. BlueNeg nennt seine restaurierten Referenzen Pseudo Ground Truth. Die ARRI-AQUA-Spektralstudie von 2024 gibt ihre Daten auf Anfrage heraus, nicht als freien Download. Keine liefert eine unabhängige Szenenfarbreferenz für die aktuelle Invertierung.

Eine [öffentliche Belichtungsreihe mit Kodak ColorPlus 200](https://discuss.pixls.us/t/any-interest-in-a-film-negative-feature-in-rt/12569/262) (fünf Sony-ILCE-7-RAW-Scans, −1 bis +3 EV) wurde ebenfalls untersucht. Ihre Karte ist eine Grey White Balance Colour Card, deshalb wurden X-Rite-Referenzwerte verworfen. Keines der 120 abgetasteten Feldgebiete erreichte im decodierten Kamera-RGB Null oder Vollaussteuerung. Das ist eine Prüfung des decodierten Signals, keine direkte Messung des Sensormosaiks und kein Ergebnis zur Farbgenauigkeit. Ohne gemessene Referenzen für diese Karte und den Scanaufbau lassen sich Farbstiche der Ausgabe nicht der Eingabe oder der Anwendung zuordnen. Die Dateien bleiben außerhalb des Repositorys, weil die Weitergaberechte nicht geklärt sind.

[FADGI](https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html) · [BlueNeg](https://huggingface.co/datasets/ttgroup/blueneg-release) · [Plutino 2024](https://doi.org/10.1002/col.22946)

## Öffentliches Regressionsmaterial

Diese beiden FADGI/OpenDICE-Dateien werden als Paar verwendet.

- Anleitung: <https://www.digitizationguidelines.gov/guidelines/digitize-OpenDice.html>
- Bild: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/IT8-7.1.tif>
  - SHA-256: `c62ee73f26390a2ad90e7e28280cbd1efb4f18834425bb7112ff1f8016832ffd`
  - Größe: `6255 x 4170`
  - Format: 16-Bit-RGB mit eingebettetem `Adobe RGB (1998)`
- Referenzdatei: <https://www.digitizationguidelines.gov/guidelines/OpenDICE/Profile_IT8-7.1.txt>
  - SHA-256: `19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840`
  - Felder: 264 Lab-Werte von `A1` bis `L22`
  - Spalte 16: Dichte

Die Weitergaberechte sind nicht bestätigt, deshalb bleiben die Dateien außerhalb von Repository und App. Laden Sie sie selbst herunter und lassen Sie das [Beispielmanifest](../../reference/IT8_FADGI_OPENDICE.example.json) darauf zeigen. Seine Stufe ist `algorithmRegression`, und eine Umbenennung in `deviceCharacterization` lässt der Prüfer nicht zu. Aufruf aus `negaflow-mac/`:

```bash
swift run negaflow it8-bench ../docs/reference/IT8_FADGI_OPENDICE.example.json \
  --image /path/to/IT8-7.1.tif \
  --reference /path/to/Profile_IT8-7.1.txt \
  --out /path/to/it8-report.json
```

## Messregeln

- Weicht der SHA-256 von Bild, Referenzdatei oder gewähltem ICC vom Manifest ab, bricht der Lauf ab.
- Bericht v2 hält zusätzlich den SHA-256 des Manifesttextes fest.
- `A01` und `A1` lesen dieselben Koordinaten, die ursprüngliche ID bleibt im Bericht.
- Die mittleren 60 % jedes Feldes im 22-mal-12-Raster werden in Quellauflösung als Gleitkomma gelesen, in den Zeilen `A`–`L` und den Spalten `1`–`22`.
- Das eingebettete ICC wird beachtet.
- Gerechnet wird von linearem sRGB D65 nach XYZ, per Bradford-Adaption nach D50, dann nach Lab D50/2°.
- Jedes Feld hält Fläche, Pixelzahl, RGB-Mittelwert und Standardabweichung, den Beschnittanteil an beiden Enden, die Zahl nicht endlicher Werte, Referenz- und Mess-Lab, L/a/b-Differenzen und CIEDE2000 fest.
- Median, p95 und Maximum sind Beobachtungen, keine Bestehensgrenze. Ein Durchschnittsschwellwert wird nicht grundlos erfunden, und `qualityDecision` bleibt `notEvaluated`.
- Ein Target, mit dem ein Profil angepasst wurde, wird nicht für die unabhängige Validierung wiederverwendet.

### Angaben zum physischen Target

Bei einer Messung an einem echten Gerät liest der Bediener diese Angaben vom Etikett des Targets ab und notiert sie.

<details>
<summary>Beispiel für den Messblock</summary>

```json
{
  "measurement": {
    "samplerVersion": "center-mean-v1",
    "renderingIntent": "relativeColorimetric",
    "physicalTargetIdentity": {
      "manufacturer": "target label manufacturer",
      "material": "target label material",
      "serial": "target label serial",
      "batchMetadataKey": "PROD_DATE",
      "batchValue": "reference header production date"
    }
  }
}
```

</details>

`MANUFACTURER`, `MATERIAL`, `SERIAL` und der Chargenkopf (einer von `BATCH`, `BATCH_ID`, `PROD_DATE`) müssen Zeichen für Zeichen mit der Referenzdatei übereinstimmen. Die oberste `targetID` muss `serial` entsprechen und `batchID` dem `batchValue`.

Dieser Eintrag zeigt nur, dass das, was der Bediener geschrieben hat, und die Referenzdatei übereinstimmen. Er liest das Etikett nicht aus dem Bild und beglaubigt die Eingabe des Bedieners nicht. Fehlen Angaben, wird weder das nächstliegende Datum noch eine allgemeine Referenzdatei eingesetzt.

Enthält die Referenzdatei Angaben zu Lichtart oder Beobachter, werden sie gegen den D50/2°-Vertrag geprüft, und ein Widerspruch stoppt den Lauf. `measurement.renderingIntent` kann die Core-Image-Umrechnung heute nicht direkt festlegen, deshalb steht im Bericht `manifestDeclarationNotControlledByEvaluator`.

## Ausgabe `PRINT`

IT8.7/1 ist für Eingabegeräte gedacht. Für die Druckerausgabe braucht es ein RGB-Druckerprofil, das aus echten Messungen der Kombination aus Drucker, Papier, Tinte oder Chemie und Treiber- oder Prozessbedingung entstanden ist.

Reihenfolge von Prüfung und Verwendung:

1. ICC-Größe, Geräteklasse `prtr`, Datenraum `RGB `, Lab/XYZ-PCS und die Signatur `acsp` bestätigen.
2. Bestätigen, dass ColorSync in beide Richtungen umrechnen kann.
3. Bei der Auswahl Profilname, Bytes und SHA-256 festlegen.
4. Einmal auf die endgültige Ausgabe anwenden, nachdem das `MAIN`-Arbeitsbild und das Seitenlayout fertig sind.
5. Nicht auf `rawScanTIFF` oder `-main-flat` anwenden.
6. Ein fehlendes oder falsches Profil scheitert, bevor eine temporäre Ausgabe entsteht. sRGB springt nicht ein.

Es wird nicht behauptet, dass der aktuelle Pfad über Core Image und ColorSync Rendering Intent und Schwarzpunktkompensation auf jeder macOS-Version bitgenau festlegt.

## Synthetische Feldregression `MAIN`

`NegativeAutoBalanceTests` und `shoulder-print-response-v4`.

MAIN/CS nutzt in beiden Schalterzuständen die v4-Kurve. Die beibehaltenen v6-Tests prüfen ihr eigenes festes Primitiv, und die Nullabweichung zwischen Bildern in diesen Tests ist kein Ergebnis für Auto-Abgleich ON.

[Negativantwort](PRINT_RESPONSE.md)

## Regression des relativen Stils von HS und SP

Eine Referenzdatei mit 264 Lab-D50-Feldern von `A1` bis `L22` wird per SHA-256 festgelegt. Jedes Feld wird zu einem synthetischen Negativ, und die Pfade `MAIN`, `HS` und `SP` laufen je zweimal.

```bash
swift run negaflow scanner-relative-it8-bench \
  /path/to/Profile_IT8-7.1.txt \
  --sha256 sha256:19337b85f213eb4397e91c91298201f421ef3ca33b0ef6da3d752a0880491840 \
  --out /path/to/scanner-relative-it8-report.json
```

Der Bericht enthält RGB und Lab je Feld, `DeltaE00` gegen die Referenz, relatives `DeltaE00` zwischen den Zielen sowie Kennzeichen für Beschnitt und nicht endliche Werte. Die Monotonie der neutralen Rampe wird aus der Dichtespalte `A16...L16` gelesen.

Farben, die nach der Umrechnung in lineares sRGB außerhalb von 0...1 liegen, lassen sich als synthetisches Negativ nicht exakt aufbauen und werden daher auf den darstellbaren Bereich begrenzt. Statistiken über den weiten Bereich sind darum Beobachtungen, keine Bestehensgrenze.

Die Belegstufe ist immer `syntheticModel`, die Entscheidung immer `notEvaluated`. Stimmt das Profilmanifest oder der SHA-256 einer Datei nicht, bricht der Lauf ab. Die Genauigkeit einer echten Maschine braucht Scans desselben physischen Negativs auf beiden Maschinen sowie getrenntes Validierungsmaterial.

D50/2° wurde nicht aus dem Kopf der Referenzdatei bestätigt. Es ist der eigene Vertrag des Prüfstands, Lab als D50/2° zu lesen, daher ist `colorimetryInterpretationProvenance` gleich `benchmarkContractNotVerifiedFromReferenceHeader`.
