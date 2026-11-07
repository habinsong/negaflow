# Filme, die GrainMend IR meidet

[Dokumentationsstart](../README.md)

Die Infrarotreinigung liest das sichtbare Bild und das Infrarotbild getrennt und legt beide übereinander, um Defekte zu finden. Sie passt nicht zu jedem Film.

- Normaler Farbfilm und Schwarzweißfilm auf Farbstoffbasis können IR nutzen.
- Gewöhnlicher Schwarzweißfilm behält sein Silber, das IR blockiert und eine falsche Defektkarte erzeugen kann.
- Kodachrome dämpft IR anders als anderer Farbfilm und kann deshalb unter- oder überkorrigiert werden.

Belege:

- [Epson technical notes and limits](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson film type table](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast on black and white and Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> Lässt sich das Filmmaterial nicht bestätigen, wird IR nicht automatisch angewendet. Eine falsche IR-Maske kann echte Bildstruktur als Defekt löschen.

## Wo es automatisch greift

Entscheidend ist, woraus das Bild besteht. Farbfilm behält nach der Entwicklung nur Farbstoff, und Farbstoff ist für Infrarot durchlässig. Schwarzweißfilm ist ein Silberbild und blockiert Infrarot, die Korrektur würde das Foto selbst als einen großen Defekt lesen und löschen.

| Filmart | Automatisches IR | Grund |
|---|---|---|
| Farbnegativ | Bedingt | Farbstoffbild. Das Plug-in muss IR melden und die Ausrichtungsprüfung muss bestehen |
| Farbpositiv | Bedingt | Farbstoffbild. Gleiche Bedingungen wie beim Farbnegativ |
| Schwarzweißnegativ und -positiv | Aus | Das Silberbild blockiert Infrarot |

`FilmType` kann Schwarzweiß auf Farbstoffbasis nicht von Silber unterscheiden und Kodachrome nicht von einem normalen Dia. Zwei Fälle bleiben beim Nutzer:

- Schwarzweiß auf Farbstoffbasis wird als Schwarzweiß gescannt, IR bleibt also aus, obwohl der Film es zuließe. Aus der Filmart allein wird nichts geraten.
- Kodachrome ist ein Farbdia, daher wird IR angeboten. Seine Farbstoffe dämpfen Infrarot anders als E-6, ein Defekt kann unter- oder überkorrigiert bleiben. Schalten Sie die Ebene aus, wenn das Ergebnis falsch aussieht.

## Ausrichtungsprüfung

`InfraredDefectRemoval` vergleicht die Streutextur im IR mit dem Rotkanal des RGB-Bildes und sucht einen ganzzahligen Versatz. Das Ergebnis trägt `AlignmentDiagnostics`.

| Zustand | Bedeutung |
|---|---|
| `notRequested` | Der Aufrufer gibt an, dass beide Ebenen schon übereinstimmen |
| `aligned` | Die Korrelation erreicht den Schwellwert, der beste Punkt liegt im Suchbereich |
| `insufficientTexture` | Das IR bietet zu wenige Ausrichtungsmerkmale |
| `weakCorrelation` | Die Korrelation erreicht den Schwellwert nicht |
| `searchLimitReached` | Der beste Punkt liegt auf der Suchgrenze |

Die letzten drei enden mit dem Fehler `alignmentUnreliable` und werden nie durch `(0,0)` ersetzt. Ein bester Punkt auf der Suchgrenze gilt als Fehlschlag, gleich wie groß der Versatz ist.

Automatische Tests ersetzen nicht die Prüfung der RGB/IR-Ausrichtung an einem echten Gerät und je Film. Diese Prüfungen erfolgen von Hand an echtem Film.

Steuerung und Aufnahmecode für SANE-Geräte liegen nur im getrennten Repository `negaflow-scanner-sane`.
