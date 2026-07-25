# Checkliste für echte Geräte

[Dokumentationsstart](../README.md)

Das sind die Punkte, die automatische Tests und Builds nicht bestätigen können. Das Endergebnis
auf dem Bildschirm und die echte Hardware prüft der Nutzer. Ein Release-Kandidat wird erst
freigegeben, wenn jeder zutreffende Pflichtpunkt ein Ergebnis und einen Beleg hat.

Tragen Sie jedes Ergebnis als `PASS`, `FAIL`, `BLOCKED` oder `N/A` ein. `FAIL`, `BLOCKED` und
`N/A` brauchen eine Begründung.

> [!IMPORTANT]
> Ein Build ohne ausgefüllte Tabelle gilt nicht als geprüft für echte Geräte, endgültige
> Bildqualität, Signatur oder Notarisierung. Bestandene automatische Tests ersetzen das nicht.

## Durchlaufprotokoll

- Release-Kandidat:
- App-Version und Build:
- Commit oder Quellkopie:
- macOS-Version:
- Mac-Modell, Architektur, Speicher:
- Display, Skalierung, HDR-Zustand:
- Version des Scanner-Plugins:
- Scannermodell und Anschluss:
- Geprüft von:
- Datum:

## 1. Installation und erster Start

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | Die Prüfsumme von ZIP/DMG stimmt mit dem veröffentlichten Wert überein. |  |
|  | Auf einem frischen Benutzerkonto kopiert es sich nach `/Applications` und startet. |  |
|  | Gatekeeper zeigt den erwarteten Unterzeichner und Notarisierungsstand. |  |
|  | Der erste Start legt nur die in der Doku genannten App-Daten an. |  |
|  | Ohne Scanner-Plugin schaltet sich kein erfundenes Gerät und keine erfundene Funktion ein. |  |
|  | App-Angaben, Version, Build, Lizenz und Hilfe stimmen. |  |

## 2. Import, Entwicklung, Export

Nehmen Sie mindestens ein JPEG, ein TIFF, ein DNG/RAW, das der aktuelle Decoder liest, und eine
hochauflösende Datei. Notieren Sie den Quell-SHA-256 vor und nach dem Durchlauf.

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | Die Quell-Bytes sind vor und nach dem Import gleich. |  |
|  | Warnung und Auswahl beim doppelten Import sind leicht zu verstehen. |  |
|  | Der Startzustand ist manuelle Korrektur mit dem Ziel `main`. |  |
|  | Zuschnitt, Ausrichtung, Tonwert, Farbe, Detail, lokale Korrektur und Widerrufen arbeiten wie erwartet. |  |
|  | Vergleich Original/Entwicklung und Clipping-Anzeige passen zum Export. |  |
|  | JPEG und 16-Bit-TIFF öffnen sich, und ihre Metadaten stimmen. |  |
|  | Namenskonflikte, Abbruch, Fehler und Fortsetzen lassen nie einen Teil der Dateien als erfolgreich zurück. |  |
|  | Fehlt der nötige Bearbeitungsverlauf oder Cache, kommt ein Fehler statt eines Exports der Quelle. |  |

## 3. Katalog, Sicherung, Offline-Originale

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | Nach einem Neustart kommen Bilder, Auswahl, Filme und Sammlungen, Bewertungen und Bearbeitungen zurück. |  |
|  | Ein abgebrochener Speichervorgang lässt den letzten intakten Katalog und dessen Sicherung stehen. |  |
|  | Ein fehlender oder kaputter Katalog hält am Wiederherstellungsbildschirm statt leer zu öffnen. |  |
|  | Sicherung anlegen, Wiederherstellung vorab ansehen, wiederherstellen und neu starten gelingen. |  |
|  | Offline-Originale sind klar gekennzeichnet, und die Quelle wird nicht an ihrer Stelle exportiert. |  |
|  | Das richtige Original verbindet sich neu, eine andere Datei wird abgelehnt. |  |
|  | Das Entfernen aus der Bibliothek löscht das Original nicht. |  |
|  | Das Verschieben in den Papierkorb ist eine bewusste Wahl und bleibt auch mit virtuellen Kopien eindeutig. |  |

## 4. Fenster, Anzeige, Bedienungshilfen

Prüfen Sie die kleinste Fenstergröße, ein großes Fenster, Retina-Skalierung, Bewegung
reduzieren, Kontrast erhöhen, VoiceOver, vollen Tastaturzugriff und eine andere Sprache als
Koreanisch.

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | Schaltflächen in Seitenleiste, Leinwand, Inspektor, Sheets, Einstellungen und Hilfe werden nicht abgeschnitten. |  |
|  | Beim Ändern der Fenstergröße bleiben Panelbreite und Fokus auf der Leinwand brauchbar. |  |
|  | Ein Neustart stellt das unterstützte Bildschirmlayout wieder her. |  |
|  | Text fällt nie unter die festgelegte Größe, wichtige Werte werden nicht abgeschnitten. |  |
|  | Der Zustand von Reglern, Farbrädern, Kurven, geteilten Schaltflächen, Schaltern und Auswahl ist ablesbar. |  |
|  | Namen, Werte, Hinweise, Schrittweiten und Auswahländerungen in VoiceOver stimmen. |  |
|  | Die Tastaturreihenfolge folgt dem sichtbaren Ablauf, der Fokus bleibt nicht hängen. |  |
|  | Bewegung reduzieren entfernt überflüssige Animation, Kontrast erhöhen bleibt lesbar. |  |
|  | Produkttexte wechseln die Sprache, technische IDs bleiben unverändert. |  |
|  | Liquid-Glass-Flächen zeigen keinen sichtbaren Schatten. |  |

