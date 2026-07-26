# Scanner-Rauschprofile

[Dokumentationsstart](../README.md)

Aus einer gewöhnlichen Aufnahme lässt sich kein Rauschprofil bauen.
Im hochfrequenten Anteil einer Aufnahme stecken Motiv und Filmkorn zugleich.

Scannen Sie ein flaches oder gestuftes Target mindestens dreimal mit denselben Einstellungen.
Wie stark das Pixel an derselben Stelle wandert, ergibt die Varianz je Signalhelligkeit.

- [ISO 15739:2023](https://www.iso.org/standard/82233.html) regelt Messung und Angabe von
Rauschen je Signal bei digitalen Bildaufnahmegeräten.
- [ISO 21550:2004](https://www.iso.org/standard/35939.html) regelt die Messung des
Dynamikumfangs von Durchlicht- und Auflichtscannern.

ISO 15739 ist für Digitalkameras geschrieben. negaflow behauptet nicht, dass Scanner unter dieselbe
Norm fallen. Übernommen sind nur die Gedanken der wiederholten Messung und der Varianz je Signal.

> [!NOTE]
> Im aktuellen Bundle gibt es kein `holdoutValidated`-Geräterauschprofil, also wird auch keines
> automatisch angewendet. Texturwerte bestehender Profile dienen nicht als Sensorrauschdaten.

## Was ein Profil abdeckt

`ScannerNoiseProfile` gilt nur als Treffer, wenn all das gleich ist.

- Hersteller und Modell des Scanners
- Auflösung in DPI
- Bittiefe je Kanal
- Farbmodus
- Mehrfachbelichtung an oder aus

Werte eines ähnlichen Modells oder einer anderen Auflösung werden nicht geborgt.
Passen mehrere automatische Profile exakt, schlägt der Vorgang fehl, statt eines auszuwählen.

Aus mindestens drei linearen RGB-Scans derselben Szene wird je Kanal Folgendes angepasst.

```math
\operatorname{variance}(x) = m_{\mathrm{shot}}x + b_{\mathrm{read}}
```

Was neben dem Profil notiert wird:

- SHA-256 des Kalibriermaterials
- Zahl der gemessenen Bilder und Stichproben
- Der beobachtete Signalbereich
- R² der Regression
- Die geprüfte Stärke der Rauschminderung

Die Höchststärke im Code sichert nur gegen eine kaputte Berechnung ab.
Sie ist keine Qualitätsgrenze.

## Zustände

| Zustand | Bedeutung | Automatische Anwendung |
|---|---|---|
| `draft` | Messung oder Abstimmung nicht fertig | Nein |
| `measured` | Wiederholte Messung am echten Gerät, keine unabhängige Prüfung | Nein |
| `holdoutValidated` | Stärke an separatem Prüfmaterial bestätigt | Nur bei exaktem Treffer |

Für die automatische Nutzung braucht es genau ein passendes `holdoutValidated`-Profil.
Auch die SHA-256 von Kalibrier- und Prüfmaterial und die Strukturprüfungen der Dateien müssen
bestehen.
`draft` und `measured` ändern die bestehenden allgemeinen Einstellungen nicht.

## Wo es steht

Die NORITSU- und SP-3000-Farbprofile im Repository tragen `texture`-Werte aus echten Szenen.
Darin stecken Motiv, Schärfe und Filmkorn, also taugen sie nicht als Sensorrauschdaten.

Wiederholte Flat-Targets und separates Prüfmaterial gibt es noch nicht.
Ein geprüftes Geräterauschprofil liegt nicht bei, und der automatische Pfad nutzt die bestehenden
allgemeinen Einstellungen.

Für ein echtes Profil braucht es all das.

1. Mindestens drei lineare Scans mit gleichem Gerät, gleicher Auflösung, Bittiefe, Farbmodus und Mehrfachbelichtung
2. Dateiliste und SHA-256 des Kalibriermaterials
3. Eine Prüfszene, die nicht zur Kalibrierung diente, samt SHA-256
4. Ein Vergleich von Rauschminderung gegen Detail- und Filmkornerhalt
5. Eine Kontrolle bei 100 % Zoom durch echte Nutzung

Die Aufnahme an echter Hardware übernimmt das Plugin `negaflow-scanner-sane`.
SANE-Optionen und Gerätesteuerungscode kommen nicht in dieses Repository.
