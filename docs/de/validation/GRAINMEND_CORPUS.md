# GrainMend-Vergleich an echten Scans

[Dokumentationsstart](../README.md)

Für die Regressionsprüfung von GrainMend RGB dient FILM-R v2.

| Punkt | Wert |
|---|---|
| Beschädigte und handrestaurierte Dateien | je 44 |
| Lizenz | CC BY 4.0 |
| Gesamtgröße | 437.570.872 Byte |
| Ablage | `build/defect-corpus/` |
| Wofür | Regressionsvergleich für GrainMend RGB |

## Das Material

- Titel: *Authentically damaged & manually restored film scans*
- Autorin: Daniela Ivanova
- DOI: <https://doi.org/10.6084/m9.figshare.21803304.v2>
- Aufsatz: <https://doi.org/10.1111/cgf.14749>
- Beschreibung: <https://daniela997.github.io/FilmDamageSimulator/>
- Lizenz: CC BY 4.0
- Inhalt: 44 beschädigte 35-mm-Filmscans und 44 fachliche Handrestaurierungen
- Gesamtgröße: 437.570.872 Byte

Die Bilder bleiben außerhalb des Repositorys. `Config/defect-corpus-film-r-v2.json` hält
DOI-Version, Lizenz, Paarzahl und Gesamtgröße fest. Das Abrufskript prüft MD5 und Größe je Datei,
wie Figshare sie angibt. Downloads und Ergebnisse liegen in `build/defect-corpus/`, das Git
ignoriert.

## Abrufen

Der einfache Befehl holt ein Paar für einen schnellen Blick.

<details>
<summary>Abrufbefehle</summary>

```bash
python3 scripts/defect-corpus/fetch-film-r.py
```

Alle 44 Paare:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --all
```

Blockt das Datei-CDN von Figshare automatische Anfragen, laden Sie das ZIP auf der Datensatzseite
über `Download all` und prüfen Sie es unverändert. Das Entpacken gelingt nur, wenn Dateinamen,
Größen und Figshare-MD5 im ZIP alle zum festgelegten Vertrag passen.

```bash
python3 scripts/defect-corpus/fetch-film-r.py \
  --archive ~/Downloads/21803304.zip \
  --all
```

Nur ein Fall:

```bash
python3 scripts/defect-corpus/fetch-film-r.py --case portra400_135_1
```

</details>

## Vergleich ausführen

Legen Sie die beschädigten Dateien und die Restaurierungen, deren Namen auf `_restored` enden, in
denselben Ordner.

<details open>
<summary>Befehl für die 44 Paare</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run -c release negaflow defect-bench build/defect-corpus/film-r-v2 \
  --reference-dir build/defect-corpus/film-r-v2 \
  --out build/defect-corpus/film-r-v2-report \
  --metrics-only
```

</details>

`--metrics-only` schreibt keine großen PNGs. Ohne die Option entstehen zusätzlich `before`,
`after`, `diff`, `mask` und 100-%-Ausschnitte für die Sichtprüfung.

Was im Bericht steht:

- Zahl der Funde, Konfidenz, Zahl geänderter Pixel, Verarbeitungszeit
- PSNR und mittlerer absoluter Fehler zwischen beschädigter Datei und fachlicher Restaurierung
- PSNR und mittlerer absoluter Fehler zwischen GrainMend-Ergebnis und fachlicher Restaurierung
- Änderung des PSNR
- Anteil der Pixel, deren Fehler gegenüber der Referenz sinkt oder steigt

Der FILM-R-Aufsatz nutzt PSNR, SSIM und LPIPS zusammen. Dieses Repository nimmt keine neue
ML-Abhängigkeit auf und berechnet deshalb nur PSNR und absoluten Fehler mit der
Standardbibliothek.

Diese Zahlen allein geben keine Auslieferung frei. Auch Handrestaurierungen enthalten
gestalterische Entscheidungen und JPEG-Unterschiede. Die automatische Qualitätsuntergrenze für
einen erneuten Lauf mit demselben Material und denselben Einstellungen steht in
`Config/defect-removal-film-r-v2-baseline.json`. Für die endgültige Entscheidung braucht es
`before`, `after`, `diff`, `mask` und die 100-%-Ausschnitte nebeneinander.

