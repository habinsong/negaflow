# ADR-0018: Film Emulation acutance는 11행 bounded spatial kernel로 격리한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

macOS의 필름 스캔 후처리는 RGB33 색상 cube 뒤에 `CIUnsharpMask`를 적용합니다. Apple 공식 문서는
radius와 intensity의 의미는 설명하지만 실제 blur kernel, support, border 처리와 수치 정밀도는 공개하지
않습니다. 이를 추측해 제품 파이프라인에 바로 연결하면 색상 차이와 spatial 차이, source routing 오류를
분리하기 어렵고 큰 이미지에서 불필요한 full-frame 임시 버퍼가 생길 수 있습니다.

## 결정

1. 같은 Apache-2.0 저장소의 고정 Film Emulation profile radius·acutance 값과, 기준 macOS에서 생성한
   `film-emulation-core-image-v1` impulse/step 관측값만 사용해 C++20 reference를 독립 작성합니다.
2. algorithm ID는 `chromabase-film-emulation-acutance-v1`입니다. 색상 cube와 별도 component로 두며
   profile 데이터, spatial 수학과 test orchestration을 각각 분리합니다.
3. 실제 sharpening amount는 `profileIntensity × clamp(userIntensity, 0, 1)`입니다. 색상 cube의 5%
   양자화와 달리 acutance의 사용자 강도는 양자화하지 않습니다. `none` 또는 효과 임계값 이하는
   bit-exact identity입니다.
4. unsharp 식은 `source + amount × (source - blur)`로 고정합니다. radius 1.0/1.1/1.2의 macOS golden에
   맞춘 separable Gaussian sigma는 각각 1.042/1.137/1.238이며, 각 축 support는 5픽셀입니다. 이 값은
   Core Image 내부 구현에 대한 주장이 아니라 현재 기준 OS의 관측 응답을 근사하는 호환 계수입니다.
5. horizontal RGB blur 11행만 caller-owned ring에 저장합니다. scratch 크기는
   `width × 11 × 12`바이트이며 full-frame 임시 이미지와 내부 heap allocation은 없습니다.
6. 입력과 출력은 extended-linear sRGB입니다. RGB overshoot는 허용하고 alpha는 bit-exact로 보존합니다.
   동일 base·stride의 exact in-place 처리를 지원하며, 그 외 부분 alias와 scratch/image 중첩은 거부합니다.
7. 좌우·상하 경계는 가장 가까운 유효 좌표로 clamp합니다. interior horizontal loop는 tap마다 좌표 clamp를
   하지 않고, 행 ring은 처리 완료된 행의 slot만 재사용합니다.
8. unknown profile, 비유한 intensity·pixel·output, 잘못된 view, 작은/null scratch와 금지된 메모리 중첩을
   처리 전에 거부합니다.
9. 이번 결정은 standalone native contract와 conformance까지만 포함합니다. 색상 cube와의 production
   orchestration, digital/film source routing, CLI, C ABI, recipe persistence와 WinUI 연결은 다음 단계입니다.
10. 일반 이미지 SHA-256 기본값은 계속 `끔`입니다. golden JSON과 CI artifact의 공급망 식별용 digest는
    사용자 이미지 content hash 옵션과 별개입니다.

## 결과

10,000픽셀 너비에서도 scratch는 1,320,000바이트로 고정되고 높이에 따라 증가하지 않습니다. macOS
Core Image 기준 6개 impulse/step signature의 최대 절대 오차는 현재 x64에서 약 `1.54e-4`입니다. 색상
cube와 spatial kernel이 분리되어 향후 source routing, SIMD와 DirectCompute/WARP를 각각 검증할 수 있습니다.

## 검증 한계

- sigma는 macOS 26.5.2의 고정 fixture에 맞춘 계수이며 Apple의 비공개 kernel을 식별했다는 뜻이 아닙니다.
- 현재 fixture는 opaque 33×9 합성 패턴입니다. 더 큰 영상, fractional alpha와 실제 ARM64 실행은 별도
  검증이 필요합니다.
- standalone 통과는 전체 `FilmEmulationStage`나 제품 source routing 완료를 의미하지 않습니다.
- 제한적 특허 검색은 법률 자문이나 freedom-to-operate 보증이 아닙니다.

## 근거

- [Apple CIUnsharpMask](https://developer.apple.com/documentation/coreimage/ciunsharpmask)
- [Apple CIUnsharpMask radius](https://developer.apple.com/documentation/coreimage/ciunsharpmask/radius)
- [Apple CIUnsharpMask intensity](https://developer.apple.com/documentation/coreimage/ciunsharpmask/3228820-intensity)

실행 증거와 권리 검토는 각각 `verification/2026-08-04-film-emulation-core-image-golden.md`와
`research/film-emulation-acutance-sources.md`에 기록합니다.
