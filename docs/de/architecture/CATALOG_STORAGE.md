# Katalogspeicherung

[Dokumentationsstart](../README.md)

Der Hauptspeicher ist `library.sqlite`. Das ältere `library.json` dient nur zum Import eines älteren Katalogs; die Diagnose schreibt bereinigte Support-Pakete statt `library.json`. Nichts aktualisiert beide gleichzeitig, es gibt also kein Dual-Write. Auf macOS nutzen Backups und BagIt-Archive portables JSON (`version 7`) und schließen die laufende SQLite-Datei aus. Windows nutzt eine eigene Schemaversion (`version 2`) und packt `library.sqlite` in ein ZIP-`.negaflowarchive`, sodass Backups zwischen Rechnern derselben Plattform umziehen.

| Art | Format | Verwendung |
|---|---|---|
| Hauptkatalog | SQLite | Betrieb der App und Suche, Speichern und Wiederherstellung |
| Ältere Daten | JSON | Import eines vorhandenen Katalogs |
| Backup und Erhaltungsarchiv | Portables JSON (`version 7`, macOS) / ZIP mit `library.sqlite` (`version 2`, Windows) | Umzug zwischen Rechnern derselben Plattform, Wiederherstellung |

> [!IMPORTANT]
> Ein fehlender oder beschädigter Katalog startet keine leere Mediathek. Der ursprüngliche Katalog und die Fotodateien bleiben unberührt, bis eine intakte Generation gefunden ist.

## Messungen

JSON und SQLite wurden auf demselben Mac mit diesen Befehlen aus `negaflow-mac/` verglichen.

<details>
<summary>Messbefehle</summary>

```bash
cd negaflow-mac

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

Gemessen am 2026-07-12 auf einem Mac14,3 (arm64 mit 8 Kernen und 24 GiB unter macOS 26.5 im Swift-Release-Build). Die Zahlen sind eine Regressionsbasis für diesen Aufbau, keine Vorhersage für einen anderen Mac.

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
- Auf macOS gehört die SQLite-C-API zum System, sodass kein neues Paket nötig ist; Windows nutzt `Microsoft.Data.Sqlite`.
- Die Wiederherstellungsregel bleibt bestehen: Ein beschädigter Speicher gilt nie als leere Mediathek.

Es läuft mit `journal_mode=DELETE` und `synchronous=FULL`. Mit WAL müssten Datenbank und `-wal`-Datei als eine Einheit behandelt werden. Die laufende Datenbank wird nicht direkt kopiert. Nur die nach dem Schließen der Verbindung geprüfte Hauptdatei wird zur Wiederherstellungskopie.

## Wer im Code was tut

- `LibraryCatalogSQLiteStore` (Windows: `SqliteCatalogStore` und `SqliteCatalogSchema`): Verbindung und Transaktionen, Schemaversion und Integritätsprüfungen
- `LibraryCatalogSQLiteMigration` und `LibraryCatalogFile` (Windows: `CatalogVersionMigration`): lesender Import älterer JSON-Dateien und Upgrades je Version
- Entitätstabellen: `catalog_metadata` plus 9 Entitätstabellen (`folders`, `frames` mit eingebetteten Originalverweisen, `rolls`, `scan_sessions`, `scan_roll_assignments`, `manual_collections`, `smart_collections`, `saved_searches`, `stacks`), geordnet über die Spalte `position` jeder Tabelle
- `LibraryBackupStore` (Windows: `CatalogBackupStore`): Backups und Wiederherstellungen

Entwicklungswerte und versionierter Bearbeitungsverlauf liegen als JSON-BLOB je Entität vor. Quellpixel, Miniaturen und GrainMend-Caches bleiben außerhalb der Datenbank. Für Suche und Sortierung fehlen noch Spalten und Indizes, deshalb wird der ganze Katalog beim Start in den Speicher geladen, und die SQLite-Lesezeit sieht derzeit aus wie die von JSON. Der nächste Schritt sind Indexabfragen, die nur die verwendeten Spalten und Bilder lesen.

## Älteres JSON übernehmen

1. JSON-Version und `LibraryCatalogHealthInspector` prüfen.
2. Eine temporäre SQLite-Datenbank anlegen.
3. Das Material in einer Transaktion übertragen.
4. IDs, Reihenfolge, Zugehörigkeit und Aufträge vergleichen.
5. `integrity_check` und die Sicherheitsbedingungen prüfen.
6. Das JSON als Wiederherstellungsgeneration behalten.
7. Auf SQLite als Hauptspeicher umschalten.

Scheitert ein Schritt, bleibt das vorhandene JSON unverändert, und ein leerer Katalog wird nie gestartet. `library.sqlite-migration.json` existiert nur während der laufenden Migration, um einen unterbrochenen Umzug fortzusetzen, wenn Quell-SHA-256 und beide Kataloge übereinstimmen, und wird nach Abschluss gelöscht. Danach wird `library.json` nach `library.pre-sqlite-<sha12>.json` verschoben, und es gibt keinen automatischen Rückfall auf JSON. `minimumReaderVersion` verhindert, dass ältere Builds neuere Kataloge öffnen.

## Quellen

- [Apple: Tuning for Performance and Responsiveness](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/Performance/Performance.html)
- [Apple: Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [SQLite: Atomic Commit](https://sqlite.org/atomiccommit.html)
- [SQLite: Write-Ahead Logging](https://sqlite.org/wal.html)
