#!/usr/bin/env bash
# Build the LibRaw revision used by Windows as a replaceable dylib, with OpenMP.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT=df226ea4178ccd74245f4f13c23adddfa01411c9
SOURCE_SHA=06a37602a3f80b3e309e7ce704e6bb277c8298e162cde81e925a784ddf0fce21
# LLVM's OpenMP runtime, linked statically and hidden inside libraw.dylib. macOS ships no OpenMP
# runtime; Windows uses Microsoft's vcomp140.dll for the same job. Without it LibRaw demosaics on
# one core (Fuji X-Trans 16.5 s, 24 MP Bayer 0.75 s on an M2; with it 1.7 s and 0.25 s).
LLVM_VERSION=20.1.8
OPENMP_SHA=b21c04ee9cbe56e200c5d83823765a443ee6389bbc3f64154c96e94016e6cee9
LLVM_CMAKE_SHA=3319203cfd1172bbac50f06fa68e318af84dcb5d65353310c0586354069d6634
# Patches in scripts/libraw, applied in name order. Each keeps the serial build's output bit for bit:
#   mem-image-parallel-rows: the final copy (with orientation) runs its rows in parallel.
#   raw-decoders-parallel: plain CR2 lossless JPEG and NEF scans go to the bridge's parallel Huffman
#     decoders, and Sony ARW2 rows decode in parallel. Anything else rewinds to LibRaw's own loop.
#   xtrans-parallel-rows: stock X-Trans parallelism races between tiles (output changed run to run);
#     tiles stay in serial order, the rows inside each tile run in parallel, and the green-bounds
#     pass runs in groups of rows that do not touch each other.
# These are the same files as negaflow-windows/scripts/libraw/.
PATCHES=("$ROOT"/scripts/libraw/*.patch)
PREVIEW_BRIDGE="$ROOT/scripts/libraw/native-preview-bridge.cpp"
ARCHITECTURES="${1:-$(uname -m)}"
OUTPUT="${2:-$ROOT/../build/libraw/$ARCHITECTURES}"
WORK="$ROOT/../build/libraw/source"
ARCHIVE="$WORK/LibRaw-$COMMIT.tar.gz"
SOURCE="$WORK/LibRaw-$COMMIT"
LLVM="$WORK/llvm-$LLVM_VERSION"
case "$ARCHITECTURES" in arm64|x86_64|universal) ;; *) echo 'unsupported architecture' >&2; exit 2 ;; esac
command -v cmake >/dev/null || { echo 'cmake is required to build the OpenMP runtime' >&2; exit 1; }
BUILD_ID="$SOURCE_SHA-native-v7-direct-preview-o3-thinlto-openmp-$LLVM_VERSION-$(cat "${PATCHES[@]}" "$PREVIEW_BRIDGE" | shasum -a 256 | cut -c1-16)"
mkdir -p "$WORK" "$OUTPUT/licenses"
fetch() { # url file sha
  if [ ! -f "$2" ]; then
    curl --fail --location --retry 2 "$1" -o "$2.part"
    mv "$2.part" "$2"
  fi
  [ "$(shasum -a 256 "$2" | cut -d ' ' -f1)" = "$3" ] || { echo "source hash mismatch: $2" >&2; exit 1; }
}
fetch "https://github.com/LibRaw/LibRaw/archive/$COMMIT.tar.gz" "$ARCHIVE" "$SOURCE_SHA"
LLVM_RELEASE="https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION"
fetch "$LLVM_RELEASE/openmp-$LLVM_VERSION.src.tar.xz" "$WORK/openmp-$LLVM_VERSION.src.tar.xz" "$OPENMP_SHA"
fetch "$LLVM_RELEASE/cmake-$LLVM_VERSION.src.tar.xz" "$WORK/cmake-$LLVM_VERSION.src.tar.xz" "$LLVM_CMAKE_SHA"
if [ ! -d "$SOURCE" ]; then tar -xzf "$ARCHIVE" -C "$WORK"; fi
if [ ! -d "$LLVM/openmp" ]; then
  # The standalone runtime build looks for LLVM's shared CMake modules in a sibling `cmake`.
  rm -rf "$LLVM"; mkdir -p "$LLVM"
  tar -xJf "$WORK/openmp-$LLVM_VERSION.src.tar.xz" -C "$LLVM"
  tar -xJf "$WORK/cmake-$LLVM_VERSION.src.tar.xz" -C "$LLVM"
  mv "$LLVM/cmake-$LLVM_VERSION.src" "$LLVM/cmake"
  mv "$LLVM/openmp-$LLVM_VERSION.src" "$LLVM/openmp"
fi
# Only upstream's default decoder set plus Apple's system zlib. No RawSpeed/DNG SDK/LCMS/JPEG dependency.
if [ ! -f "$OUTPUT/libraw.dylib" ] || [ "$(cat "$OUTPUT/build-id" 2>/dev/null || true)" != "$BUILD_ID" ]; then
  architectures="$ARCHITECTURES"
  if [ "$ARCHITECTURES" = universal ]; then architectures='arm64 x86_64'; fi
  for architecture in $architectures; do
    omp="$WORK/openmp-$LLVM_VERSION-dyn1-$architecture"
    # The archive ends up inside libraw.dylib, so it keeps the shared-library lifetime: a static
    # build shuts the runtime down when the last OpenMP thread exits, and LibRaw's critical-section
    # locks (static data) then point at freed memory on the next decode from a new GCD thread.
    if [ ! -f "$omp/lib/libomp.a" ]; then
      rm -rf "$omp" "$omp-build"
      cmake -S "$LLVM/openmp" -B "$omp-build" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$architecture" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DOPENMP_STANDALONE_BUILD=ON -DLIBOMP_ENABLE_SHARED=OFF -DOPENMP_ENABLE_LIBOMPTARGET=OFF \
        -DLIBOMP_OMPT_SUPPORT=OFF -DLIBOMP_OMPD_SUPPORT=OFF -DCMAKE_INSTALL_PREFIX="$omp"
      # The generated header ties KMP_DYNAMIC_LIB to LIBOMP_ENABLE_SHARED; set it after configuring.
      config="$omp-build/runtime/src/kmp_config.h"
      sed -i '' 's/^#define KMP_DYNAMIC_LIB LIBOMP_ENABLE_SHARED$/#define KMP_DYNAMIC_LIB 1/' "$config"
      grep -q '^#define KMP_DYNAMIC_LIB 1$' "$config" || { echo 'could not set KMP_DYNAMIC_LIB' >&2; exit 1; }
      cmake --build "$omp-build" -j "${NEGAFLOW_LIBRAW_JOBS:-4}"
      cmake --install "$omp-build"
    fi
    # A fresh tree every time: make compares timestamps to the second and can keep stale objects.
    build="$WORK/build-$architecture"
    rm -rf "$build"; mkdir -p "$build"; cp -R "$SOURCE/." "$build/"
    for patch_file in "${PATCHES[@]}"; do patch -d "$build" -p1 --forward --quiet < "$patch_file"; done
    mkdir -p "$build/object" "$build/lib"
    # libraw_types.h keeps OpenMP off for reentrant builds on Apple unless it is forced.
    make -C "$build" -f Makefile.dist -j "${NEGAFLOW_LIBRAW_JOBS:-4}" lib/libraw_r.a \
      CXX=clang++ "CFLAGS=-O3 -flto=thin -fPIC -I. -arch $architecture -mmacosx-version-min=14.0 -DUSE_ZLIB -DLIBRAW_FORCE_OPENMP -Xpreprocessor -fopenmp -I$omp/include"
    library="$OUTPUT/libraw-$architecture.dylib"
    clang++ -O3 -flto=thin -ffp-contract=off -fPIC -I"$build" -arch "$architecture" -mmacosx-version-min=14.0 \
      -Xpreprocessor -fopenmp -I"$omp/include" \
      -c "$PREVIEW_BRIDGE" -o "$build/object/native-preview-bridge.o"
    clang++ -O3 -flto=thin -dynamiclib -arch "$architecture" -mmacosx-version-min=14.0 \
      "-Wl,-force_load,$build/lib/libraw_r.a" "$build/object/native-preview-bridge.o" "-L$omp/lib" -Wl,-hidden-lomp -lz \
      -install_name @rpath/libraw.dylib -o "$library"
    # The runtime must be inside the library and invisible from outside it. Outputs are captured
    # first: under pipefail an early `grep -q` exit fails the producer with SIGPIPE.
    linked="$(otool -L "$library")"; symbols="$(nm -arch "$architecture" "$library")"
    exported="$(nm -gU -arch "$architecture" "$library")"
    if grep -q libomp <<<"$linked"; then echo 'libraw.dylib links a separate libomp' >&2; exit 1; fi
    grep -q ' t ___kmpc_fork_call$' <<<"$symbols" || { echo 'libraw.dylib was built without OpenMP' >&2; exit 1; }
    if grep -q -E '___kmpc_|_omp_get_' <<<"$exported"; then
      echo 'libraw.dylib exports OpenMP runtime symbols' >&2; exit 1
    fi
  done
  if [ "$ARCHITECTURES" = universal ]; then
    lipo -create "$OUTPUT/libraw-arm64.dylib" "$OUTPUT/libraw-x86_64.dylib" -output "$OUTPUT/libraw.dylib"
  else cp "$OUTPUT/libraw-$ARCHITECTURES.dylib" "$OUTPUT/libraw.dylib"; fi
  printf '%s\n' "$BUILD_ID" > "$OUTPUT/build-id"
fi
for name in LICENSE.LGPL LICENSE.CDDL COPYRIGHT Changelog.txt; do cp "$SOURCE/$name" "$OUTPUT/licenses/$name"; done
cp "$ARCHIVE" "$OUTPUT/licenses/"
cp "$ROOT/scripts/build-libraw.sh" "${PATCHES[@]}" "$PREVIEW_BRIDGE" "$OUTPUT/licenses/"
cp "$LLVM/openmp/LICENSE.TXT" "$OUTPUT/licenses/LLVM-OpenMP-LICENSE.TXT"
if [ -f "$ROOT/Config/LibRaw-Third-Party-Notices.txt" ]; then
  cp "$ROOT/Config/LibRaw-Third-Party-Notices.txt" "$OUTPUT/licenses/"
else
  echo '[libraw] warning: supplemental notice file is missing; upstream source and licence files are retained.' >&2
fi
cat > "$OUTPUT/licenses/README.txt" <<EOF
LibRaw upstream: https://github.com/LibRaw/LibRaw/tree/$COMMIT
This macOS distribution selects CDDL-1.0 from upstream dual licensing.
See LICENSE.CDDL, COPYRIGHT,
and LibRaw-Third-Party-Notices.txt for the library and included BSD/MIT components.
LICENSE.LGPL is retained as the upstream alternative; it is not the selected macOS distribution licence.
Source SHA-256: $SOURCE_SHA

Modified files (patches included here, CDDL-1.0 like the files they change):
- src/demosaic/xtrans_demosaic.cpp (xtrans-parallel-rows.patch). Upstream runs
  the Fuji X-Trans tiles in parallel while each tile reads pixels its
  neighbours write, so the output changed from run to run. The patch keeps the
  tiles in serial order, reuses one worker team for the rows of each tile, and
  gathers two per-pixel loops a row at a time.
- src/postprocessing/mem_image.cpp (mem-image-parallel-rows.patch). The final
  copy into the output bitmap runs its rows in parallel.
- src/decoders/decoders_dcraw.cpp (raw-decoders-parallel.patch). Plain lossless
  JPEG (CR2) and Nikon NEF scans are handed to the bridge's parallel Huffman
  decoders, and Sony ARW2 rows are decoded in parallel after the frame is read
  at once. Other files, or any sign of damage, rewind and run LibRaw's own loop.
The X-Trans patch also runs the green-bounds pass in groups of rows that do not
touch each other. All three keep the output equal to the unpatched serial build
bit for bit (on this Mac: 41 RAW files - CR2, CR3, NEF, ARW, RAF, ORF, RW2,
PEF, DNG - gave the same pixel hashes). No other LibRaw file is changed.
native-preview-bridge.cpp is Negaflow's CDDL-1.0 source for selecting a provisional
preview from reported mosaic data, forwarding cancellation, and reducing linear
camera RGB directly from the processed sensor buffer. Its area weights and float
accumulation order match RGB16AreaReduce.swift; no full-resolution output copy is
allocated for previews. negaflow_libraw_init() creates a LibRaw subclass that runs
three per-pixel loops (scale_colors_loop, convert_to_rgb_loop,
lin_interpolate_loop) on every core with byte-identical output. The bridge also
holds the parallel Huffman decoders the decoder patch calls; they follow S. T.
Klein and Y. Wiseman, "Parallel Huffman decoding with applications to JPEG
files" (The Computer Journal, 2003), and are an independent implementation. It
uses the upstream public headers. Settled previews and exports keep the default
quality.

OpenMP runtime: LLVM $LLVM_VERSION libomp, built from
$LLVM_RELEASE/openmp-$LLVM_VERSION.src.tar.xz
(SHA-256 $OPENMP_SHA) and linked statically into libraw.dylib with its symbols
hidden. Licence: Apache License v2.0 with LLVM Exceptions, LLVM-OpenMP-LICENSE.TXT.

The separate libraw.dylib can be replaced by a compatible C-ABI build.
The archive, the patches and the exact Negaflow build script are included here.
The script runs from a Negaflow source checkout; alternatively extract the
archive, apply the patches with patch -p1, and build with upstream Makefile.dist
(lib/libraw_r.a), compile the supplied bridge, then link with:
  clang++ -O3 -flto=thin -ffp-contract=off -fPIC -I. -Xpreprocessor -fopenmp -I<libomp>/include -c native-preview-bridge.cpp -o native-preview-bridge.o
  clang++ -O3 -flto=thin -dynamiclib -Wl,-force_load,lib/libraw_r.a native-preview-bridge.o -L<libomp>/lib -Wl,-hidden-lomp -lz -install_name @rpath/libraw.dylib -o libraw.dylib
Compilation uses -O3 -flto=thin -fPIC -I. -mmacosx-version-min=14.0 -DUSE_ZLIB
-DLIBRAW_FORCE_OPENMP -Xpreprocessor -fopenmp -I<libomp>/include and the
matching -arch arm64 or -arch x86_64. A build without the OpenMP flags and
without libomp is serial and gives the same pixels. No optional RawSpeed or DNG
SDK is linked.

For a replacement library in your own copy of negaflow.app, re-sign the library
and then the app with your own signature (ad-hoc signing is supported):
  codesign --force --sign - negaflow.app/Contents/Frameworks/libraw.dylib
  codesign --force --options runtime --preserve-metadata=entitlements --sign - negaflow.app
Keep the app's entitlements (disable-library-validation): without them macOS refuses
to load a library signed by a different identity.
Keep your own source/build records when distributing a modified library.
EOF
echo "[libraw] $OUTPUT/libraw.dylib"
