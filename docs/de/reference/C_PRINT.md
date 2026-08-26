# Abzugslayouts und C-Print-Vorschau

[Dokumentationsstart](../README.md)

Der Druckbereich verbindet Seitenlayout, Seitenexport und Vorschau des Ausgabeverfahrens.
Unterstützt werden Einzelbild, Kontaktbogen, Bildpaket, Benutzerpaket, Cyanotypie, Glasplatte und
Gelatinesilber.

## Kontaktbögen

Ein neuer Kontaktbogen startet mit schwarzem Hintergrund, 6 Spalten × 7 Zeilen und horizontalen
sowie vertikalen Abständen von 2 mm. Alle anderen Layouts starten mit Weiß. Jedes Layout kann
unabhängig Schwarz, Grau oder Weiß wählen. Beschriftungen, freie Texte, Schnittmarken und
Seitenkonturen wechseln automatisch zu einer kontrastierenden Farbe.

Rand, Zeilen, Spalten und beide Abstände verwenden dieselbe physische Berechnung. Zu große
Kombinationen werden auf den größten gültigen Abstand begrenzt, statt die Vorschau zu beschädigen.
Die automatische Ausrichtung richtet sich nach dem Raster und nicht nach dem ersten Foto.
**Einpassen** zeigt das ganze Bild und kann freien Raum in der Zelle lassen; **Zelle füllen**
beschneidet auf eine einheitliche Zelle und erzeugt gleichmäßige sichtbare Zwischenräume.

Beschriftungen unterstützen Dateiname, ursprüngliche Bildnummer, eine bei 1 beginnende
Reihenfolgennummer, Bewertung und benutzerdefinierten Text. Bildbeschriftungen lassen sich links,
mittig oder rechts ausrichten. Mehrere freie Textfelder können mit eigenem Text, eigener
Ausrichtung, Position, Breite und Höhe beliebig auf dem Bogen platziert werden.

## Papier und Lineale

Alle Layouts verwenden dieselben Papierregler. Verfügbar sind Fotoformate in Zoll von 3.5 × 5 bis
24 × 36, Letter, Tabloid, A3+, ISO A1–A6 und ISO B1–B6. Oberfläche steht direkt unter Bogenfarbe
und bietet Matt, Glänzend, Lustre und Seide; Matt ist die Voreinstellung.

Lineale sind standardmäßig aus. Nach dem Einschalten erscheint direkt darunter die Wahl in/cm,
außerdem ein horizontales Lineal über und ein vertikales Lineal links vom Papier. Ganze Zoll oder
Zentimeter werden klein beschriftet und durch kürzere Teilstriche unterteilt.

## Einzelne und historische Abzugslayouts

Einzelbild, Cyanotypie, Glasplatte und Gelatinesilber erzeugen für jedes ausgewählte Foto eine
Seite. Bei mehreren Fotos erscheinen die Seiten untereinander und werden durch Scrollen gewechselt,
statt auf einen Bogen gezwungen zu werden. Cyanotypie bildet die Helligkeit monochrom in Blau ab,
Glasplatte zeigt ein Schwarzweißnegativ und Gelatinesilber ein neutrales Schwarzweißpositiv.

Die drei historischen Layouts verwenden Papier, Ausrichtung, Rand, Ausgabe und Inspektor des
Einzelbilds; ihre Darstellung wird auch in Export und Schnellexport gerendert. Es sind bewusst
gestaltete Darstellungen, keine messtechnische Rekonstruktion einer bestimmten historischen
Chemie, Platte, eines Papiers oder einer Betrachtungsbedingung.

## Abzug exportieren

**Abzug exportieren** direkt unter dem Schnellexport rendert Papierformat, Ausrichtung, Rand,
Layout, schwarzen, grauen oder weißen Bogen, Beschriftungen, freie Texte und Schnittmarken. Dateiformat,
DPI, Ordner, Benennung und Auslieferungsfarbraum stammen aus den Exporteinstellungen. Reine
Bildschirmhilfen wie Farbumfangwarnung, Softproof-Simulation und Oberflächenglanz werden nicht in
die Datei eingebrannt.

Während Abzugsexport oder Schnellexport laufen, zeigt der Exportbereich fertige Seiten, einen
linearen Fortschrittsbalken und Prozent statt eines unbestimmten Kreisindikators.

