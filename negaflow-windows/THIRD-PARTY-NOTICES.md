# Third-Party Notices — negaflow for Windows

negaflow itself is licensed under the Apache License 2.0. See the repository
[LICENSE](../LICENSE) and [NOTICE](../NOTICE).

This file records the third-party components that are, or may be, redistributed
with a negaflow Windows binary distribution, together with the notices those
components require. It is generated from the pinned dependency set declared in
[`third_party/manifest/components.json`](third_party/manifest/components.json)
and must be reviewed against the exact release payload before any distribution.

The native imaging engine (`Negaflow.Native.dll`, `negaflow-cli.exe`) links no
third-party code. Its only imports are Windows system libraries
(`kernel32`, `bcrypt`, `mscms`, `ole32`, `shlwapi`), so it contributes no
obligations to this file.

That zero-dependency statement is about **linking**, and about the native engine
rather than the distribution as a whole. Two third-party **native** binaries do
ship alongside it, and neither appears in the engine's import table:

- `e_sqlite3.dll` — the managed catalog layer, as of 2026-08-07, section 3 below.
  See [ADR-0025](docs/decisions/0025-managed-sqlite-catalog-provider.md).
- `libraw.dll` — the camera RAW decoder, as of 2026-08-25, section 4 below. The
  engine resolves it at run time with `LoadLibraryExW`/`GetProcAddress` and runs
  without it. Windows ships no RAW codec of its own, so this is what keeps RAW
  import working on a machine that does not have Microsoft's Store extension.

---

## 1. Microsoft Windows App SDK (WinUI 3)

- Packages: `Microsoft.WindowsAppSDK.Runtime` 1.8.260710003,
  `Microsoft.WindowsAppSDK.WinUI` 1.8.260709004, and their pinned transitive
  packages `Microsoft.WindowsAppSDK.Base` 1.8.251216001,
  `Microsoft.WindowsAppSDK.Foundation` 1.8.260709000,
  `Microsoft.WindowsAppSDK.InteractiveExperiences` 1.8.260708001.
- License: **MICROSOFT SOFTWARE LICENSE TERMS — MICROSOFT WINDOWS APP SDK**
  (proprietary; not an open-source license).
- Redistribution basis: Section 3(a)(i) of those terms states that files
  binplaced with the application by the Windows App SDK NuGet package are
  permitted to be redistributed, for both framework-dependent and self-contained
  deployment.
- Obligation: the full license terms must accompany the distribution. The
  canonical text ships inside each package as `license.txt`; the packaging step
  copies it from the restored package directory for the exact pinned version
  rather than from a hand-copied excerpt, so that the shipped text always matches
  the shipped binaries.
- Reference: <https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI/1.8.260709004/License>

Note that these terms also carry data-collection provisions (Section 2). The
current shell does not enable Windows App SDK telemetry features, but this must
be re-checked before release.

## 2. Microsoft Edge WebView2 — NOT redistributed

- Package: `Microsoft.Web.WebView2` 1.0.3179.45 (transitive, via WinUI).
- License: **BSD 3-Clause**.
- **Status: excluded from the distribution.** The shell contains no reference to
  WebView2 and renders no web content. The WinUI package graph used to binplace
  `Microsoft.Web.WebView2.Core.dll`,
  `Microsoft.Web.WebView2.Core.Projection.dll`, and `WebView2Loader.dll`
  (~1.6 MB) into the output; the `RemoveUnusedWebView2Payload` target in
  `src/Shell/Negaflow.Shell.csproj` now removes them from the copied output on
  both x64 and ARM64. See
  [ADR-0022](docs/decisions/0022-webview2-payload-boundary.md).
- Because no WebView2 binary is shipped, **no WebView2 notice obligation
  currently applies.**

Note that the exclusion target prevents copying but does not delete files left by
an earlier build. Release payloads must therefore be produced from a clean build.

The text below is retained so the obligation can be met immediately if the
WebView2 payload is ever reintroduced. It is reproduced verbatim from
`LICENSE.txt` in the pinned package, and **is not currently an active notice**:

