# Render-Protokoll

[Dokumentationsstart](../README.md)

Das `renderManifest` in der Sidecar-Datei verknüpft Quelle, Bearbeitungswerte und fertige Datei per SHA-256. Dateipfade werden nicht aufgezeichnet.

> [!IMPORTANT]
> Das `renderManifest` hält Hash-Beziehungen zwischen Dateien und Einstellungen fest. Es hat weder digitale Signatur noch Zertifikat und ist deshalb keine C2PA Content Credentials.

## Inhalt von v3

- Bytezahl der Quelle, SHA-256 und der Algorithmusname `sha-256`
- Welche Render-Eingabe tatsächlich verwendet wurde
- Der geprüfte Umfang der GrainMend-Cachedatei oder der Speichereingabe
- SHA-256 der Einstellungen für Entwicklung, GrainMend und Export
- SHA-256 des Scannerprofils
- Herkunft des Decoders und Version des Chroma-Engine-Renderers
- SHA-256, Bytezahl, Pixelgröße und Format der fertigen Datei

Nach dem Schreiben des Encoders wird die Datei mit ImageIO erneut geöffnet, um die Pixelgröße zu prüfen, und als Ganzes gehasht. Danach wird die Sidecar-Datei geschrieben. Schlägt die v3-Prüfung fehl, wird das Ergebnis nicht als fertiger Ausgabesatz veröffentlicht.

## GrainMend-Eingabe

- `cleanedMemory`: Pixel im Speicher haben keinen Standard-Hash, deshalb wird der geprüfte Umfang als `sourceAndDevelopRecipe` vermerkt. Der SHA-256 des GrainMend-Verlaufs ist immer enthalten.
- `cleanedFile`: Die gesamte GrainMend-Cachedatei und der Verlauf werden gehasht.

Dateien der Versionen v1 und v2 lassen sich weiterhin öffnen. Hashes, die es damals nicht gab, werden nicht nachträglich ergänzt.

## Unterschied zu C2PA

Es gibt keine digitale Signatur, kein Zertifikat, keine Vertrauenskette und keinen eingebetteten Claim-Speicher, nur prüfbare SHA-256-Werte. Das Hard Binding und der Verarbeitungsverlauf von C2PA sowie der Integritätsgedanke von PREMIS dienten als Vorbild.

Quellen:

- [C2PA Content Credentials 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html)
- [C2PA hard-binding guidance](https://spec.c2pa.org/specifications/specifications/2.4/guidance/Guidance.html)
- [PREMIS preservation metadata](https://www.loc.gov/standards/premis/)
- [Apple Image I/O orientation and image properties](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