> [!CAUTION]
> Die Bildqualität von GrainMend wird nicht über PSNR oder mittleren Fehler allein freigegeben.
> Schäden an echter Textur und Fehlfunde beurteilt man aus Vorher- und Nachher-Bild,
> Differenzbild, Maske und 100-%-Ausschnitten zusammen.

Mit diesem Material lässt sich nur der GrainMend-RGB-Pfad auf gerenderten Bildern prüfen. Es
belegt weder RAW-Dekodierung noch Genauigkeit der Filmumkehr, IR-Ausrichtung oder das Verhalten
eines echten Scanners.

## Ergebnis vom 2026-07-25

Alle 44 Paare liefen auf einem Release-Build mit `--metrics-only --crops 0`. Die bisherige
Regressionsbasis mit Empfindlichkeit 3.0 wurde gegen 0.7 verglichen, den automatischen Pfad der
Auslieferung.

| Kennzahl | Bisherige Basis 3.0 | Sicheres Auto 0.7 |
|---|---:|---:|
| Bewertete Bilder | 44 | 44 |
| PSNR besser / schlechter / gleich | 11 / 33 / 0 | 34 / 6 / 4 |
| Mittlere PSNR-Änderung | -1,688 dB | +0,466 dB |
| Mediane PSNR-Änderung | -0,237 dB | +0,118 dB |
| Schlechteste PSNR-Änderung | -18,952 dB | -1,338 dB |
| Gewichtete verbesserte Pixel | 0,128 % | 0,029 % |
| Gewichtete verschlechterte Pixel | 0,792 % | 0,017 % |
| Gewichtete geänderte Pixel | 0,794 % | 0,043 % |
| Automatischer Sicherheitsstopp | keiner | 3 Bilder |

Der alte Standardwert der App lag bei 6.0 und war noch offensiver als die Basis 3.0. Der
automatische Pfad der Auslieferung geht auf 0.7 herunter, und die Erkennung feinster Partikel ist
standardmäßig aus. Übersteigen die Kandidaten 2 % einer Kachel, fallen die Komponenten weg, die
diese Kachel berühren. Geht eine Kachel über 5 %, oder liegen die Kandidaten nach der Filterung
insgesamt über 0,06 %, wird auf dieses Foto keine automatische Reparatur angewendet. Der Nutzer
kann den Bereich stattdessen mit Guided eingrenzen.

Diese Sicherheitslinie gilt nur für Auto. Erkennungsbereich und Reparaturverhalten von Guided,
Pinsel, Klonstempel und IR werden davon nicht eingeschränkt.

`Config/defect-removal-film-r-v2-baseline.json` prüft neben der beobachteten Regressionsbasis
diese absoluten Untergrenzen.

- Mindestens 30 verbessert, höchstens 10 verschlechtert
- Mittlere und mediane PSNR-Änderung bei 0 dB oder besser
- Schlechteste PSNR-Änderung bei -1,5 dB oder besser
- Gewichtete verschlechterte Pixel bei höchstens 0,03 %
- Insgesamt geänderte Pixel bei höchstens 0,06 %

Gegenüber der bisherigen Basis verbessert dieser Lauf 23 Bilder mehr, verschlechtert 27 weniger
und hebt den schlechtesten Fall um 17,614 dB. Sechs Bilder liegen im PSNR trotzdem unter der
fachlichen Restaurierung. FILM-R liefert echte Schäden und Handrestaurierungen und trägt zugleich
die Unschärfe restauratorischer Entscheidungen. Material und Aufsatz stehen beim
[FILM-R-Projekt](https://daniela997.github.io/FilmDamageSimulator/) und im
[FILM-R-Aufsatz](https://arxiv.org/abs/2302.10004).

Dichte Kandidaten aus Auto herauszunehmen passt zu früheren Arbeiten der Bildrestaurierung, die
Fehlfunde in strukturreichen Bereichen senken. Trotzdem lässt sich aus diesem Ergebnis nichts
davon behaupten.

- Das automatische Ergebnis schlägt bei jedem Foto die Handrestaurierung.
- GrainMend RGB ist dasselbe wie Hardware-IR-Reinigung.
- RGB/IR-Ausrichtung und optische Qualität eines echten Scanners sind belegt.

Der vollständige Lauf startet im manuellen Workflow `GrainMend corpus`. Zusätzlich zum
automatischen Qualitätsgate braucht es die Sichtprüfung der 100-%-Ausschnitte.
