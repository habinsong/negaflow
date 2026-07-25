# Feste Printantwort

[Dokumentationsstart](../README.md)

Wo es liegt:

- Swift: `PrintResponse` in `Sources/Chromabase/Film/NegativeInversion.swift`
- Metal: der Kernel `negativeInvert`
- Fixierender Test:
  `NegativeInversionCalibrationTests.testPrintResponseDerivesFromPhotometricContract`

## Die Kurve

Eine Filmkennlinie erklärt Belichtung gegen Dichte über Fuß, Geradenteil und Schulter. Negaflow
nähert die Schulter im Dichtebereich mit einer gestreckten Exponentialkurve an.

```math
\begin{aligned}
D &= \log_{10}\left(\frac{D_{\min}}{T}\right) \\
d &= \frac{D}{d_{\max}} \\
\log_{10}(P) &= y_{\mathrm{ceil}} - A \exp\left(-(r d)^s\right)
\end{aligned}
```

`A`, `r` und `s` sind Kurzformen von `amplitude`, `rate` und `shape` im Code. `d_{\max}` ist
`dmaxNorm`.

- `D`: optische Dichte ohne den Filmträger
- `d`: dieser Wert geteilt durch den genutzten Dichtebereich
- `P`: lineare Ausgabehelligkeit

Die Kurve steigt über den ganzen Bereich. Für `d ≥ 0` landet die Ausgabe in
`[baseToe, ceiling)`. Werte unter null, etwa ein Hintergrundlicht heller als der Träger oder die
Perforation, werden nicht auf null beschnitten. Sie laufen als endliche positive Werte weiter.

```math
y(-|d|) = 2\log_{10}(P_{\mathrm{toe}}) - y(|d|)
```

Auch die Umkehrfunktion hat eine geschlossene Form. Sie dient synthetischen Negativen und
Hin-und-zurück-Prüfungen.

```math
d = \frac{\left[\ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(P)}\right)\right]^{1/s}}{r}
```

## Die vier Ankerpunkte

Kurvenkoeffizienten werden nicht gespeichert. Sie werden aus diesen Werten berechnet.

| Ankerpunkt | Farbe | Schwarzweiß | Wozu |
|---|---:|---:|---|
| `P(0)` Trägerschwarzpunkt | 0.001 | 0.0005 | Hält es weg von 8-Bit-Code 0 |
| `P(midFraction)` Mittelgrau | 0.18 | 0.18 | 18-%-Grau |
| `P(1)` Weiß | 0.70 | 0.85 | Helligkeit der gemessenen dichtesten Stelle |
| `P(∞)` Obergrenze | 0.90 | 0.98 | Reserve für reflektiertes Licht |

`midFraction` ist `0.60D / 1.55D`, etwa `0.387`.

Die Koeffizienten berechnen:

```math
\begin{aligned}
y_{\mathrm{ceil}} &= \log_{10}(P_{\mathrm{ceil}}) \\
A &= y_{\mathrm{ceil}} - \log_{10}(P_{\mathrm{toe}}) \\
r_X &= \ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(X)}\right) \\
s &= \frac{\ln(r_{\mathrm{white}}/r_{\mathrm{mid}})}
          {\ln(1/f_{\mathrm{mid}})} \\
r &= r_{\mathrm{white}}^{1/s}
\end{aligned}
```

## Standard-Dichtebereich

`normalRange` ist nicht die physikalische Maximaldichte des Films. Es ist der Bereich, den eine
normal belichtete Szene nutzt. Er zählt vor allem, wenn der Träger nicht gemessen werden konnte
oder der Szenenkontrast sehr gering ist.

```math
\begin{aligned}
\operatorname{normalRange}(\mathrm{color}) &= 0.62 \times 2.5 = 1.55\,D \\
\operatorname{normalRange}(\mathrm{B\&W}) &= 0.62 \times 3.5 = 2.17\,D
\end{aligned}
```

- `0.62`: grobe Steigung des Geradenteils einer C-41-Kennlinie
- Farbe `2.5`: etwa 7⅓ Blenden diffuse Leuchtdichte plus Lichterreserve
- Schwarzweiß `3.5`: Praxis der Schwarzweißvergrößerung mit längerem Geradenteil
- `0.60D`: Mittelgraudichte einer normal belichteten Szene

`applySceneRanged` misst statt dieses Werts den Dichtebereich, den das Bild je Kanal wirklich
nutzt.

## Was sich in v4 geändert hat

Früher gab es eine in drei Abschnitte geteilte Funktion und feste Presets. v4 nutzt eine Kurve
und vier Ankerpunkte. Es gibt keine Abschnittsgrenzen, und jeder Wert lässt sich in Code und
Tests nachvollziehen.

Gegenüber dem alten Ergebnis:

- Farbige Mitten und Lichter, normierte Dichte 0,3 bis 1,1: innerhalb ±0,05 Blenden
- Tiefe farbige Schatten, 0,1 bis 0,2: etwa −0,2 Blenden
- Farbiger Trägerschwarzpunkt: etwa +0,25 Blenden
- Schwarzweiß: Schatten etwa −0,4 Blenden, Mitten etwa +0,1 Blenden
- Der Mittelgrau-Ankerpunkt 0,18 von NORITSU/FUJI bleibt

## Quellen und Umfang

Fuß, Geradenteil, Schulter und Gamma stammen aus der veröffentlichten Sensitometrie. Kein
Kurvenkoeffizient aus dieser Literatur wurde übernommen. Negaflow rechnet seine eigenen aus den
vier Ankerpunkten oben.

- [Sensitometry](https://en.wikipedia.org/wiki/Sensitometry)
- [Hurter–Driffield Characteristic Curve](https://studyguides.com/study-methods/overview/cmpanf83znm1201neitjb4waw)
- [Vergleich von RA-4-Papieren](https://tinker.koraks.nl/photography/on-a-color-mission-comparing-two-ra4-color-papers/)

Bekannte Kontrastumfänge von RA-4-Material werden nicht direkt übernommen. Der Kontrast dieser
Kurve kommt aus dem `shape`, das sich aus den vier Ankerpunkten ergibt.
