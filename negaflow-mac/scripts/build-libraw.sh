#!/usr/bin/env bash
# Build the same unmodified LibRaw revision used by Windows as a replaceable dylib.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT=df226ea4178ccd74245f4f13c23adddfa01411c9
SOURCE_SHA=06a37602a3f80b3e309e7ce704e6bb277c8298e162cde81e925a784ddf0fce21
ARCHITECTURES="${1:-$(uname -m)}"
OUTPUT="${2:-$ROOT/../build/libraw/$ARCHITECTURES}"
WORK="$ROOT/../build/libraw/source"
ARCHIVE="$WORK/LibRaw-$COMMIT.tar.gz"
SOURCE="$WORK/LibRaw-$COMMIT"
case "$ARCHITECTURES" in arm64|x86_64|universal) ;; *) echo 'unsupported architecture' >&2; exit 2 ;; esac
mkdir -p "$WORK" "$OUTPUT/licenses"
if [ ! -f "$ARCHIVE" ]; then
  curl --fail --location --retry 2 "https://github.com/LibRaw/LibRaw/archive/$COMMIT.tar.gz" -o "$ARCHIVE.part"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
[ "$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f1)" = "$SOURCE_SHA" ] || { echo 'LibRaw source hash mismatch' >&2; exit 1; }
if [ ! -d "$SOURCE" ]; then tar -xzf "$ARCHIVE" -C "$WORK"; fi
# Only upstream's default decoder set plus Apple's system zlib. No RawSpeed/DNG SDK/LCMS/JPEG dependency.
if [ ! -f "$OUTPUT/libraw.dylib" ] || [ "$(cat "$OUTPUT/build-id" 2>/dev/null || true)" != "$SOURCE_SHA-native-v1" ]; then
  architectures="$ARCHITECTURES"
  if [ "$ARCHITECTURES" = universal ]; then architectures='arm64 x86_64'; fi
  for architecture in $architectures; do
    build="$WORK/build-$architecture"
    if [ ! -d "$build" ]; then mkdir -p "$build"; cp -R "$SOURCE/." "$build/"; fi
    mkdir -p "$build/object" "$build/lib"
    make -C "$build" -f Makefile.dist -j "${NEGAFLOW_LIBRAW_JOBS:-4}" lib/libraw_r.a \
      CXX=clang++ "CFLAGS=-O2 -fPIC -I. -arch $architecture -mmacosx-version-min=14.0 -DUSE_ZLIB"
    clang++ -dynamiclib -arch "$architecture" -mmacosx-version-min=14.0 \
      "-Wl,-force_load,$build/lib/libraw_r.a" -lz -install_name @rpath/libraw.dylib \
      -o "$OUTPUT/libraw-$architecture.dylib"
  done
  if [ "$ARCHITECTURES" = universal ]; then
    lipo -create "$OUTPUT/libraw-arm64.dylib" "$OUTPUT/libraw-x86_64.dylib" -output "$OUTPUT/libraw.dylib"
  else cp "$OUTPUT/libraw-$ARCHITECTURES.dylib" "$OUTPUT/libraw.dylib"; fi
  printf '%s\n' "$SOURCE_SHA-native-v1" > "$OUTPUT/build-id"
fi
for name in LICENSE.LGPL LICENSE.CDDL COPYRIGHT Changelog.txt; do cp "$SOURCE/$name" "$OUTPUT/licenses/$name"; done
cp "$ARCHIVE" "$OUTPUT/licenses/"
cp "$ROOT/scripts/build-libraw.sh" "$OUTPUT/licenses/"
if [ -f "$ROOT/Config/LibRaw-Third-Party-Notices.txt" ]; then
  cp "$ROOT/Config/LibRaw-Third-Party-Notices.txt" "$OUTPUT/licenses/"
else
  echo '[libraw] warning: supplemental notice file is missing; upstream source and licence files are retained.' >&2
fi
cat > "$OUTPUT/licenses/README.txt" <<EOF
LibRaw upstream: https://github.com/LibRaw/LibRaw/tree/$COMMIT
Unmodified source; this macOS distribution selects CDDL-1.0 from upstream dual licensing.
See LICENSE.CDDL, COPYRIGHT,
and LibRaw-Third-Party-Notices.txt for the library and included BSD/MIT components.
LICENSE.LGPL is retained as the upstream alternative; it is not the selected macOS distribution licence.
Source SHA-256: $SOURCE_SHA

The separate libraw.dylib can be replaced by a compatible C-ABI build.
The archive and the exact Negaflow build script are included here.
The script runs from a Negaflow source checkout; alternatively extract the
archive and build with upstream Makefile.dist (lib/libraw_r.a), then link with:
  clang++ -dynamiclib -Wl,-force_load,lib/libraw_r.a -lz -install_name @rpath/libraw.dylib -o libraw.dylib
Compilation uses -O2 -fPIC -I. -mmacosx-version-min=14.0 -DUSE_ZLIB and the
matching -arch arm64 or -arch x86_64. No optional RawSpeed or DNG SDK is linked.

For a replacement library in your own copy of negaflow.app, re-sign the library
and then the app with your own signature (ad-hoc signing is supported):
  codesign --force --sign - negaflow.app/Contents/Frameworks/libraw.dylib
  codesign --force --options runtime --preserve-metadata=entitlements --sign - negaflow.app
Keep the app's entitlements (disable-library-validation): without them macOS refuses
to load a library signed by a different identity.
Keep your own source/build records when distributing a modified library.
EOF
echo "[libraw] $OUTPUT/libraw.dylib"
