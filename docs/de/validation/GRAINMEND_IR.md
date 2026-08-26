# GrainMend-IR-Messung an echten Scans

[Dokumentationsstart](../README.md)

Wie viel GrainMend IR von einem Defekt tatsächlich entfernt, gemessen an echten Scans statt
an synthetischen Vorlagen.

| Punkt | Wert |
|---|---|
| Material | Epson GT-X900, Farbnegativ, 2400 dpi, 16 Bit |
| Paare | 5 (Hauptscan und Infrarotdurchgang) |
| Bewertete Defekte | 140 bis 338 je Bild |
| Gemessen am | 2026-08-11 |

## Wie bewertet wird

Der Detektor benotet sich nicht selbst. Ein Defekt zählt nur, wenn die Aufnahme ihn
bestätigt: Der Infrarotkandidat wird mit dem dunklen Fleck im Rotkanal über den eigenen
lokalen Versatz zur Deckung gebracht und nur behalten, wenn dieser Gipfel vier Sigma über
dem umgebenden Rauschen liegt. Die Entfernung ist der logarithmische Dichteüberschuss in der
Defektmitte gegen eine Ringbasislinie, vor und nach der Korrektur. Überkorrektur ist
dieselbe Zahl im Negativen: Die Mitte kam heller heraus als ihre Umgebung.

## Die Aufnahme kommt zuerst

Der Infrarotdurchgang muss dieselbe Gammatabelle und denselben Fokus tragen wie der
Hauptscan. Bleibt es bei den Gerätevorgaben, beschneidet die Filmbasis am weißen Ende,
9,07 Prozent des Bildes stehen fest auf 65535, und die Basislinie, an der die Defekttiefe
gemessen wird, ist weg. Sind beide Durchgänge gleich eingestellt, gibt es kein Clipping.
Messungen von vor dieser Korrektur sagen nichts über den Detektor aus.

## Ergebnis

| Bild | Kandidaten zu bestätigt | Verstärkung | Entfernung in der Mitte | Überkorrektur leicht/mittel/schwer |
|---|---|---|---|---|
| 19 | 483 zu 262 | 1,12 | 90% | 5 / 0 / 0 |
| 20 | 726 zu 407 | 1,84 | 85% | 16 / 8 / 3 |
| 21 | 1138 zu 494 | 1,52 | 96% | 24 / 5 / 0 |
| 22 | 969 zu 674 | 1,26 | 93% | 25 / 3 / 3 |
| 23 | 540 zu 341 | 1,32 | 95% | 13 / 2 / 0 |

Die Verstärkung ist das gemessene Verhältnis von sichtbarer zu infraroter Dichte. Die
Abdeckung ist über die Wellenlänge nahezu flach, ein Wert nahe eins sagt also, dass beide
Durchgänge sich darüber einig sind, was verdeckt war. Leicht heißt, die Mitte kam 1 bis 3
Prozent heller heraus als ihre Umgebung, unterhalb des Filmkorns; schwer heißt mehr als 6
Prozent. Die Erkennung braucht 0,6 bis 0,9 Sekunden je Bild, das Anwenden der Korrektur
weitere 0,1 bis 0,3.

96 bis 99 Prozent der Korrektur liegen innerhalb von acht Pixeln um einen echten
Infrarotdefekt, und die mittlere Korrektur je Rot-Dezil zeigt keinen Trend: Die breitere
Erkennung läuft also nicht in die Szene über.

## Nach Defektgröße

Breiter Staub überlebte, während Kratzer sauber verschwanden. Vier Schritte lasen nur
Defekte falsch, die größer als wenige Pixel sind, und ein fünfter hielt jeden Defekt um
einen festen Betrag zurück.

| Radius der schmalen Seite | Vorher | Nachher |
|---|---|---|
| 1 bis 2 px | 52 bis 74% | 77 bis 95% |
| 3 bis 4 px | 77 bis 89% | 93 bis 99% |
| 5 bis 7 px | 0 bis 91% | 24 bis 99% |
| 12 bis 17 px | 0 bis 73% | 58 bis 89% |
| 18 px und mehr | 0% | 73 bis 93% |

- Das Strukturelement der Basislinie wuchs mit dem, was der erste Durchgang beobachtete,
  doch diese Beobachtung entsteht mit derselben Basislinie: Ein Defekt, der breiter ist als
  das Element, misst sein eigenes Inneres und wirkt klein. Es wird jetzt aus der Auflösung
  bestimmt.
- Die Kandidatenschwelle ist die Signifikanz eines einzelnen Pixels, blasser breiter Staub
  überschritt also kein einziges. Dieselbe Signifikanz gilt nun für die bedeckte Fläche.
- Die Nullverteilung kam aus der ganzen Suchebene, ein Defekt so groß wie diese Ebene wurde
  damit zu seiner eigenen Null und halbierte die gemessene Verstärkung.
- Die wiederherzustellende Menge wurde an der Drei-Sigma-Zugehörigkeitslinie gemessen statt
  am eigenen Boden des Films, was diesen Betrag bei jedem Defekt stehen ließ.
- Die Aufwärtsverzerrung eines Gipfels, der wegen seiner Größe ausgewählt wurde, war ein
  festes Sigma. Sie ist das inverse Mills-Verhältnis der Vier-Sigma-Schwelle: volle Vorsicht
  an der Schwelle, nichts mehr jenseits von acht.

## Nicht geprüft

- Kein Blick von Auge auf die korrigierten Bilder. Leichte Überkorrektur ist hier eine Zahl,
  kein Urteil darüber, wie es aussieht.
- Kein vollständiger Stapel von achtzehn Bildern durch die Anwendung.
- Bild 20 bleibt mit 85 Prozent unter den anderen. Seine Infrarotdichte liegt bei etwa 60
  Prozent der übrigen Bilder, die Vorlage selbst ist also vermutlich dünn.
- Nur ein Scanner. V800, V850 und Coolscan wurden nicht gemessen.
- Farbscans mit 16 Bit kommen bei 300 dpi und darunter schwarz heraus. 2400 dpi ist normal
  und eine Produktwirkung ist nicht bestätigt, die Ursache bleibt unbekannt.
