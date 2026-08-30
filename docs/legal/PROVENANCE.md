# Code and resource provenance

[Docs home](../README.md)

This is where the Apache-2.0 distribution scope of the negaflow app is written down. It is not a legal opinion. It is a provenance record so the repository and the release artifacts can be checked again.

## Code

`Sources`, `Tests`, and `scripts` are Swift, Python, and shell code written for negaflow. The app has no C/C++/Objective-C source, no external package, no static or dynamic library, and no vendored source tree. Only the system frameworks Apple ships with macOS are linked.

Film inversion uses the published sensitometry ideas of density, toe, straight line, and shoulder. The curves and coefficients here come from negaflow's four photometric anchors, not from a third-party program's formulas or constants. The equations and the derivation are in [fixed print response](../reference/PRINT_RESPONSE.md).

The film-stock Dmin and Dmax presets are the one place where published third-party material reaches a shipped constant. Those numbers are approximate readings of the characteristic curves in manufacturer datasheets, and `FilmStockDmin` marks every entry as `datasheetCurve` or `estimated` so the origin stays visible. Numbers read off a published chart are facts about the film, not a copy of anyone's code or text, and a measured film base from the scan always wins over them.

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

The release check confirms again that no plugin, SANE executable, or library slipped into the app bundle. The plugin side ships its own `LICENSE`, `COPYING`, complete corresponding source, and third-party notices.

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

Film, scanner, color space, XMP namespace, and product names identify targets and keep files interoperable. No trademark ownership or affiliation is claimed. The full scope is in [`TRADEMARKS.md`](../../TRADEMARKS.md).

## Automated checks and what they miss

`python3 scripts/ci/verify-provenance.py` fails on any of these.

- A bundled resource that is not registered, or whose hash changed
- C/C++/Objective-C, external packages, binary archives, or a vendor tree in the app
- SANE-only names or traces of a checked external implementation in the app code
- A change that makes the release script put the SANE plugin in the app
- FILM-R image material in the repository

The check stops obvious regressions in the current tree. It does not prove similarity against the whole internet, rights to photographic or profile inputs, patents, trademarks, or legal outcomes in any country. When an origin changes, review the declaration together with the hash. When it is unclear, take the resource out of the release and ask the rights holder or a specialist.
