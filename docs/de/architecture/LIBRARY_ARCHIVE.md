# Mediatheksarchiv

[Dokumentationsstart](../README.md)

Ein Katalog-Backup bringt die App wieder zum Laufen und enthält die Originalfotos nicht. Beide Plattformen schreiben `.negaflowarchive`, nutzen auf macOS und Windows aber unterschiedliche Paketformate und Inhalte.

> [!WARNING]
> Scheitert der Aufbau eines Archivs, bleiben Originale, fremde XMP-Dateien, der laufende Katalog und jedes vorhandene Archiv unberührt.

## macOS-Archiv (BagIt-Ordner)

Auf macOS ist `.negaflowarchive` ein Ordner nach [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html), der den Katalogzustand mit den referenzierten Fotos bündelt.

| Enthalten | Nicht enthalten |
|---|---|
| Portables Katalog-JSON | Die laufende SQLite-Datei |
| Referenzierte Originale und verbliebene IR-Originale | Miniaturen und Vorschauen |
| GrainMend-Fehlerrezepte | Wiederherstellbare GrainMend-Caches |
| Verknüpfungen virtueller Kopien zu gemeinsamen Originalen | Exportierte Dateien |

Inhaltsdateien und Tag-Dateien erhalten getrennte SHA-256-Manifeste (`manifest-sha256.txt` und `tagmanifest-sha256.txt`). `negaflow-archive.json` verbindet Bild-IDs mit den gespeicherten Datei-IDs. Virtuelle Kopien desselben Originals teilen sich eine gespeicherte Kopie.

Das Schreiben lehnt es ab, ein vorhandenes Ziel zu überschreiben. Der temporäre Ordner wird erst an den endgültigen Pfad verschoben, wenn alle diese Prüfungen bestehen:

1. Die aktuelle App kann den Katalog sicher lesen.
2. Originale und IR-Eingaben sind reguläre Dateien, deren Größe und Änderungszeit sich beim Kopieren nicht ändern.
3. Jedes benötigte GrainMend-Fehlerrezept ist lesbar.
4. SHA-256-Hashes (`manifest-sha256.txt`, `tagmanifest-sha256.txt`), Bytezahlen, Dateiliste und `Payload-Oxum` stimmen überein.
5. Die Verknüpfungen von Bildern zu Originalen, IR-Dateien und GrainMend-Rezepten passen zum Katalog.

Bei einem Fehler wird nur der halb fertige temporäre Ordner gelöscht.

## Windows-Archiv (ZIP-Datei)

Auf Windows ist `.negaflowarchive` ein ZIP-Archiv mit Katalog- und Fehlerdaten. Originalfotodateien werden nicht kopiert.

| Enthalten | Nicht enthalten |
|---|---|
| `library.sqlite` | Originalfotodateien und IR-Originale |
| Fehlerrezepte unter `defects/*` | Miniaturen, Vorschauen und wiederherstellbare Caches |
| `archive.json` (Bytezahlen und SHA-256-Hashes je Eintrag) | Exportierte Dateien |

Windows schreibt das Archiv in eine temporäre Datei und ersetzt das Ziel bei Erfolg atomar. Scheitert der Aufbau, wird die temporäre Datei entfernt und ein vorhandenes Archiv am Ziel bleibt unberührt.

## Grenzen

macOS- und Windows-`.negaflowarchive`-Pakete nutzen verschiedene Formate und Katalogschemata; ein Archiv zieht deshalb zwischen Rechnern derselben Plattform um. Originalformate bleiben unverändert, es gibt keine Umwandlung für Langzeitkompatibilität. PREMIS-Erhaltungsereignisse, Agenteneinträge und die Migration in empfohlene Formate liegen außerhalb von v1.

Ein Archiv ist kein Erhaltungskonzept. Bewahren Sie Kopien auf anderen Medien an einem anderen Ort auf und prüfen Sie die Hashes regelmäßig.

Quellen:

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