## 5. Externe Plugins und echte Scanner

Die SANE-Umsetzung wird aus der separaten Auslieferung `negaflow-scanner-sane` installiert und
eingerichtet. Belege zu Plugin und Gerät gehören in jenes Repository und in dieses Protokoll.

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | Ein erstmals gesehenes Plugin muss vom Nutzer freigegeben werden. |  |
|  | Löschen oder Austauschen eines Plugins macht die frühere Freigabe ungültig. |  |
|  | Die Gerätesuche zeigt nur echte Geräte, die das Plugin gemeldet hat. |  |
|  | Auflösung, Bittiefe, Modus, Bereich, Vorschau, Belichtung und IR zeigen nur gemeldete Fähigkeiten. |  |
|  | Nicht unterstützte Fähigkeiten sind ausgeblendet oder nennen einen genauen Grund für die Sperre. |  |
|  | Vorschau, vollständiger Scan, Abbruch, Zeitüberschreitung, Trennung und Plugin-Ende laufen sauber aus. |  |
|  | Größe, Bittiefe, Bereich und angewandte Einstellungen des Ergebnisses passen zu den gemeldeten Werten. |  |
|  | `detect --json` und `capabilities <id> --json` in der CLI stimmen mit der App-Oberfläche überein. |  |
|  | Plugin-Dateien, Abhängigkeiten, Konfiguration und Protokolle liegen außerhalb der App und dieses Repositorys. |  |

## 6. GrainMend und Bildqualität

Decken Sie Farbnegativ, unterstütztes chromogenes Schwarzweiß, gewöhnliches Silber-Schwarzweiß,
Dias, saubere Bilder, Staub, Kratzer, Korn, Gesichter, Himmel und feine Muster ab.

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | GrainMend wird nicht als dasselbe wie fremde Hardware-IR-Reinigung dargestellt. |  |
|  | Die Zieldefekte gehen zurück, ohne Textur und Kanten zu ruinieren. |  |
|  | Fehlfunde auf sauberen Bildern bleiben vertretbar. |  |
|  | RGB und IR passen zusammen, versetztes oder nicht unterstütztes Material scheitert deutlich. |  |
|  | IR hält die Grenzen je Filmtyp ein und bewahrt das Ausgangsmaterial. |  |
|  | 100-%-Ausschnitte und Masken vor und nach dem Eingriff werden mit Einstellungen und App-Version aufbewahrt. |  |

## 7. Leistung und Speicher

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | Wiederholtes Regeln und Verschieben auf einem 24-MP-Foto bleibt brauchbar. |  |
|  | Wiederholtes Regeln und Verschieben auf einem 48-MP-Foto bleibt brauchbar. |  |
|  | Entwicklung und Export laufen bei Scangrößen von 3600 DPI und 7200 DPI durch. |  |
|  | Ein Film mit 48 Bildern vermischt nie den Zustand zwischen den Bildern. |  |
|  | Bei Speicherdruck fallen nur nicht ausgewählte Caches weg, das aktuelle Bild bleibt. |  |
|  | Suche, Filter und Sortierung in einem großen Katalog bleiben auf dem getesteten Mac brauchbar. |  |
|  | Wärme, Speicher und Festplattennutzung langer Läufe werden notiert. |  |

## 8. Aktualisierung und Auslieferung

| Ergebnis | Was zu prüfen ist | Beleg oder Problem |
|---|---|---|
|  | Vorhandene Kataloge und Sidecar-Dateien überstehen die Aktualisierung. |  |
|  | Nicht unterstützte ältere Versionen und Schemata scheitern sauber und nennen den Weg zurück. |  |
|  | Das Release-Paket enthält App, dSYM, Prüfsummen, Lizenz und die nötigen Listen. |  |
|  | Testmaterial, Originale, Zugangsdaten und die Plugin-Umsetzung sind nicht im Paket. |  |
|  | Bekannte Probleme sowie Geräte- und Profilbelege passen zu den Release Notes. |  |

Auslieferungsentscheidung: `APPROVE`, `REJECT`, `BLOCKED`

- Entscheidung:
- IDs blockierender Probleme:
- IDs akzeptierter nicht blockierender Probleme und Begründung:
- Ablageort der Belege:
- Unterschrift:

Tritt einer der folgenden Punkte auf, gilt bis zur Korrektur und erneuten Prüfung automatisch
`REJECT`.

- Die Quelle wird verändert
- Der Katalog wird stillschweigend zurückgesetzt
- Bei einem Exportfehler wird auf die Quelle ausgewichen
- Erfundene Scannerfunktionen werden angezeigt
- Nur ein Teil der Ausgabe wird veröffentlicht
- Signatur oder Notarisierung passen nicht zusammen
- Datenverlust
