# Third-Party Notices for negaflow on Windows

negaflow itself is licensed under the Apache License 2.0. See the repository
[LICENSE](../LICENSE) and [NOTICE](../NOTICE).

This file records the third-party components that are, or may be, redistributed
with a negaflow Windows binary distribution, together with the notices those
components require. It is generated from the pinned dependency set declared in
[`third_party/manifest/components.json`](third_party/manifest/components.json)
and must be reviewed against the exact release payload before any distribution.

The native imaging engine embeds a GPU median-filter sorting network adapted
from Morgan McGuire and Kyle Whitson; its BSD-2-Clause notice is in section 7.
External DLL imports do not identify embedded third-party source. Two additional
third-party native binaries ship alongside the engine:

- `e_sqlite3.dll`, the managed catalog layer, as of 2026-08-07, section 3 below.
  See ADR-0025.
- `libraw.dll`, the camera RAW decoder, as of 2026-08-25, section 4 below. The
  engine resolves it at run time with `LoadLibraryExW`/`GetProcAddress` and runs
  without it. Windows ships no RAW codec of its own, so this is what keeps RAW
  import working on a machine that does not have Microsoft's Store extension.

---

## 1. Microsoft Windows App SDK (WinUI 3)

- Packages: `Microsoft.WindowsAppSDK.Runtime` 1.8.260710003,
  `Microsoft.WindowsAppSDK.WinUI` 1.8.260709004, and their pinned transitive
  packages `Microsoft.WindowsAppSDK.Base` 1.8.251216001,
  `Microsoft.WindowsAppSDK.Foundation` 1.8.260709000,
  `Microsoft.WindowsAppSDK.InteractiveExperiences` 1.8.260708001,
  `Microsoft.WindowsAppSDK.AI` 1.8.79,
  `Microsoft.WindowsAppSDK.DWrite` 1.8.25122902,
  `Microsoft.WindowsAppSDK.ML` 1.8.2197,
  `Microsoft.WindowsAppSDK.Widgets` 1.8.251231004.
- License: **MICROSOFT SOFTWARE LICENSE TERMS, MICROSOFT WINDOWS APP SDK**
  (proprietary; not an open-source license).
- Redistribution basis: Section 3(a)(i) of those terms states that files
  binplaced with the application by the Windows App SDK NuGet package are
  permitted to be redistributed, for both framework-dependent and self-contained
  deployment. The installer also chains the Microsoft-signed
  `WindowsAppRuntime.msix` (1.8) produced by the MSIX build under `Dependencies\`.
- Obligation: the full license terms must accompany the distribution. The
  canonical text ships inside each package as `license.txt`; `scripts/build-release.ps1`
  copies the license files from the restored NuGet package directories into
  `licenses\nuget\` in the installer payload so that the shipped text matches
  the shipped binaries.
- Reference: <https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI/1.8.260709004/License>

Note that these terms also carry data-collection provisions (Section 2). The
current shell does not enable Windows App SDK telemetry features, but this must
be re-checked before release.

## 2. Microsoft Edge WebView2, NOT redistributed

- Package: `Microsoft.Web.WebView2` 1.0.3179.45 (transitive, via WinUI).
- License: **BSD 3-Clause**.
- **Status: excluded from the distribution.** The shell contains no reference to
  WebView2 and renders no web content. The WinUI package graph used to binplace
  `Microsoft.Web.WebView2.Core.dll`,
  `Microsoft.Web.WebView2.Core.Projection.dll`, and `WebView2Loader.dll`
  (~1.6 MB) into the output; the `RemoveUnusedWebView2Payload` target in
  `src/Shell/Negaflow.Shell.csproj` now removes them from the copied output on
  both x64 and ARM64. See
  ADR-0022.
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

WebView2 also ships a `NOTICE.txt` listing components Microsoft
incorporated into it, including an offer to provide corresponding source for
components under copyleft terms. Dropping the payload also drops that chain. If
the payload is ever reintroduced, that `NOTICE.txt` must be reproduced alongside
this file, unmodified, from the pinned package directory. It is Microsoft's own
attribution document and must not drift from the version actually shipped.

## 3. SQLite catalog stack

The catalog store (`Negaflow.Catalog.Core`) uses SQLite through the managed
provider. The packages are referenced separately rather than through the
convenience `Microsoft.Data.Sqlite` package, so that the native SQLite version
can be raised on its own; see
ADR-0025 for why that
matters here.

| Package | Version | License | Shipped payload |
|---|---|---|---|
| `Microsoft.Data.Sqlite.Core` | 10.0.10 | MIT | `Microsoft.Data.Sqlite.dll` |
| `SQLitePCLRaw.config.e_sqlite3` | 3.0.5 | Apache-2.0 | `SQLitePCLRaw.batteries_v2.dll` |
| `SQLitePCLRaw.provider.e_sqlite3` | 3.0.5 | Apache-2.0 | `SQLitePCLRaw.provider.e_sqlite3.dll` |
| `SQLitePCLRaw.core` | 3.0.5 | Apache-2.0 | `SQLitePCLRaw.core.dll` |
| `SourceGear.sqlite3` | 3.53.4 | Public Domain | `runtimes\win-x64\native\e_sqlite3.dll`, `runtimes\win-arm64\native\e_sqlite3.dll` |
| `System.Numerics.Tensors` | 9.0.0 | MIT | `System.Numerics.Tensors.dll` (transitive) |
| `.NET Runtime (self-contained)` | 10.0 | MIT | `coreclr.dll`, `hostfxr.dll`, `System.*.dll` |

- **MIT** (`Microsoft.Data.Sqlite.Core`, `System.Numerics.Tensors`, and the
  self-contained `.NET 10` runtime): the licence text and copyright notice
  appear below and `scripts/build-release.ps1` also copies `LICENSE.txt` /
  `LICENSE.TXT` from the restored NuGet package directories into `licenses\nuget\`.

```
The MIT License (MIT)

