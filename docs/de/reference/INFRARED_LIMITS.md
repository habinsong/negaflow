# Filme, die GrainMend IR meidet

[Dokumentationsstart](../README.md)

Die Infrarotreinigung liest sichtbares und infrarotes Bild getrennt und legt sie übereinander, um Defekte zu finden. Das passt nicht zu jedem Film.

- Normaler Farbfilm und chromogener Schwarzweißfilm können IR nutzen.
- Gewöhnlicher Schwarzweißfilm behält sein Silber, blockt damit IR und liefert eine falsche Defektkarte.
- Kodachrome dämpft IR anders als andere Farbfilme, deshalb wird zu wenig oder zu stark korrigiert.

Belege:

- [Technische Hinweise und Grenzen von Epson](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson-Tabelle der Filmtypen](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast zu Schwarzweiß und Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> Lässt sich das Filmmaterial nicht bestimmen, wird IR nicht automatisch angewendet. Eine falsche IR-Maske löscht echte Bildstruktur als Defekt.

## Wo es automatisch greift

Entscheidend ist nicht, ob der Film negativ oder positiv ist, sondern **was das Bild bildet**. Farbfilm bleicht sein Silber bei der Entwicklung heraus und behält nur Farbstoff, und Farbstoff ist für Infrarot durchlässig. Schwarzweißfilm ist ein Silberbild und blockt Infrarot ab; die Korrektur würde die Aufnahme selbst als einen einzigen großen Defekt lesen und löschen.

| Filmtyp | Automatisches IR | Grund |
|---|---|---|
| Farbnegativ | Bedingt | Farbstoffbild. Das Plugin muss IR melden und die Ausrichtungsprüfung bestehen |
| Farbpositiv | Bedingt | Farbstoffbild. Dieselben Bedingungen wie beim Farbnegativ |
| Schwarzweiß-Negativ und -Positiv | Aus | Das Silberbild blockt Infrarot ab |

`FilmType` trennt chromogenes Schwarzweiß nicht von silberbasiertem und Kodachrome nicht von einem normalen Dia. Zwei Fälle bleiben deshalb beim Anwender.

- Chromogenes Schwarzweiß wird als Schwarzweiß gescannt; IR bleibt also aus, obwohl der Film es zuließe. Aus dem Filmtyp allein wird nichts geraten.
- Kodachrome ist ein Farbdia, IR wird also angeboten. Seine Farbstoffe schwächen Infrarot anders als E-6, ein Defekt kann dadurch unter- oder überkorrigiert werden. Schalten Sie die Ebene ab, wenn das Ergebnis falsch aussieht.

## Ausrichtungsprüfung

`InfraredDefectRemoval` vergleicht die Durchschlagstextur im IR mit dem Rotkanal des RGB und sucht einen ganzzahligen Versatz. Das Ergebnis trägt `AlignmentDiagnostics`.

| Zustand | Bedeutung |
|---|---|
| `notRequested` | Der Aufrufer hat angegeben, dass beide Ebenen bereits passen |
| `aligned` | Die Korrelation liegt über der Schwelle, das Optimum im Suchbereich |
| `insufficientTexture` | Im IR fehlen Anhaltspunkte für die Ausrichtung |
| `weakCorrelation` | Die Korrelation bleibt unter der Schwelle |
| `searchLimitReached` | Das Optimum liegt auf der Suchgrenze |

Die letzten drei werden nicht durch `(0,0)` ersetzt. Sie brechen mit dem Fehler `alignmentUnreliable` ab. Liegt das Optimum auf der Suchgrenze, gilt das unabhängig vom Betrag des Versatzes als Fehlschlag.

Automatische Tests ersetzen weder die RGB/IR-Ausrichtung am echten Gerät noch Ergebnisse je Film. Prüfungen am echten Scanner laufen von Hand, mit echtem Film.

SANE-Gerätesteuerung und Aufnahmecode liegen nur im separaten Repository `negaflow-scanner-sane`.
