# Abzugslayouts und C-Print-Vorschau

[Dokumentationsstart](../README.md)

Der Abzug hat acht Layouts: Einzelbild, Kontaktbogen, Bildpaket, eigenes Paket, Cyanotypie, Glasplatte, Silbergelatine und Wasserzeichen.

## Kontaktbögen

- Ein neuer Kontaktbogen beginnt mit einem schwarzen Bogen, 6 Spalten × 7 Zeilen und 2 mm Abstand. Alle anderen Layouts beginnen mit einem weißen Bogen. Jedes Layout kann seinen Bogen zwischen Schwarz, Grau und Weiß wechseln, und Beschriftungen, eigener Text, Schnittmarken und Seitenränder nehmen von selbst eine Kontrastfarbe an.
- Ränder, Zeilen- und Spaltenzahl und Abstände folgen einem einzigen physischen Layoutvertrag. Eine unmögliche Kombination wird auf den größten gültigen Abstand verkleinert, statt die Vorschau zu zerstören. Die automatische Ausrichtung folgt dem Raster. **Einpassen** lässt das ganze Foto sichtbar und kann Platz in der Zelle lassen. **Zelle füllen** beschneidet jedes Foto auf die gemeinsame Zelle und gleicht die Zwischenräume an.
- Beschriftungen können Dateiname, ursprüngliche Bildnummer, Laufnummer (ab 1 in der aktuellen Bildreihenfolge), Bewertung oder eigener Text sein. Jede installierte Mac-Schrift ist wählbar, Vorschau und Export verwenden dieselbe. Beschriftungen pro Bild lassen sich links, mittig oder rechts ausrichten. Der eigene Text unterstützt mehrere unabhängige Felder mit je eigenem Text, eigener Ausrichtung, Position, Breite und Höhe.

## Papiereinstellungen und Lineale

Alle Layouts nutzen dieselben Papiereinstellungen. Der Katalog enthält gängige fotografische Zollformate von 3,5 × 5 bis 24 × 36, Letter, Tabloid, A3+, ISO A1–A6 und ISO B1–B6. Die Oberfläche steht unter der Bogenfarbe und bietet Matt (Standard), Glänzend, Lustre und Seide.

Die Lineale sind standardmäßig aus. Eingeschaltet erscheint unter dem Schalter eine Auswahl Zoll/cm, über der Seite ein waagerechtes und links davon ein senkrechtes Lineal. Ganze Zoll oder Zentimeter sind beziffert, dazwischen liegen feinere Teilstriche.

## Einzel- und historische Layouts

Einzelbild, Cyanotypie, Glasplatte und Silbergelatine erzeugen je ausgewähltem Foto eine Seite. Mehrere ausgewählte Fotos erscheinen als senkrechter Stapel. Cyanotypie bildet die Luminanz auf ein blaues Einfarbbild ab, Glasplatte zeigt ein einfarbiges Negativ, Silbergelatine ein neutrales einfarbiges Positiv.

Diese drei Stile nutzen dieselben Einstellungen für Papier, Ausrichtung, Ränder, Ausgabe und Inspektor wie das Einzelbild und werden in Export und Schnellexport mit ausgegeben. Es sind bewusst gestaltete Bildstile, keine gemessene Nachbildung einer bestimmten historischen Chemie, Platte, eines Papiers oder einer Betrachtungsbedingung.

## Wasserzeichen und Layoutvorlagen

Das Wasserzeichen ist ein eigener Layouttyp im Menü. Seine Wahl setzt das Papierformat auf Fotoverhältnis (danach ist ein anderes Format wählbar) und fügt Rahmen außerhalb des Fotos hinzu. Das Menü für die Namensposition ist immer verfügbar: unten mittig, oben links, oben mittig oder oben rechts, und eine obere Position schaltet den oberen Rahmen ein. Belichtungszeiten bekommen kein zusätzliches Anführungszeichen, leere Textfelder bleiben leer. Der Namenstext ist in seiner Position zentriert. Teilen sich Name und Histogramm eine Position, liegt das Histogramm über dem Namen und beide sind zentriert.

Eine Layoutvorlage stellt Layout, Papiereinstellungen, Bogenfarbe und Wasserzeichen-Einstellungen wieder her und aktualisiert dann die Vorschau. DPI- und Linealeinstellungen bleiben, wie sie waren. Vorlagen, die vor diesen Feldern gespeichert wurden, behalten die aktuelle Bogenfarbe und das aktuelle Wasserzeichen. Die Anordnung der Felder und die Regeln für DNG-Quelle und Farbraum stehen in [Von der Mediathek zum Abzug](../product/WORKFLOW.md).

## Abzugsexport

