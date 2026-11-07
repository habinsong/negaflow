# Scanner-Rauschprofile

[Dokumentationsstart](../README.md)

Aus einem gewöhnlichen Foto lässt sich kein Rauschprofil bauen, weil sein hochfrequenter Anteil Motiv und Filmkorn vermischt.

Scannen Sie ein gleichmäßiges oder gestuftes Ziel mindestens dreimal mit denselben Einstellungen. Die Änderung des Pixelwerts an derselben Stelle liefert die Varianz je Signalstufe.

- [ISO 15739:2023](https://www.iso.org/standard/82233.html) legt fest, wie das Rauschen je Signal bei digitalen Bildgeräten gemessen und berichtet wird.
- [ISO 21550:2004](https://www.iso.org/standard/35939.html) legt fest, wie der Dynamikumfang von Durchlicht- und Auflichtscannern gemessen wird.

ISO 15739 ist für Digitalkameras geschrieben. negaflow behauptet nicht, dass Scanner darunter fallen, und übernimmt nur die Ideen der Wiederholmessung und der Varianz je Signal.

> [!NOTE]
> Im aktuellen Paket gibt es kein Geräte-Rauschprofil mit `holdoutValidated`, daher greift keines automatisch. Texturwerte vorhandener Profile werden nicht als Sensor-Rauschdaten verwendet.

## Was ein Profil abdeckt

`ScannerNoiseProfile` passt nur, wenn alle diese Angaben gleich sind:

- Hersteller und Modell des Scanners
- Auflösung in DPI
- Bittiefe je Kanal
- Farbmodus
- Mehrfachbelichtung an oder aus

Werte eines ähnlichen Modells oder einer anderen Auflösung werden nicht übernommen. Passen mehrere automatische Profile genau, schlägt die Wahl fehl, statt eines auszusuchen.

Aus mindestens drei linearen RGB-Scans derselben Szene wird je Kanal angepasst:

```math
\operatorname{variance}(x) = m_{\mathrm{shot}}x + b_{\mathrm{read}}
```

Das Profil hält außerdem fest:

- SHA-256 des Kalibriermaterials
- Zahl der gemessenen Bilder und Stichproben
- Den beobachteten Signalbereich
- Das R² der Regression
- Die validierte Stärke der Rauschminderung

Die Maximalstärke im Code schützt nur vor einer fehlerhaften Berechnung. Sie ist keine Qualitätsgrenze.

## Zustände

| Zustand | Bedeutung | Automatische Anwendung |
|---|---|---|
| `draft` | Messung oder Abstimmung unfertig | Nein |
| `measured` | Wiederholmessung an einem echten Gerät, keine unabhängige Validierung | Nein |
| `holdoutValidated` | Stärke an getrenntem Validierungsmaterial geprüft | Nur bei genauer Übereinstimmung |

Für die automatische Nutzung braucht es genau ein passendes `holdoutValidated`-Profil, und die SHA-256 von Kalibrier- und Validierungsmaterial sowie die Prüfungen der Dateistruktur müssen bestehen. `draft` und `measured` können die vorhandenen allgemeinen Einstellungen nicht ändern.

## Stand

Die Farbprofile NORITSU und SP-3000 im Repository tragen `texture`-Werte aus echten Szenen. Sie mischen Motiv, Fokus und Filmkorn und taugen nicht als Sensor-Rauschdaten.

Wiederholt aufgenommene gleichmäßige Ziele und getrenntes Validierungsmaterial gibt es noch nicht. Es ist kein validiertes Geräte-Rauschprofil gebündelt, und der automatische Pfad nutzt die vorhandenen allgemeinen Einstellungen.

Ein echtes Profil braucht alles Folgende:

1. Drei oder mehr lineare Scans mit demselben Gerät, derselben Auflösung, Bittiefe, demselben Farbmodus und derselben Mehrfachbelichtung
2. Dateiliste und SHA-256 des Kalibriermaterials
3. Eine nicht zur Kalibrierung verwendete Validierungsszene samt SHA-256
4. Einen Vergleich von Rauschminderung gegen Erhalt von Detail und Filmkorn
5. Eine Prüfung bei 100 % Vergrößerung durch einen echten Nutzer

Die Aufnahme an echter Hardware übernimmt das Plug-in `negaflow-scanner-sane`. SANE-Optionen und Gerätesteuerungscode kommen nicht in dieses Repository.
