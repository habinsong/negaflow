# 선택형 이미지 SHA-256 구현

## 기본 동작

`hash_image_content(path)`의 기본 control은 `ImageContentHashMode::off`입니다. 이 경우 path가 존재하지
않아도 `disabled`를 반환하며 `CreateFileW`를 호출하지 않습니다. 일반 probe, decode와 scanner working
경로도 hash API를 호출하지 않습니다.

SHA-256은 호출자가 `mode=sha256`을 명시한 경우에만 실행됩니다. CLI에서는 별도
`--sha256-image <path>` command가 이 opt-in을 표현합니다.

## 책임 경계

- `image_content_hash.h`: 기본-off 정책, progress/cancel과 결과 계약
- `image_content_hash.cpp`: Win32 순차 file read와 Windows CNG adapter
- `commands/hash_image.cpp`: 경로를 출력하지 않는 개발 CLI
- `image_content_hash_tests.cpp`: 기본-off 무 I/O와 known-answer test

이 모듈은 catalog 설정 저장, 중복 후보 정책이나 archive manifest를 소유하지 않습니다.

## 활성 경로

1. `CreateFileW`로 read-only, share-deny-write, `FILE_FLAG_SEQUENTIAL_SCAN` handle을 엽니다.
2. regular disk file인지 확인하고 시작 file identity, 크기와 수정 시각을 기록합니다.
3. Windows 10 이상 CNG SHA-256 pseudo-handle로 hash object를 만듭니다.
4. 기본 8 MiB buffer로 순차 읽으며 `BCryptHashData`에 전달합니다.
5. 각 묶음 사이에서 stop token을 확인하고 byte progress를 보고합니다.
6. 종료 file 관측값이 시작과 다르면 digest를 publish하지 않습니다.
7. `BCryptFinishHash` 성공 뒤에만 32-byte digest를 결과에 공개합니다.

buffer는 64 KiB~64 MiB 범위만 허용합니다. 기본 8 MiB는 현재 코퍼스 진단값이며 향후 장치 matrix에서
다시 측정합니다. `FILE_FLAG_NO_BUFFERING`은 정렬·장치별 제약과 cache 이점을 잃을 수 있으므로 근거 없이
사용하지 않습니다.

## 실패 계약

- 기본 끔: `disabled`, I/O 0 bytes
- 이미 취소됨: `cancelled`, I/O 0 bytes
- 읽기 중 취소: 다음 chunk 경계에서 `cancelled`, digest 0
- read/CNG/file-info 실패: digest 0과 분류된 status
- 읽는 동안 file 관측값 변경: `file_changed`, digest publish 안 함
- JSON 오류: 사용자 경로와 파일명 없음

## 검증

- 존재하지 않는 경로에 기본 control을 적용해 `disabled`와 I/O 0 확인
- `abc`의 표준 SHA-256 known answer 확인
- 200,000-byte deterministic fixture를 64 KiB 여러 묶음으로 읽어 known answer 확인
- pre-cancelled token이 읽기 전에 `cancelled`를 반환함을 확인
- x64 Debug/Release native test와 CLI test 통과
- 사용자 TIFF 15개 opt-in 처리, 총 1,677,073,728 bytes, 원본 관측값 불변

ARM64는 build 검증 뒤 별도 장치에서 수치 실행해야 합니다.