```
Copyright (C) Microsoft Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * The name of Microsoft Corporation, or the names of its contributors
may not be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

WebView2 additionally ships a `NOTICE.txt` listing components Microsoft
incorporated into it, including an offer to provide corresponding source for
components under copyleft terms. Dropping the payload also drops that chain. If
the payload is ever reintroduced, that `NOTICE.txt` must be reproduced alongside
this file, unmodified, from the pinned package directory — it is Microsoft's own
attribution document and must not drift from the version actually shipped.

## 3. SQLite catalog stack

The catalog store (`Negaflow.Catalog.Core`) uses SQLite through the managed
provider. The packages are referenced separately rather than through the
convenience `Microsoft.Data.Sqlite` package, so that the native SQLite version
can be raised on its own; see
[ADR-0025](docs/decisions/0025-managed-sqlite-catalog-provider.md) for why that
matters here.

| Package | Version | License | Shipped payload |
|---|---|---|---|
| `Microsoft.Data.Sqlite.Core` | 10.0.10 | MIT | `Microsoft.Data.Sqlite.dll` |
| `SQLitePCLRaw.config.e_sqlite3` | 3.0.5 | Apache-2.0 | `SQLitePCLRaw.batteries_v2.dll` |
| `SQLitePCLRaw.provider.e_sqlite3` | 3.0.5 | Apache-2.0 | `SQLitePCLRaw.provider.e_sqlite3.dll` |
| `SQLitePCLRaw.core` | 3.0.5 | Apache-2.0 | `SQLitePCLRaw.core.dll` |
| `SourceGear.sqlite3` | 3.53.4 | Apache-2.0 | `runtimes\win-x64\native\e_sqlite3.dll`, `runtimes\win-arm64\native\e_sqlite3.dll` |

- **MIT** (`Microsoft.Data.Sqlite.Core`): the licence text and copyright notice
  must accompany the distribution. Copy it from `LICENSE.txt` in the restored
  package directory for the exact pinned version.
- **Apache-2.0** (the four SQLitePCLRaw and SourceGear packages): section 4(a)
  requires a copy of the licence with the distribution, and section 4(d)
  requires that any `NOTICE` file carried by those packages be reproduced.
  Take both from the restored package directories for the pinned versions
  rather than from a hand-copied excerpt.
- **SQLite itself is in the public domain** and imposes no obligation. The
  Apache-2.0 terms above come from SourceGear's packaging of the build, not
  from SQLite.

`SourceGear.sqlite3` carries native binaries for around 30 runtime identifiers.
The `RestrictRuntimeTargetsToWindows` target in `Directory.Build.targets` keeps
only `win-x64` and `win-arm64` in the build output, which drops roughly 48 MB of
Android, iOS, Linux and WebAssembly binaries that this product cannot execute.
Those excluded binaries are not distributed and carry no notice obligation here.
As with the WebView2 exclusion, the target prevents copying but does not delete
files left by an earlier build, so release payloads must come from a clean build.

**Not used, and deliberately so:** `SQLitePCLRaw.bundle_winsqlite3`, which would
bind the product to `winsqlite3.dll`. Microsoft treats that DLL as a Windows
component for Windows and Microsoft apps and updates it only through Windows
Update, so it is not a supported base for a third-party product database.

## 4. LibRaw — camera RAW decoder (`libraw.dll`)

Windows does not ship a camera RAW codec. The codecs Microsoft documents as built
into WIC are BMP, GIF, ICO, JPEG, JPEG XR, PNG, TIFF, HD Photo and DDS — RAW is
not among them. RAW support on Windows comes from **Raw Image Extension**, a
separate free Microsoft Store package that is not guaranteed to be present.
macOS has RAW decoding inside ImageIO, so without a decoder of our own the same
file opens on macOS and fails on Windows.

negaflow therefore redistributes LibRaw as `libraw.dll` and uses it whenever the
installed WIC codecs cannot open a file.

| Component | Version | License | Shipped payload |
|---|---|---|---|
| LibRaw | 0.22.2+df226ea | **LGPL-2.1** or **CDDL-1.0** (dual; we distribute under LGPL-2.1) | `libraw.dll` |
| Microsoft OpenMP runtime | 14.51.36231 (VC++ 2015-2022 redistributable) | Microsoft Visual C++ Redistributable licence (redistributable component) | `vcomp140.dll` |

- Upstream source: <https://github.com/LibRaw/LibRaw/archive/df226ea4178ccd74245f4f13c23adddfa01411c9.tar.gz>
- Upstream SHA-256: `06a37602a3f80b3e309e7ce704e6bb277c8298e162cde81e925a784ddf0fce21`
- **This is a pinned upstream commit, not a tagged release.** The newest tagged
  release, 0.22.2, lists ILCE-7M2/7M3/7M4 but not ILCE-7M5, so a real Sony A7 V
  file did not open at all. Upstream master carries that camera and libraw.org
  publishes no snapshot tarball, so the pin is the GitHub archive of commit
  `df226ea4178ccd74245f4f13c23adddfa01411c9` (2026-08-18). The archive was
  downloaded twice and produced the same SHA-256.
- Build recipe: [`scripts/build-libraw.ps1`](scripts/build-libraw.ps1). It pins the
  URL and hash above, builds with the `Makefile.msvc` that ships in the LibRaw
  source, and verifies that the fifteen C API entry points negaflow resolves are
  actually exported. No optional LibRaw dependency (RawSpeed, Adobe DNG SDK,
  LCMS, libjpeg) is enabled, so `libraw.dll` pulls in no further third-party code.
- **Built with `/openmp`.** LibRaw's demosaic carries 44 OpenMP regions and stock
  `Makefile.msvc` leaves them switched off, which left a Fuji X-Trans export at
  14.1 s where the same file takes 4.5 s with them on. The only added payload is
  Microsoft's own OpenMP runtime, `vcomp140.dll`, which the build script copies
  from the installed Visual C++ redistributable directory; the C runtime stays
  statically linked (`/MT`). `libraw.dll` will not load without it, so the two
  ship and install together.
- The source is **not modified**. We build stock LibRaw at that commit.

### Why this does not change the native engine's zero-dependency statement

`Negaflow.Native.dll` and `negaflow-cli.exe` still **link** no third-party code.
`libraw.dll` is resolved at run time with `LoadLibraryExW` and `GetProcAddress`;
it is not in the import table, and the product runs without it (RAW files then
fail with the same message any undecodable file gets). This is the same
arrangement as `e_sqlite3.dll` in section 3.

### LGPL-2.1 obligations a distribution must meet

`vcomp140.dll` is Microsoft's redistributable OpenMP runtime, shipped under the
Visual C++ Redistributable licence that permits redistribution with an
application. It is not LibRaw code and carries no LGPL obligation of its own.

1. Ship the licence text. `LICENSE.LGPL` and `LICENSE.CDDL` come from the LibRaw
   source archive; `scripts/build-libraw.ps1` copies both, plus `COPYRIGHT` and
   `Changelog.txt`, into its `redistributable\` staging directory.
2. Ship the complete corresponding source, or a written offer for it. The build
   script places the exact pinned `LibRaw-0.22.2+df226ea.tar.gz` in the same directory.
   Ship that archive; it is the source the shipped binary was built from.
3. Allow the user to relink. Satisfied by shipping LibRaw as a separate DLL the
   user can replace with their own build of the same C API.
4. State that LibRaw is used and is covered by the LGPL. This file does that.

**LibRaw is not linked into, and does not affect the licence of, any Apache-2.0
negaflow code.** The dual licence also offers CDDL-1.0; we take LGPL-2.1 because
dynamic linking under it is unambiguous and needs no per-file copyleft tracking.

## 5. Windows platform APIs

The following are used through the operating system and are **not** redistributed:
Windows SDK, Win32, Windows Imaging Component, Windows Color System / ICM, COM,
and Shell Lightweight Utility APIs.

## 6. Build-only tooling

`vcpkg` (MIT), `Microsoft.Windows.SDK.BuildTools`, and
`Microsoft.Windows.SDK.BuildTools.MSIX` are development tools. They are pinned
for reproducibility and are not part of any distributed payload, so they impose
no redistribution obligation.

---

## Deployment prerequisites

The current shell is framework-dependent and requires the .NET 10 runtime and the
Windows App Runtime 1.8 on the target machine. Installing or chaining those
runtimes is governed by their own Microsoft terms, which the installer must
surface to the user.

## Review status

This file closes the notice obligation for the dependency set pinned as of
2026-08-06. It does **not** by itself make the product release-ready: an SBOM
generated from the final installer payload, and a re-review of this file against
that payload, remain required. See `distribution_gate` in
[`third_party/manifest/components.json`](third_party/manifest/components.json).
