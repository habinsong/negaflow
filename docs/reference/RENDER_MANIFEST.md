# Render manifest

[Docs home](../README.md)

`renderManifest` in the sidecar links the source, the edit values and the final file with SHA-256. File paths are not recorded.

> [!IMPORTANT]
> `renderManifest` records hash relationships between files and settings. It has no digital signature or certificate, so it is not C2PA Content Credentials.

## What v3 holds

- Source byte count, SHA-256 and the algorithm name `sha-256`
- Which render input was actually used
- The checked scope of the GrainMend cache file or memory input
- SHA-256 of the develop, GrainMend and export settings
- SHA-256 of the scanner profile
- Decoder origin and Chroma Engine renderer version
- SHA-256, byte count, pixel size and format of the final file

After the encoder finishes, the file is opened again with ImageIO to confirm the pixel size, and the whole file is hashed. The sidecar is written after that. If the v3 check fails, the result is not published as a finished output set.

## GrainMend input

- `cleanedMemory`: pixels in memory have no standard hash, so the checked scope is recorded as `sourceAndDevelopRecipe`. The SHA-256 of the GrainMend edit history is always included.
- `cleanedFile`: the whole GrainMend cache file and the edit history are both hashed.

v1 and v2 files still open. Hashes that did not exist then are not filled in later.

## Difference from C2PA

There is no digital signature, certificate, trust chain or embedded claim store, only SHA-256 values that can be checked. C2PA's hard binding and processing history and PREMIS's integrity idea served as references.

Sources:

- [C2PA Content Credentials 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html)
- [C2PA hard-binding guidance](https://spec.c2pa.org/specifications/specifications/2.4/guidance/Guidance.html)
- [PREMIS preservation metadata](https://www.loc.gov/standards/premis/)
- [Apple Image I/O orientation and image properties](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
