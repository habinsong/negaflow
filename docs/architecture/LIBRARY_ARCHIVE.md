# Library archive

[Docs home](../README.md)

A catalog backup gets the app running again and does not hold the original photos. Both platforms write `.negaflowarchive`, using different package formats and contents on macOS and Windows.

> [!WARNING]
> If an archive fails to build, originals, third-party XMP, the running catalog, and any existing archive stay untouched.

## macOS archive (BagIt folder)

On macOS, `.negaflowarchive` is a folder following the [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html) layout that bundles catalog state with the referenced photos.

| Included | Left out |
|---|---|
| Portable catalog JSON | The live SQLite file |
| Referenced originals and remaining IR originals | Thumbnails and previews |
| GrainMend defect recipes | GrainMend caches that can be rebuilt |
| Virtual-copy links to shared originals | Exported files |

Content files and tag files get separate SHA-256 manifests (`manifest-sha256.txt` and `tagmanifest-sha256.txt`). `negaflow-archive.json` connects frame IDs to stored file IDs. Virtual copies of one original share a single stored copy.

Writing refuses to overwrite an existing destination path. The temporary folder moves to its final path only after all of these pass:

1. The current app can read the catalog safely.
2. Originals and IR inputs are regular files, and their size and modification time do not change while copying.
3. Every needed GrainMend defect recipe can be read.
4. SHA-256 hashes (`manifest-sha256.txt`, `tagmanifest-sha256.txt`), byte counts, the file list, and `Payload-Oxum` match.
5. The links from frames to originals, IR files, and GrainMend recipes match the catalog.

On failure, only the half-built temporary folder is deleted.

## Windows archive (ZIP file)

On Windows, `.negaflowarchive` is a ZIP archive of catalog and defect state. It does not copy original photo files.

| Included | Left out |
|---|---|
| `library.sqlite` | Original photo files and IR originals |
| `defects/*` defect recipes | Thumbnails, previews, and rebuildable caches |
| `archive.json` (byte counts and SHA-256 hashes per entry) | Exported files |

Windows writes the archive into a temporary file and replaces the destination atomically once staging and verification finish. If building fails, the temporary file is removed and any existing archive at the destination stays untouched.

## Limits

macOS and Windows `.negaflowarchive` packages use different formats and catalog schemas, so an archive moves between machines on the same platform. Original formats are kept as they are, with no conversion for long-term compatibility. PREMIS preservation events, agent records, and migration to recommended formats are outside v1.

One archive is not a preservation plan. Keep copies on other media in another place, and check the hashes on a schedule.

Sources:

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
