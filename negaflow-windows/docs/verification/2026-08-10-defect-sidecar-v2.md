# Defects sidecar v2 검증

날짜: 2026-08-10

기준: macOS `2fa1d6297378673b58b8bec72025e968ccc3125c`의 Defects v2 sidecar·recipe 계약

## 구현 경계

- frame ID, 양의 recipe revision, recipe SHA-256, 선택적 source identity와 ordered
  brush/region/infrared/clone item을 Windows canonical JSON sidecar로 저장
- raw mask를 bounded zlib로 압축하고 sidecar 크기·item/stroke/point/cluster/mask pixel·decoded recipe
  상한을 encode/decode 양쪽에서 검증
- 같은 revision의 다른 내용 충돌, 낮은 revision의 늦은 완료, 미래 version과 잘못된 fingerprint를 차단
- temp→flush→atomic replace 뒤 readback을 검증하고 게시 실패 시 이전 파일을 복원
- `hasDefectEdits` catalog 선언과 sidecar를 library open에서 교차 검증해 누락·손상을 fail-closed
- logical backup v3 manifest에 catalog와 모든 authoritative sidecar의 byte count·SHA-256을 포함하고,
  pending restore에서 defects 디렉터리와 catalog를 같은 generation으로 교체
- 재시작한 `LibraryDocument`가 sidecar를 보존하고, 선택된 region/infrared mask만 bounded decode해 기존
  ABI v18 request로 투영. enabled brush/clone은 조용히 무시하지 않고 request 생성을 거부

Windows 저장 bytes는 제품 내부 구현이며 macOS binary plist bytes를 복제하지 않습니다. 사용자에게 보이는
recipe 순서·revision/source binding·실패 의미와 preview/export 공통 수학을 기준으로 맞췄습니다.

## 실행한 검증

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-release
```

## 결과

- x64 Debug 관리 build 경고 0·오류 0, Catalog `583`, Shell `313` assertions 통과
- x64 Release 관리 build 경고 0·오류 0, Catalog `583`, Shell `313` assertions 통과
- ARM64 Release 관리 전체 graph 교차 빌드 경고 0·오류 0
- 같은 날 고정된 ABI v18 경로의 x64 Debug/Release Interop `103 assertions`, native CTest `44/44` 결과는
  `2026-08-10-defect-region-pipeline-v18.md`에 별도로 기록

ARM64 결과는 교차 빌드 증거이며 실제 ARM64 Windows runtime 검증은 아닙니다. Windows 호스트에서는
macOS Core Image 실행이나 동일 입력 pixel golden을 생성하지 않았습니다.

## 고정한 실패·재시작 경계

- all 4 edit kinds와 item 순서의 저장·재로드, region mask exact decode
- 같은 revision의 idempotent write/source bind와 다른 내용 충돌, newer write, stale completion skip
- future version 보존, invalid zlib의 게시 전 거부, sidecar 없는 defect catalog 선언의 공개 write 차단
- missing/corrupt sidecar의 library open 차단과 실제 `LibraryDocument` 재시작 후 region request 재적용
- backup sidecar copy/hash/decode, hash 손상 세대 거부, 선택 세대 sidecar restore와 safety generation 보존
- unsupported enabled brush가 무시되지 않고 `UnsupportedDefectEditKind`로 request 생성 실패

## 남은 검증

- 저장된 source identity와 실제 source bytes의 렌더 직전 비교 및 source 교체 race
- brush/clone의 native payload·복원 수학과 WinUI 편집/undo 흐름
- process-kill/disk-full/power-loss가 directory swap·catalog commit 사이에 발생한 경우의 자동 복구
- 실제 촬영 TIFF의 macOS/Windows 동일 입력 mask·pixel golden
- JSON base64 overhead를 포함한 병리적 고엔트로피 대형 mask의 실효 파일 용량
- 실제 ARM64 Windows 장치 실행
