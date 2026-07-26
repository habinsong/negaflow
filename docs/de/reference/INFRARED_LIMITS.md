# Filme, die GrainMend IR meidet

[Dokumentationsstart](../README.md)

Die Infrarotreinigung liest sichtbares und infrarotes Bild getrennt und legt sie übereinander, um
Defekte zu finden.
Das passt nicht zu jedem Film.

- Normaler Farbfilm und chromogener Schwarzweißfilm können IR nutzen.
- Gewöhnlicher Schwarzweißfilm behält sein Silber, blockt damit IR und liefert eine falsche Defektkarte.
- Kodachrome dämpft IR anders als andere Farbfilme, deshalb wird zu wenig oder zu stark korrigiert.

Belege:

- [Technische Hinweise und Grenzen von Epson](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson-Tabelle der Filmtypen](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast zu Schwarzweiß und Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> Lässt sich das Filmmaterial nicht bestimmen, wird IR nicht automatisch angewendet. Eine
> falsche IR-Maske löscht echte Bildstruktur als Defekt.

## Wo es automatisch greift

`FilmType` unterscheidet nur Farbe und Schwarzweiß, Negativ und Positiv.
Nichts darin trennt chromogenes Schwarzweiß von silberbasiertem oder ein normales Dia von
Kodachrome.

| Filmtyp | Automatisches IR | Grund |
|---|---|---|
| Farbnegativ | Bedingt | Das Plugin muss IR melden und die Ausrichtungsprüfung bestehen |
| Farbpositiv | Aus | Ob es Kodachrome ist, lässt sich nicht feststellen |
| Schwarzweiß-Negativ und -Positiv | Aus | Chromogen und silberbasiert sind nicht auseinanderzuhalten |

Das heißt nicht, dass IR bei chromogenem Schwarzweiß oder einem normalen Farbdia nie ginge.
Die vorhandenen Daten bestätigen das Filmmaterial nicht, also wird nichts geraten.

## Ausrichtungsprüfung

`InfraredDefectRemoval` vergleicht die Durchschlagstextur im IR mit dem Rotkanal des RGB und sucht
einen ganzzahligen Versatz.
Das Ergebnis trägt `AlignmentDiagnostics`.

| Zustand | Bedeutung |
|---|---|
| `notRequested` | Der Aufrufer hat angegeben, dass beide Ebenen bereits passen |
| `aligned` | Die Korrelation liegt über der Schwelle, das Optimum im Suchbereich |
| `insufficientTexture` | Im IR fehlen Anhaltspunkte für die Ausrichtung |
| `weakCorrelation` | Die Korrelation bleibt unter der Schwelle |
| `searchLimitReached` | Das Optimum liegt auf der Suchgrenze |

Die letzten drei werden nicht durch `(0,0)` ersetzt.
Sie brechen mit dem Fehler `alignmentUnreliable` ab.
Liegt das Optimum auf der Suchgrenze, gilt das unabhängig vom Betrag des Versatzes als Fehlschlag.

Automatische Tests ersetzen weder die RGB/IR-Ausrichtung am echten Gerät noch Ergebnisse je Film.
Prüfungen am echten Scanner folgen den IR-Punkten der
[Checkliste für echte Geräte](../validation/REAL_QA_CHECKLIST.md).

SANE-Gerätesteuerung und Aufnahmecode liegen nur im separaten Repository `negaflow-scanner-sane`.
