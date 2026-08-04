# 수동 네거티브 현상 수직 경로

## 목적

develop_manual_negative는 색상 관리가 끝난 WorkingImage와 사용자가 지정한 필름 베이스
투과율(Dmin)을 받아 고정 인화 응답으로 네거티브를 반전합니다. TIFF decode, ICC 변환, 사용자 설정
저장과 출력 encode를 한 객체에 섞지 않습니다.

현재 CLI 수직 경로는 다음 책임을 실제 데이터 흐름으로 연결합니다.

    read-only TIFF
      → bounded preflight + WIC 16-bit row decode
      → scanner ICC/linear policy
      → extended linear-sRGB RGBA float32
      → manual Dmin negative inversion
      → 구조화된 수치 보고

아직 파일을 출력하지 않으므로 완전한 M4 end-to-end 제품 경로는 아닙니다.

## 수동 경로 계약

- 입력 Dmin은 채널별 선형 투과율이며 [0.001, 1]로 제한합니다.
- color negative의 고정 명목 밀도 범위는 1.55입니다.
- B&W negative의 고정 명목 밀도 범위는 2.17입니다.
- 장면 histogram, percentile, auto levels나 auto white balance를 읽지 않습니다.
- 모든 parameter와 입력 pixel은 finite여야 합니다.
- alpha는 그대로 보존합니다.
- 결과 RGB는 float32이며 출력 단계 전까지 숨은 [0,1] clamp를 하지 않습니다.

채널별 density 좌표는 다음 순서로 계산합니다.

    boundedTransmission = max(transmission, 1e-5)
    density = log10(dmin / boundedTransmission) / dmaxNormalized
    output = fixedPrintResponse(density)

고정 인화 응답의 계수와 statement order는 macOS 기준선의
shoulder-print-response-v4와 기존 Windows scalar reference가 소유합니다. orchestration 계층은
이를 다시 구현하지 않고 parameter 선택과 소유권만 담당합니다.

## 메모리와 책임 분리

- manual_negative_developer: 필름 종류, Dmin 제한, scalar kernel 호출
- negative_inversion: 채널별 수학과 pixel validation
- scanner_tiff_to_working: TIFF row decode와 scanner→working 변환
- develop_negative_tiff: 개발 진단용 CLI 연결과 JSON
- working_image_report: CLI가 공유하는 min/max/fingerprint 계산

WorkingImage 소유권을 현상 단계에 넘겨 같은 pixel buffer를 제자리 변환합니다. 따라서 현상 단계가
추가로 소유하는 full-frame pixel buffer는 0바이트입니다. 실패하면 부분 결과를 공개하지 않고 pixel
storage를 폐기합니다.

## SHA-256 정책

이 경로는 이미지 content SHA-256 API를 호출하지 않습니다. CLI 결과의 source_sha256_mode도
off로 명시합니다. 보안 공급망, installer와 profile 무결성 hash 정책은 별도이며 변경하지 않습니다.

## 개발 CLI

    .\out\build\native\x64-debug\Debug\negaflow-cli.exe --develop-negative-tiff C:\path\scan.tiff 0.72 0.32 0.15 color

마지막 인자는 color 또는 bw입니다. 결과에는 사용자 경로나 pixel을 넣지 않고 적용된 Dmin,
고정 밀도 범위, working 크기, streaming temporary peak와 결과 fingerprint만 기록합니다.

## 검증

- wrapper 결과와 기존 scalar reference의 pixel별 exact 일치
- color 1.55, B&W 2.17 선택과 Dmin 제한
- 제자리 변환의 alpha 보존
- non-finite Dmin과 잘못된 image layout에서 결과 pixel 미공개
- 저장소 TIFF의 decode→color→develop CLI 성공과 JSON schema 검사
- 현재 x64 Debug/Release CTest 각각 23/23 통과
- ARM64 Debug/Release 전체 target cross-build

ARM64 수치는 실제 ARM64 Windows 장치에서 아직 실행하지 않았습니다.

## 남은 제품 경로

- 사용자 조작으로 얻은 film-base sample과 Dmin 설정 model
- auto film-base/scene-range 추정의 별도 검증
- output color transform, WIC encode, readback과 atomic publish
- cancellation/progress를 현상 pixel loop까지 전달하는 job API
- preview용 tile/GPU 경로와 CPU exact 비교
