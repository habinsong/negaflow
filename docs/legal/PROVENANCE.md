# Code and resource provenance

[Docs home](../README.md)

This document records the Apache-2.0 distribution scope of the negaflow app. It is a provenance record to verify the repository and release artifacts, and does not constitute legal advice.

## Code

The Swift, Python and shell integration in `negaflow-mac` is written for negaflow. Negative camera RAW decoding uses an unmodified, pinned LibRaw revision as a replaceable `libraw.dylib`, distributed under CDDL-1.0. The app includes its source archive, build script, copyright and license files in `Contents/Resources/licenses/libraw/`. No LibRaw source is merged into the Apache source tree. Windows uses the same upstream revision; its other components are recorded in [`negaflow-windows/THIRD-PARTY-NOTICES.md`](../../negaflow-windows/THIRD-PARTY-NOTICES.md). The test-only `CameraNativeRaw.dng` is CC0-1.0 material from raw.pixls.us entry 2204, identified by its adjacent source JSON, and is excluded from the application.

If the supplemental notice file is absent, the build and packaging steps warn and continue. Upstream licence files and corresponding source remain included.

Film inversion uses the published sensitometry ideas of density, toe, straight line, and shoulder. The curves and coefficients here come from negaflow's four photometric anchors, not from a third-party program's formulas or constants. The equations and the derivation are in [fixed print response](../reference/PRINT_RESPONSE.md).

Published manufacturer datasheets inform three groups of shipped film constants: film-stock Dmin and Dmax presets (`FilmStockDmin`), black-and-white spectral and characteristic-curve presets (`BWFilmProfile`), and physical grain and MTF parameters (`DigitalFilmPhysics`). Those numbers are approximate readings or fits from published technical data sheets, and `FilmStockDmin` marks every entry as `datasheetCurve` or `estimated` so the origin stays visible. Numbers read off a published chart are facts about the film, not a copy of anyone's code or text, and a measured film base from the scan always wins over them.

GrainMend IR runs in this order.

1. Estimate the integer offset between RGB and IR on its own.
2. Interpolate trimmed IR means per `log(red)` bin to build a non-parametric scene leakage curve.
3. Subtract the scene leakage, then compute relative contrast against the local mean.
4. Build the defect mask from a trimmed local noise threshold, connected components, and orientation.

This code does not link or port SANE's IR correction. Published papers and product pages are background for confirming the physical limits of film and infrared. Taking a method or a principle is one thing, copying the expression of code is another. The U.S. Copyright Office draws the same line between methods and systems and their concrete expression.

- [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf)
- [SANE backends source repository](https://gitlab.com/sane-project/backends)

## SANE plugin boundary

The app has no `scanimage`, no SANE headers, no backend configuration, and no device-specific processing code. It talks to the installed external program through a versioned JSON/NDJSON contract only. The real SANE work ships as a separate GPL-2.0-or-later repository and executable.

Being a separate process does not settle the license question by itself. The GNU FAQ says pipe or command-line communication usually looks like separate programs, but that the answer can change if the communication is too intimate. So the contract exchanges device-independent requests, capabilities, progress, and result file information, and shares no SANE data structures.

- [GNU license FAQ: aggregates and separate programs](https://www.gnu.org/licenses/gpl-faq.en.html)
- [Apache License 2.0 and GPL compatibility](https://www.apache.org/licenses/GPL-compatibility)
- [Scanner plugin architecture](../architecture/SCANNER_PLUGINS.md)

The release check confirms again that no plugin, SANE executable, or SANE library slipped into the app bundle. The plugin side ships its own `LICENSE`, `COPYING`, complete corresponding source, and third-party notices.

## Bundled resources

[`Config/bundled-resource-provenance-v1.json`](../../negaflow-mac/Config/bundled-resource-provenance-v1.json) pins the declared origin, license, and SHA-256 of every resource that goes into the app and the source tree.

| Group | Origin | What ships |
|---|---|---|
| ScannerKit TIFF | Layout material shot and prepared by the maintainer | 4 TIFF files |
| App icon | Project artwork from the maintainer | Source PNG, build PNG, ICNS |
| Look presets | Values written for negaflow | 6 JSON files |
| Scanner profiles | Built from scan measurements the maintainer keeps | Numeric profiles, without the source scans |

The camera and color space metadata you can see in the TIFF files is container information from shooting and encoding. `sourceProfiles` in a scanner profile is the logical path of local measurement material at build time, and those source photographs do not ship.

FILM-R v2 material is downloaded only during quality measurement. The images never enter the repository or the app. The DOI version, CC BY 4.0, file sizes, and hashes are pinned in [`Config/defect-corpus-film-r-v2.json`](../../negaflow-mac/Config/defect-corpus-film-r-v2.json).

## Names and interoperability

Film, scanner, color space, XMP namespace, and product names identify targets and keep files interoperable. Output ICC profiles synthesized by the Windows engine use descriptive labels (`"Negaflow Compatible P3"`, `"Compatible with Adobe RGB (1998)"`) and a `CC0 1.0 Universal` dedication so exported user images carry no profile copyright restrictions. No trademark ownership or affiliation is claimed. The full scope is in [`TRADEMARKS.md`](../../TRADEMARKS.md).

## Automated checks and what they miss

`python3 scripts/ci/verify-provenance.py` fails on any of these.

- A bundled resource that is not registered, or whose hash changed
- C/C++/Objective-C, external packages, binary archives, or a vendor tree in the app
- SANE-only names or traces of a checked external implementation in the app code
- A change that makes the release script put the SANE plugin in the app
- FILM-R image material in the repository

The check stops obvious regressions in the current tree. It does not prove similarity against the whole internet, rights to photographic or profile inputs, patents, trademarks, or legal outcomes in any country. When an origin changes, review the declaration together with the hash. When it is unclear, take the resource out of the release and ask the rights holder or a specialist.