**Abzugsexport**, direkt unter Schnellexport, rendert die aktuelle Seitengröße, Ausrichtung, Ränder, das Layout, die Bogenfarbe, Beschriftungen, den eigenen Text und die Schnittmarken mit Format, DPI, Ordner, Benennung und Auslieferungsfarbraum aus Export. Hilfen, die nur auf dem Bildschirm gelten, werden nicht in die Datei eingebrannt: Gamut-Warnungen, Softproof-Simulation und Papieroberflächenglanz. Während einer der beiden Abzugsexport-Wege läuft, zeigt das Exportfeld die Zahl fertiger Seiten, einen linearen Fortschrittsbalken und eine Prozentangabe statt eines endlosen Drehkreises.

### Seitenzahl und Rendering

Gezählt werden fertige Seiten. Ein Kontaktbogen 6 × 7 mit 39 Fotos exportiert eine zusammengesetzte Seite, ein vierfaches Bildpaket 10 Seiten, das Standard-Paket eine Seite, und jedes Einzelbild-Layout 39 Dateien über denselben begrenzten Stapelplaner wie der Schnellexport.

Die Paketvorschau erzeugt nicht für jedes Foto eine interaktive und eine beruhigte Vorschau in voller Auflösung. Sie nutzt vorhandene Bilder und erzeugt nur für ein fehlendes Element eine schnelle Vorschau in Miniaturgröße. Der endgültige Export leitet das Layout aus den Quellmetadaten ab, entwickelt nur die Pixel, die jede Platzierung braucht, bereitet zwei bis vier verschiedene Quellen gleichzeitig vor und hält den Core-Image-Graphen bis zum Schreiben der Seite verbunden. Der gemeinsame Render-Kontext und ein Budget von 512 MiB Quellraster pro Seite begrenzen den Speicher, ohne das sichtbare Layout oder den Ausgabevertrag zu ändern.

### Druckerausgabeprofil

Das im Abzug-Arbeitsbereich gewählte Druckerausgabeprofil gehört zum exportierten Ergebnis. negaflow setzt zuerst die ganze Seite zusammen und wendet das Profil einmal auf die fertige Seite an. Das umfasst jede Platzierung in einem Bildpaket oder eigenen Paket, ob ein Foto wiederholt oder mehrere gemischt werden. Das Profil wirkt nicht auf die Vorschau von Mediathek oder Entwickeln, nur auf Abzugsvorschau und Abzugsexport.

## C-Print verwenden

Der Ausgabeprozess ist Standard oder C-Print. C-Print hält das Ziellabor und das Papier fest und nutzt ein vom Labor gelieferte RGB-ICC-Profil für einen Softproof am Bildschirm. Die Oberflächenwahl bleibt für jeden Prozess und jedes Layout unter Layout. Ohne gemessenes Profil wendet negaflow keinen allgemeinen „C-Print-Look“ an.

1. Öffnen Sie den Abzug-Arbeitsbereich und wählen Sie unter Ausgabeprozess **C-Print**.
2. Geben Sie Labor und Papier ein. Wählen Sie bei Bedarf unter Layout die Oberfläche.
3. Wählen Sie das für dieses Labor, Papier und diese Maschine gelieferte RGB-ICC-Profil.
4. Schalten Sie die Abzugsvorschau ein. Papier- und Schwarztinten-Simulation und Gamut-Warnung stehen unter Erweitert.

Ohne gültiges RGB-ICC-Profil werden die Zieleinstellungen trotzdem gespeichert, die Abzugsvorschau bleibt aber nicht verfügbar. CMYK- und Device-Link-Profile nimmt dieser RGB-Vorschauweg nicht an.

## Farbvertrag

Das C-Print-Proof-ICC dient nur der Probe. Es ändert die Bildschirmvorschau, nicht die Pixel oder das eingebettete Profil einer exportierten Datei. Der Abzugsexport nutzt den in den Exporteinstellungen gewählten Auslieferungsfarbraum, sofern nicht ein Druckerausgabeprofil gewählt ist, ein Softproof-Profil des Labors wird also nie stillschweigend als Auslieferungsprofil benutzt. Das Entwicklungsziel `PRINT` ist davon getrennt: Es verlangt ein gültiges RGB-ICC-Profil der Druckerklasse und wandelt die Ausgabe damit um.

## Genauigkeitsgrenzen

Die Vorschau enthält die ICC-Umrechnung und kann auf Wunsch Papierweiß, Schwarzpunkt und Farben außerhalb des Gamuts simulieren. Ihre Genauigkeit hängt von einem kalibrierten Display und einem aktuellen Profil für den genauen Laborprozess ab. Sie kann Betrachtungslicht, Chemiedrift, Maschinenkalibrierung und Papierchargenschwankungen nicht vorhersagen. negaflow liefert kein Laborprofil mit und erfindet keines.
