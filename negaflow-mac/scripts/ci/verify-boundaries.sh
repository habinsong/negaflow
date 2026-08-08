#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if find Sources Tests -iname '*sane*' -print -quit | grep -q .; then
  echo "[ci-boundary] ERROR: SANE 이름의 구현/테스트 파일은 negaflow-scanner-sane 저장소에만 허용됩니다." >&2
  exit 1
fi

if git grep -n -E \
    'SANE_CONFIG_DIR|scanimage|libsane|sane-backends|sane/sane\.h' \
    -- \
    Sources Tests scripts Package.swift \
    ':(exclude)scripts/ci/verify-boundaries.sh' \
    ':(exclude)scripts/ci/verify-provenance.py'; then
  echo "[ci-boundary] ERROR: 메인 저장소에 SANE 전용 구현 또는 런타임 처리가 있습니다." >&2
  exit 1
fi

echo "[ci-boundary] external scanner host is implementation-neutral"