Copyright (c) .NET Foundation and Contributors

All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- **Apache-2.0** (the three `SQLitePCLRaw.*` packages, Copyright 2014-2022
  SourceGear, LLC): section 4(a) requires a copy of the Apache License 2.0 with
  the distribution (provided in the root `LICENSE` and copied from the restored
  NuGet package directories into `licenses\nuget\`), and section 4(d) requires
  any `NOTICE` file carried by those packages to be reproduced.
- **Public Domain** (`SourceGear.sqlite3` and SQLite itself): dedicated to the
  public domain and imposes no redistribution obligation.

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

## 4. LibRaw, the camera RAW decoder (`libraw.dll`)

Windows does not ship a camera RAW codec. The codecs Microsoft documents as built
into WIC are BMP, GIF, ICO, JPEG, JPEG XR, PNG, TIFF, HD Photo and DDS. RAW is
not among them. RAW support on Windows comes from **Raw Image Extension**, a
separate free Microsoft Store package that is not guaranteed to be present.
macOS has RAW decoding inside ImageIO, so without a decoder of our own the same
file opens on macOS and fails on Windows.

negaflow therefore redistributes LibRaw as `libraw.dll` and uses it whenever the
installed WIC codecs cannot open a file. Negative RAW processing uses LibRaw
directly so inversion precedes the camera color matrix.

| Component | Version | License | Shipped payload |
|---|---|---|---|
| LibRaw | 0.22.2+df226ea | **LGPL-2.1** or **CDDL-1.0** (dual; we distribute under CDDL-1.0) | `libraw.dll` |
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
  source, and verifies that the required C API entry points negaflow resolves are
  actually exported. No optional LibRaw dependency (RawSpeed, Adobe DNG SDK,
  LCMS, libjpeg) is enabled. Upstream still includes BSD and MIT portions, whose
  notices are reproduced in `licenses/libraw/LibRaw-Third-Party-Notices.txt`.
- Built with `/openmp` and a static C runtime (`/MT`). Microsoft's OpenMP
  runtime, `vcomp140.dll`, is copied from the installed Visual C++ redistributable
  directory and shipped beside `libraw.dll`.
- Two LibRaw files are modified under CDDL-1.0. The patches in
  [`scripts/libraw/`](scripts/libraw/) keep X-Trans tiles in serial order while
  parallelizing rows inside each tile (`src/demosaic/xtrans_demosaic.cpp`) and
  parallelize the output bitmap copy (`src/postprocessing/mem_image.cpp`).
  On four tested RAW files, the patched DLL matches the unpatched serial build
  bit for bit. The former parallel X-Trans build differed from the serial result.
  On the Windows validation PC, the minimum of three decode runs changed from
  5.2 to 3.7 seconds for RAF and 1.81 to 1.50 seconds for ARW; NEF stayed at
  1.03 seconds. These are decoder timings, not whole-app export timings.

### Runtime loading of LibRaw

`libraw.dll` is resolved at run time with `LoadLibraryExW` and `GetProcAddress`;
it is not in the import table, and the product runs without it (RAW files then
fail with the same message any undecodable file gets). This is the same
arrangement as `e_sqlite3.dll` in section 3.

### LibRaw distribution under CDDL-1.0

`vcomp140.dll` is Microsoft's redistributable OpenMP runtime, shipped under the
Visual C++ Redistributable licence that permits redistribution with an
application. It is not LibRaw code and carries no LGPL obligation of its own.

This distribution selects CDDL-1.0 from upstream's dual licence. The library
includes the two patches above and remains a separate, replaceable DLL. Negaflow source files
retain their Apache-2.0 licence.

`scripts/build-libraw.ps1` stages the upstream `LICENSE.CDDL`, `LICENSE.LGPL`,
`COPYRIGHT`, `Changelog.txt`, the exact source archive, both patches, a modification notice and the build script.
`scripts/build-release.ps1` includes them in `licenses/libraw/`, together with
`LibRaw-Third-Party-Notices.txt` for upstream BSD and MIT portions. The LGPL
text is retained as the upstream alternative. It is not the selected licence
for this Windows distribution.

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

## 7. GPU median filter

The 3x3 median sorting network in `src/Native/gpu/shaders/median3.hlsl` is
adapted from Morgan McGuire and Kyle Whitson's implementation. The compute
shader is compiled into the native engine. The adapted portion is covered by
BSD-2-Clause. Negaflow changes the shader interface and texture sampling for
its Windows compute pipeline.

Source: [MedianFilter.shader in Morgan McGuire's repository](https://github.com/morgan3d/misc/blob/master/tachyon/Assets/Standard%20Assets/Effects/DepthOfField/Resources/MedianFilter.shader).

```text
3x3 Median
Morgan McGuire and Kyle Whitson
http://graphics.cs.williams.edu

Copyright (c) Morgan McGuire and Williams College, 2006
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## 8. NSIS installer

The Windows installer contains the NSIS installer stub and plug-ins under the
zlib/libpng license, and the LZMA compression module under CPL-1.0 with the
NSIS LZMA linking exception. That exception permits Negaflow's linked code to
retain its Apache-2.0 license.

The original `COPYING` from the NSIS installation used to compile the installer
is included as `licenses\nsis\COPYING`. It contains the copyright notices,
license terms, and LZMA linking exception without modification.

`licenses\nsis\SOURCE.txt` records the exact compiler version, source archive
name, SHA-256, and source download URLs. To obtain the source, open the
[Negaflow release](https://github.com/habinsong/negaflow/releases) matching the
installed application version and download the archive named in `SOURCE.txt`.
The version-specific upstream download URL is also recorded there.
`scripts/build-release.ps1` writes that original NSIS source archive and its
`.sha256` file beside the installer for publication with the same release.

Upstream license reference: <https://nsis.sourceforge.io/Docs/AppendixI.html>.

## 9. DNG technology (Adobe)

- Component: the DNG export writer (`src/Native/output/dng_linear_export.cpp`), written for negaflow
  from the DNG Specification 1.6 published by Adobe Inc. It contains no Adobe DNG SDK code.
- Terms: Adobe's DNG Specification patent license, a royalty-free grant for software that reads or
  writes DNG files, https://helpx.adobe.com/camera-raw/digital-negative.html.

This product includes DNG technology under license by Adobe.

---

## Deployment model

`scripts/build-release.ps1` builds the shell `--self-contained true` (bundling the
.NET 10 runtime libraries under the MIT license above) with
`WindowsAppSDKSelfContained=false`, and includes the Microsoft-signed
`WindowsAppRuntime.msix` (1.8) inside the NSIS installer so that
`package-registration.ps1` can register the framework dependency for the current
user before registering the application manifest.

## Review status

This file records the notices for the dependency set pinned in
[`third_party/manifest/components.json`](third_party/manifest/components.json),
and `scripts/build-release.ps1` stages the corresponding license and source
artifacts into `licenses\libraw\` and `licenses\nuget\` inside the installer
payload. NSIS license and source download information is installed under
`licenses\nsis\`; the NSIS source archive is a separate release asset.
