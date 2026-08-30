#!/usr/bin/env bash
# 릴리스 폴더에 있는 파일 전부를 체크섬 한 장에 다시 적는다.
#
# 아키텍처마다 체크섬을 따로 두면 릴리스 페이지에 같은 성격의 파일이 여러 개 걸린다.
# dSYM 은 릴리스에 올리지 않으므로 목록에서 뺀다.
# 이 스크립트는 지금 폴더에 있는 것만 보고 매번 새로 적으므로, 아키텍처를 하나 더
# 만든 뒤에 다시 불러도 되고 공증으로 파일이 바뀐 뒤에 다시 불러도 된다.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <release-artifacts-dir> <version>" >&2
  exit 2
fi

OUTPUT_DIR="$1"
VERSION="$2"
CHECKSUM_NAME="negaflow-$VERSION-mac.sha256"

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "[release-checksums] ERROR: 릴리스 폴더가 없습니다: $OUTPUT_DIR" >&2
  exit 1
fi

cd "$OUTPUT_DIR"
FILES=()
for name in *; do
  [ -f "$name" ] || continue
  case "$name" in
    *.sha256|*.sha256.txt|*.dSYM.zip) continue ;;
  esac
  FILES+=("$name")
done

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[release-checksums] ERROR: 체크섬을 적을 파일이 없습니다: $OUTPUT_DIR" >&2
  exit 1
fi

shasum -a 256 "${FILES[@]}" > "$CHECKSUM_NAME"
shasum -a 256 -c "$CHECKSUM_NAME" >/dev/null
echo "[release-checksums] checksums: $OUTPUT_DIR/$CHECKSUM_NAME"
