# Mediatheksarchiv

[Dokumentationsstart](../README.md)

Ein Katalog-Backup bringt die App wieder zum Laufen und enthält die Originalfotos nicht. Das Archiv `.negaflowarchive` fasst sie in einem Paket zusammen.

| Enthalten | Nicht enthalten |
|---|---|
| Portables Katalog-JSON | Die laufende SQLite-Datei |
| Referenzierte Originale und verbliebene IR-Originale | Miniaturen und Vorschauen |
| Der noch benötigte GrainMend-Verlauf | Wiederherstellbare GrainMend-Caches |
| Die Verbindung zwischen virtuellen Kopien und gemeinsamen Originalen | Exportierte Dateien |

> [!WARNING]
> Scheitert der Aufbau des Archivs, wird ein vorhandenes Archiv nicht überschrieben. Originale, fremde XMP-Dateien und der laufende Katalog bleiben unberührt.

## Paketaufbau und Prüfungen

Das Paket folgt der Ordnerstruktur von [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html). SHA-256-Listen gibt es getrennt für Inhaltsdateien und Verwaltungsdateien. `negaflow-archive.json` verbindet Bild-IDs mit den gespeicherten Datei-IDs. Virtuelle Kopien desselben Originals teilen sich eine gespeicherte Kopie.

Der temporäre Ordner wird erst an den endgültigen Pfad verschoben, wenn alle diese Prüfungen bestehen:

1. Die aktuelle App kann den Katalog sicher lesen.
2. Originale und IR-Eingaben sind reguläre Dateien, deren Größe und Änderungszeit sich beim Kopieren nicht ändern.
3. Jeder benötigte GrainMend-Eintrag ist lesbar.
4. SHA-256, Bytezahlen, Dateiliste und `Payload-Oxum` stimmen überein.
5. Die Verknüpfungen von Bildern zu Originalen, IR-Dateien und GrainMend-Einträgen passen zum Katalog.

Bei einem Fehler wird nur der halb fertige temporäre Ordner gelöscht. Das vorhandene Archiv bleibt bestehen.

## Grenzen

Originalformate bleiben unverändert, es gibt keine Umwandlung für Langzeitkompatibilität. PREMIS-Erhaltungsereignisse, Agenteneinträge und die Migration in empfohlene Formate liegen außerhalb von v1.

Ein Archiv ist kein Erhaltungskonzept. Bewahren Sie Kopien auf anderen Medien an einem anderen Ort auf und prüfen Sie die Hashes regelmäßig.

Quellen:

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
