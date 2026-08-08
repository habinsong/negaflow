# ADR-0005: 이미지 content SHA-256은 기본 끔

- 상태: 채택
- 날짜: 2026-08-04

## 배경

로컬 이미지의 full-file SHA-256은 파일 전체를 한 번 더 읽어야 합니다. 일반적인 가져오기, 탐색,
현상과 로컬 내보내기에서 이 비용에 비해 얻는 이점은 작습니다. 파일 크기, 수정 시각, volume/file ID와
같은 로컬 identity만으로도 일상적인 변경 감지와 재연결 후보 검색에 충분한 경우가 많습니다.

SHA-256은 byte-identical 중복 확인, 장기 보관 검증이나 외부 전달 manifest처럼 사용자가 명시적으로
무결성 증거를 원하는 작업에는 여전히 유용합니다. 따라서 기능을 제거하지 않고 기본 경로에서 분리합니다.

## 결정

1. 일반 이미지의 content SHA-256 설정 기본값은 `끔`입니다.
2. 기본 control은 경로 유효성 검사보다 먼저 `disabled`를 반환하므로 파일을 열거나 읽지 않습니다.
3. 가져오기, Library 탐색, preview, 현상과 일반 로컬 export는 이 설정을 묵시적으로 켜지 않습니다.
4. 사용자가 설정을 켜거나 중복·보관 검증처럼 hash가 작업의 본질인 command를 명시적으로 시작한 경우에만
   full-file SHA-256을 계산합니다.
5. 플러그인/실행 파일 신뢰, 업데이트, installer, bundled resource, ICC/profile identity와 release artifact
   검증은 이 이미지 설정의 적용 대상이 아닙니다. 보안·공급망 hash는 계속 필수입니다.
6. hash를 켰을 때도 UI thread에서 계산하지 않으며 progress와 cancellation을 제공합니다.

이 결정은 `windows_docs/08-ui/surfaces/export.md`의 일반 이미지 source/output full-hash 제안을 Windows 제품
기본값에 한해 대체합니다. hash가 꺼졌을 때 render manifest의 이미지 digest는 optional/absent로 기록하고,
묵시적으로 파일을 다시 읽어 채우지 않습니다. relink와 중복 찾기는 volume/file ID, 크기와 수정 관측값으로
후보를 좁힌 뒤 사용자의 확인을 요구합니다. cryptographic identity가 꼭 필요한 기능은 `알 수 없음` 상태를
표시하거나 해당 작업에서 opt-in을 요청하며, 전역 설정을 몰래 바꾸지 않습니다.

## Windows 구현

`ImageContentHashControl`의 기본 `mode`는 `off`입니다. 명시적 SHA-256 경로는 다음 계약을 사용합니다.

- Windows CNG의 `BCRYPT_SHA256_ALG_HANDLE`
- `FILE_FLAG_SEQUENTIAL_SCAN`을 지정한 share-deny-write read handle
- 기본 8 MiB 순차 buffer와 chunk 사이 cooperative cancellation
- byte 진행률
- 시작/종료 file identity·크기·수정 시각 비교
- 경로나 파일명 없는 구조화된 실패 결과

`negaflow-cli --sha256-image <path>`는 개발과 명시적 opt-in 검증용입니다. 다른 TIFF command는 이
함수를 호출하지 않습니다.

## UI/UX 계약

Settings의 Library/파일 관리 영역에 다음 toggle을 둡니다.

- 이름: `이미지 SHA-256 계산`
- 기본 상태: `끔`
- 설명: `파일 전체를 읽어 가져오기와 내보내기가 느려질 수 있습니다. 로컬 작업에는 보통 필요하지 않습니다.`

켜진 작업에는 처리 중인 파일 수와 byte progress, 취소를 표시합니다. 설정을 켠 것만으로 기존 Library
전체를 즉시 다시 읽지 않으며 이후 요청부터 적용합니다.

## 성능 증거와 다음 최적화

x64 Release 진단에서 사용자 TIFF 15개, 총 1,677,073,728 bytes를 명시적 opt-in으로 처리했습니다.
파일별 hash 구간은 약 1,307~1,362 MiB/s였고, 파일마다 별도
CLI process를 시작한 전체 집계는 약 1,096 MiB/s였습니다. 원본 크기·수정 시각·속성은 유지됐습니다.
이는 warm cache와 저장장치 상태를 통제하지 않은 진단값이며 제품 성능 보장이 아닙니다.

후속 Library/export 구현에서는 다음 순서로 최적화합니다.

1. 이미 copy/staging하는 byte stream이 있으면 같은 pass에서 hash해 두 번째 전체 읽기를 피합니다.
2. 확인된 volume/file ID, byte count와 수정 관측값이 그대로인 opt-in 결과만 cache합니다.
3. 여러 파일은 volume별 bounded concurrency를 실제 HDD/SATA SSD/NVMe 측정 뒤 정합니다.
4. 순차 CNG 경로가 storage throughput을 제한한다는 증거가 있을 때만 overlapped double buffering을
   추가합니다.

## 공식 근거

- [BCryptCreateHash](https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptcreatehash)
- [CNG로 hash 만들기](https://learn.microsoft.com/en-us/windows/win32/seccng/creating-a-hash-with-cng)
- [CreateFile의 FILE_FLAG_SEQUENTIAL_SCAN](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)
- [FILE_ID_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_id_info)

Windows 기본 API만 사용하므로 새 제3자 코드, 라이선스나 특허 payload는 추가되지 않습니다.
