# Katalogspeicherung

[Dokumentationsstart](../README.md)

Der Hauptspeicher ist `library.sqlite`. Das ältere `library.json` dient nur zum Import eines älteren Katalogs oder zum Schreiben einer Diagnosedatei. Nichts aktualisiert beide gleichzeitig, es gibt also kein Dual-Write. Backups und Erhaltungsarchive nutzen portables JSON und schließen die laufende SQLite-Datei aus.

| Art | Format | Verwendung |
|---|---|---|
| Hauptkatalog | SQLite | Betrieb der App, Suche, Speichern, Wiederherstellung |
| Ältere Daten | JSON | Import eines vorhandenen Katalogs |
| Backup und Erhaltungsarchiv | JSON-Form | Umzug auf einen anderen Rechner, Wiederherstellung |

> [!IMPORTANT]
> Ein fehlender oder beschädigter Katalog startet keine leere Mediathek. Der ursprüngliche Katalog und die Fotodateien bleiben unberührt, bis eine intakte Generation gefunden ist.

## Messungen

JSON und SQLite wurden auf demselben Mac mit diesen Befehlen verglichen.

<details>
<summary>Messbefehle</summary>

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_CATALOG_PERF_REPORT="$PWD/build/performance/catalog.json" \
  bash scripts/performance/run-catalog.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_LIBRARY_QUERY_PERF_REPORT="$PWD/build/performance/library-query.json" \
  bash scripts/run-library-query-performance.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  NEGAFLOW_SQLITE_CATALOG_PERF_REPORT="$PWD/build/performance/catalog-sqlite.json" \
  bash scripts/performance/run-sqlite-catalog.sh
```

</details>

Gemessen am 2026-07-12: Mac14,3, arm64, 8 Kerne, 24 GiB, macOS 26.5, Swift-Release-Build. Die Zahlen sind eine Regressionsbasis für diesen Aufbau, keine Vorhersage für einen anderen Mac.

| Bilder | JSON-Größe | Encode p50 | Decode p50 | File read p50 |
|---:|---:|---:|---:|---:|
| 1,000 | 2,192,671 bytes | 98 ms | 241 ms | 231 ms |
| 10,000 | 21,934,841 bytes | 811 ms | 2,301 ms | 2,299 ms |
| 50,000 | 109,721,335 bytes | 2,746 ms | 7,353 ms | 7,397 ms |

Das Kodieren von 50.000 Bildern nach JSON erhöhte den residenten Speicher um etwa 191 MiB und den maximalen RSS um etwa 107 MiB. Mit denselben Daten dauerte das Vorbereiten der Speichersuche 32,86 ms, das Sortieren aller Namen 86,01 ms und das Sortieren der Namen nach einem Filter 158,37 ms. Vier Filterprojektionen hintereinander hatten einen p50 von 512,80 ms.

Der SQLite-Zeilenspeicher bei 50.000 Bildern, Release p95:

| Vorgang | p95 |
|---|---:|
| Neuer Commit | 3,714 ms |
| Hauptdatei lesen | 7,446 ms |
| Commit ohne Änderungen | 3,856 ms |
| Größe pro Bild | ≈ 4,211 bytes |

Ein Backup zieht nicht die ganze Datenbank in `Data`. Es erstellt eine temporäre, replikationsfähige Kopie und tauscht sie atomar aus. Die Prüfung vor dem Backup kontrolliert SQLite-Integrität und Schema, statt jedes Bild zu dekodieren, und senkte den p95 eines Commits ohne Änderungen von 11.245 ms auf 3.856 ms.

## Warum SQLite

- Viele Zeilenänderungen passen in eine Transaktion.
- Zeilen und Indizes erlauben, nur die benötigten Bilder zu lesen.
- Die SQLite-C-API gehört zu macOS, ein neues Paket ist nicht nötig.
- Die Wiederherstellungsregel bleibt bestehen: Ein beschädigter Speicher gilt nie als leere Mediathek.

Es läuft mit `journal_mode=DELETE` und `synchronous=FULL`. Mit WAL müssten Datenbank und `-wal`-Datei als eine Einheit behandelt werden. Die laufende Datenbank wird nicht direkt kopiert. Nur die nach dem Schließen der Verbindung geprüfte Hauptdatei wird zur Wiederherstellungskopie.

## Wer im Code was tut

- `CatalogStore`: Verbindung, Transaktionen, Schemaversion, Integritätsprüfungen
- `CatalogMigration`: lesender JSON-Import und Umwandlung je Version
- Entitätstabellen: Bilder, Originale, Reihenfolge, Filme, Ordner, Sammlungen, Suche, Scanaufträge
- `LibraryBackupStore`: portables JSON-Backup, Vorprüfungen der Wiederherstellung, Wiederherstellungsinformationen

Entwicklungswerte und versionierter Bearbeitungsverlauf liegen als JSON-BLOB je Entität vor. Quellpixel, Miniaturen und GrainMend-Caches bleiben außerhalb der Datenbank. Für Suche und Sortierung fehlen noch Spalten und Indizes, deshalb wird der ganze Katalog beim Start in den Speicher geladen, und die SQLite-Lesezeit sieht derzeit aus wie die von JSON. Der nächste Schritt sind Indexabfragen, die nur die verwendeten Spalten und Bilder lesen.

## Älteres JSON übernehmen

1. JSON-Version und `LibraryCatalogHealth` prüfen.
2. Eine temporäre SQLite-Datenbank anlegen.
3. Das Material in einer Transaktion übertragen.
4. IDs, Reihenfolge, Zugehörigkeit und Aufträge vergleichen.
5. `integrity_check` und die Sicherheitsbedingungen prüfen.
6. Das JSON als Wiederherstellungsgeneration behalten.
7. Auf SQLite als Hauptspeicher umschalten.

Scheitert ein Schritt, bleibt das vorhandene JSON unverändert, und ein leerer Katalog wird nie gestartet. Auch wenn Zwischendateien und Marker zurückbleiben, wird nur weitergearbeitet, wenn die Quell-SHA-256 und beide Kataloge übereinstimmen. Nach der Migration gibt es keinen automatischen Rückfall auf JSON. Mindest-Lesversion und Migrationsmarker werden geprüft, damit eine ältere App das JSON nicht bearbeitet und den Speicher in zwei Hälften spaltet.

## Quellen

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