### Seitenzahlen und Rendering

Die Ausgabezahl meint fertige Seiten. Ein 6 × 7-Kontaktbogen mit 39 Fotos ergibt eine
zusammengesetzte Seite, ein Bildpaket mit vier Fotos pro Seite 10 Seiten, das voreingestellte
Benutzerpaket eine Seite und jedes Einzelbildlayout 39 Dateien über denselben begrenzten
Batch-Scheduler wie der Schnellexport.

Die Paketvorschau erzeugt nicht für jedes Foto eine interaktive und eine stabilisierte
Vollauflösungsvorschau. Sie verwendet vorhandene Bilder und erstellt nur für fehlende Elemente eine
schnelle Vorschau in Thumbnailgröße. Der endgültige Export berechnet das Layout aus
Quellmetadaten, entwickelt nur die für jede Platzierung benötigten Pixel und bereitet gleichzeitig
zwei bis vier eindeutige Quellen vor. Ein gemeinsamer Core-Image-Kontext, der bis zur Seitenausgabe
verbundene Graph und ein Rasterbudget von 512 MiB pro Seite begrenzen den Speicher, ohne Layout oder
Ausgabevertrag zu ändern.

### Drucker-Ausgabeprofil

Das im Print-Arbeitsbereich gewählte Drucker-Ausgabeprofil wird auf den tatsächlichen Export
angewendet. negaflow setzt zuerst die ganze Seite zusammen und wendet das Profil anschließend
einmal auf die fertige Seite an. Damit werden alle Platzierungen eines Bildpakets verarbeitet,
unabhängig davon, ob dasselbe Foto wiederholt oder mehrere Fotos gemischt werden.

Das Profil beeinflusst weder die Bibliothek noch die Vorschau in Entwicklung. Es gilt nur für die
Print-Vorschau und den Print-Export.

## C-Print verwenden

Das Ausgabeverfahren kann Standard oder C-Print sein. C-Print speichert Labor und Papier und
verwendet das vom Labor bereitgestellte RGB-ICC-Profil für einen Bildschirm-Softproof. Die
gemeinsame Oberflächeneinstellung bleibt für alle Verfahren und Layouts im Layout-Tab. Ohne
gemessenes Profil wendet negaflow keinen pauschalen „C-Print-Look“ an.

1. Wählen Sie im Druckbereich unter Ausgabeverfahren **C-Print**.
2. Tragen Sie Labor und Papier ein. Wählen Sie die Oberfläche bei Bedarf im Layout-Tab.
3. Wählen Sie das RGB-ICC-Profil für genau dieses Labor, Papier und Gerät.
4. Aktivieren Sie die Abzugsvorschau. Papier- und Schwarzpunktsimulation sowie Farbumfangwarnung
   befinden sich unter Erweitert.

Ohne gültiges RGB-ICC-Profil werden die Zielangaben weiterhin gespeichert, die Abzugsvorschau bleibt
jedoch nicht verfügbar. CMYK- und Device-Link-Profile werden in diesem RGB-Vorschaupfad nicht
akzeptiert.

## Farbvertrag

Das C-Print-Proof-ICC dient nur dem Softproof. Es verändert weder Pixel noch eingebettetes Profil
der exportierten Datei. Wenn kein separates Drucker-Ausgabeprofil gewählt ist, verwendet der
Abzugsexport den in den Exporteinstellungen angezeigten Auslieferungsfarbraum. Ein vom Labor nur
zum Softproof verteiltes Profil wird dadurch nicht unbemerkt zum Lieferprofil.

Das ältere Entwicklungs-target `PRINT` bleibt getrennt. Dieser Pfad verlangt weiterhin ein gültiges
RGB-ICC-Profil der Druckerklasse und konvertiert die Ausgabe durch dieses Profil.

## Genauigkeitsgrenzen

Die Vorschau verwendet die ICC-Transformation und kann Papierweiß, Schwarzpunkt und Farben außerhalb
des Farbumfangs anzeigen. Ihre Genauigkeit hängt von einem kalibrierten Display und einem aktuellen
Profil für den exakten Laborprozess ab. Betrachtungslicht, Chemiedrift, Gerätekalibrierung und
Papierchargen kann sie nicht vorhersagen. negaflow liefert keine Laborprofile mit und erfindet keine.
