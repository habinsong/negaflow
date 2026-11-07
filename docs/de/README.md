# negaflow-Dokumentation

Nach Themen getrennt, damit Sie direkt das passende Dokument öffnen.

[English](../README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [简体中文](../zh-Hans/README.md) · [Français](../fr/README.md) · Deutsch

> [!NOTE]
> negaflow 1.2.6 läuft auf macOS und Windows. Beide Apps sind getrennt geschrieben und liefern aus derselben Datei dasselbe Bild.

## Plattform

| Dokument | Wann lesen |
|---|---|
| [Wo sich die macOS- und die Windows-Version unterscheiden](platform/PLATFORM_DIFFERENCES.md) | Sie wollen wissen, was gleich ist und was nicht |
| [macOS-Dokumentation](../../negaflow-mac/docs/README_de.md) | Sie installieren, bauen oder nutzen die CLI unter macOS |
| [Windows-Dokumentation](../../negaflow-windows/docs/README_de.md) | Sie installieren, bauen oder prüfen die Engine unter Windows |

## Produkt

| Dokument | Wann lesen |
|---|---|
| [Von der Mediathek zum Abzug](product/WORKFLOW.md) | Sie brauchen das Verhalten von Import, Ordnerentwicklung, Kopieren und Einfügen oder Abzug |
| [Chroma Engine](product/CHROMA_ENGINE.md) | Sie wollen Filminvertierung und Entwicklungsreihenfolge sehen |
| [GrainMend](product/GRAINMEND.md) | Sie wollen wissen, wie die Reparatur von Staub und Kratzern arbeitet |
| [Filmprofile](product/FILM_PROFILES.md) | Sie wollen wissen, woher die mitgelieferten Profile stammen und wo ihre Grenzen liegen |

## Struktur

| Dokument | Wann verwenden |
|---|---|
| [Produktstruktur](architecture/PRODUCT_ARCHITECTURE.md) | Datenfluss zwischen App, Engine, Speicher und Export |
| [Katalogspeicherung](architecture/CATALOG_STORAGE.md) | SQLite-Katalog, Import des älteren JSON-Katalogs, Messwerte |
| [Scanner-Plugin-Struktur](architecture/SCANNER_PLUGINS.md) | Externer Prozess, Freigabe, Veröffentlichung der Scandateien |
| [Mediatheksarchiv](architecture/LIBRARY_ARCHIVE.md) | Originale und Bearbeitungsverlauf gemeinsam gespeichert |

## Referenz

| Dokument | Inhalt |
|---|---|
| [Scanner-CLI-JSON](reference/CLI_JSON.md) | Ausgabe von `detect --json` und `capabilities --json` |
| [Render-Protokoll](reference/RENDER_MANIFEST.md) | SHA-256-Verknüpfung von Quelle, Bearbeitungswerten und Ausgabedatei |
| [Abzugslayouts und C-Print-Vorschau](reference/C_PRINT.md) | Acht Layouts, Export fertiger Seiten, ICC nur für die Probe, Genauigkeitsgrenzen |
| [Negativantwort](reference/PRINT_RESPONSE.md) | Formel und Ankerpunkte von `shoulder-print-response-v4` |
| [Qualitätsprüfung der Scannerprofile](reference/PROFILE_QUALITY_GATE.md) | Freigaberegeln für REAL/TARGET-Paare |
| [Scanner-Rauschprofile](reference/SCANNER_NOISE_PROFILES.md) | Messung mit Wiederholscans und wann sie greift |
| [Filme, die GrainMend IR meidet](reference/INFRARED_LIMITS.md) | Schwarzweiß, Kodachrome, Grenzen der RGB/IR-Ausrichtung |
| [Wie die Bilderkennung am Flachbettscanner den Film findet](reference/FRAME_DETECTION.md) | Film oder leerer Halter, Bildgrenzen |
| [IT8-Farbprüfung](reference/IT8_COLOR_VALIDATION.md) | Feldmessung, Belegstufen, synthetische Regression |

## Herkunft und Auslieferung

| Dokument | Inhalt |
|---|---|
| [Herkunft von Code und Ressourcen](legal/PROVENANCE.md) | Sie prüfen die Grenze zwischen Apache und GPL oder die Hashes der mitgelieferten Ressourcen |
| [`TRADEMARKS.md`](../../TRADEMARKS.md) | Sie prüfen, wie Film-, Scanner- und Produktnamen verwendet werden |

## Wie das geschrieben ist

- Produktdokumente beschreiben, was Nutzer heute sehen.
- Architekturdokumente beschreiben Zuständigkeiten und Datenfluss.
- Referenzdokumente lassen Codewerte, Feldnamen und Hashes unverändert.
- Prüfdokumente trennen, was bestanden hat, von dem, was nicht geprüft ist.
- Ein Abschnitt, der in einer Sprache vorkommt, kommt in allen sechs vor.
