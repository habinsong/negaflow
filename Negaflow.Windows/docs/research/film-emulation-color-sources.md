# Film Emulation 색상 cube 공식 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

Windows 명부, profile 값, intensity 양자화와 node 연산 순서는 같은 Apache-2.0 저장소의 다음 source를
기준으로 C++20으로 독립 이식했습니다.

- `Sources/Chromabase/Adjustments/FilmEmulation.swift`
- `Sources/Chromabase/Adjustments/FilmEmulationProfile.swift`
- `Sources/Chromabase/Adjustments/FilmEmulationProfile+Slide.swift`
- `Sources/Chromabase/Adjustments/FilmEmulationProfile+Negative.swift`
- `Sources/Chromabase/Engine/ChromabaseEngine+PostPipeline.swift`
- `Sources/negaflowApp/Features/Develop/Inspector/DevelopAdjustmentSections.swift`

외부 LUT, 필름 스캔, ICC profile, 제조사 특성 곡선, shader, reference implementation이나 test image를
복사하지 않았습니다. 4×3 fixture와 11개 profile signature는 저장소 소유 수치를 별도 JavaScript
Float32 계산으로 만들었습니다.

## Apple 공식 기술 근거

- [CIColorCubeWithColorSpace](https://developer.apple.com/documentation/coreimage/cicolorcubewithcolorspace):
  cube data가 premultiplied RGBA floating-point이며 dimension과 color space를 갖는 공식 필터 계약을
  확인했습니다. 현재 Windows table은 opaque RGB node만 저장하고 source straight alpha를 보존합니다.
- [colorCubeWithColorSpace filter](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/colorcubewithcolorspace%28%29?language=objc):
  입력 RGB를 cube로 mapping하며 red가 column, green이 row, blue가 plane인 배열 순서를 확인했습니다.
- [CIContext](https://developer.apple.com/documentation/coreimage/cicontext): Core Image context가 input,
  working과 output color matching을 관리한다는 점을 확인했습니다. Windows reference는 이 숨은 경계를
  추측하지 않고 제품 source가 지정한 sRGB cube domain을 명시적으로 왕복합니다.
- [CIContext useSoftwareRenderer](https://developer.apple.com/documentation/coreimage/cicontextoption/usesoftwarerenderer):
  software renderer 요청 option과 미지원 플랫폼에서는 효과가 없을 수 있다는 제한을 확인했습니다.
  baseline은 실제 backend라고 단정하지 않고 default/software-requested 두 결과를 함께 기록합니다.
- [CIUnsharpMask](https://developer.apple.com/documentation/coreimage/ciunsharpmask): radius와 intensity
  parameter가 있다는 사실만 확인됩니다. Windows와 같은 numeric kernel·경계 처리는 문서로 확정할 수
  없어 이번 색상 component에서 제외했습니다.

Apple 문서나 sample code를 복사하지 않았습니다. 실제 Core Image 보간과 fractional-alpha 동작은
macOS golden으로 별도 검증해야 합니다.

## baseline workflow 근거

- [GitHub 수동 workflow 실행](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow?tool=cli):
  `workflow_dispatch` workflow를 선택한 branch에서 수동 실행할 수 있음을 확인했습니다.
- [GitHub workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts):
  실행 결과 파일을 workflow artifact로 보존·다운로드하는 공식 경계를 확인했습니다.
- [actions/upload-artifact](https://github.com/actions/upload-artifact): 현재 저장소가 이미 고정한 v7의
  `path`, `if-no-files-found`, `retention-days` 계약을 사용합니다.

수동 실행 전 bootstrap의 macOS commit과 Film Emulation 제품 source 네 파일의 diff가 0인지 확인합니다.
artifact는 자동 정답이 아니며 source·runner·OS와 default/software-requested 차이를 검토한 뒤에만
canonical fixture로 채택합니다.

## 제조사 자료와 상표

- [Kodak Professional EKTACHROME E100 기술 자료](https://kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4000_ektachrome_100.pdf)
- [Kodak Professional PORTRA 400 기술 자료](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)
- [Fujifilm PROVIA 100F 데이터시트](https://asset.fujifilm.com/www/us/files/2020-03/6325e0d91ad8f74448c5968b5a954199/Provia100f.pdf)
- [Fujifilm VELVIA 50 데이터시트](https://asset.fujifilm.com/www/in/files/2020-07/fcc8016d9ffc8503faacbc39c9b827c4/films_velvia-50_datasheet_01.pdf)

이 자료는 제품명과 필름 유형 확인에만 사용했습니다. 감광 곡선, 표, 사진이나 제조사 측정값을
implementation data로 옮기지 않았습니다. 이름은 macOS recipe 호환과 필름 유형 식별을 위한 지명적
사용이며 Kodak·Fujifilm의 제휴, 보증 또는 공식 재현을 주장하지 않습니다. 저장소의 `TRADEMARKS.md`와
같은 경계를 따릅니다.

## 특허 engineering screen

- [WO2006104666A2 / US7274428B2 family](https://patents.google.com/patent/WO2006104666A2/en)는 Google
  Patents에서 미국은 fee-related expiry, EP ceased, CA abandoned, WO ceased로 표시됩니다. claims는
  scan-only film origination, 화학 처리·스캔, scanned film density에 참조한 optical-density transform과
  motion-picture reproduction을 결합합니다. 현재 component는 still-image creative RGB cube이고 film
  density model, 화학 공정과 motion-picture 출력이 없습니다.
- [US8045796B2](https://patents.google.com/patent/US8045796/en)는 active, 2030-08-24 expiry로
  표시됩니다. device-in-use LUT와 target-device LUT, gamut conversion과 lattice update를 요구하는
  claims와 달리 현재 component는 하나의 고정 creative stock cube이며 장치·target gamut LUT를 결합하지
  않습니다.
- [US7197182B2](https://patents.google.com/patent/US7197182B2/en)는 fee-related expiry로
  표시됩니다. GPU projector의 실시간 film appearance와 film-negative projection의 반복 perceptual
  comparison 구성이며 현재 component에는 projector나 comparison loop가 없습니다.
- [US20140176743A1](https://patents.google.com/patent/US20140176743A1/en)은 abandoned로
  표시됩니다. creative look을 camera에 publish하는 구성이지만 현재 component는 desktop 후처리이며
  camera upload/publish가 없습니다.
- [US6985253B2](https://patents.google.com/patent/US6985253B2/en)는 fee-related expiry로
  표시됩니다. scanner density를 printing density로 바꾸고 film printing/reference patch와 projector
  match를 사용하는 claims이며 현재 RGB cube에는 printing-density, patch와 projector가 없습니다.
- [US8654192B2](https://patents.google.com/patent/US8654192B2/en)는 active, 2032-10-01 expiry로
  표시됩니다. 현상 전 film-video preview에 spectral negative/recorder/printer/positive/projector model과
  추정 3×3 inter-image-effect array, quality metric을 결합합니다. 현재 component는 고정 profile의
  `exposure_saturation` 값을 사용하며 spectral model, 추정 array, preview와 optimizer가 없습니다.
- [US9961236B2](https://patents.google.com/patent/US9961236B2/en)는 active, 2036-07-21 expiry로
  표시됩니다. camera sensor/ISP와 scene 또는 downscaled image에서 만든 dynamic gain curve를 color-mapped
  3D LUT에 적용하는 claims입니다. 현재 component는 desktop 고정 cube이며 sensor/ISP, scene-derived
  gain curve와 dynamic tone mapping이 없습니다.

Google Patents의 legal status와 expiry 표시는 법적 결론이 아닙니다. 위 비교는 가까운 공개 claims와
같은 구성을 무심코 복제하지 않기 위한 제한적 engineering screen이며 법률 자문, 유효성 판단 또는
freedom-to-operate 보증이 아닙니다. 배포 국가, camera integration, device gamut emulation이나 측정 기반
film model이 추가되면 전문 검토가 필요합니다.

## 라이선스·저작권 결론

- Windows core는 저장소와 같은 Apache-2.0이며 이번 변경의 실행·링크 제3자 payload는 0개입니다.
- profile 값은 같은 제품 저장소의 소유 source에서 가져왔고 C++ math와 test는 독립 작성했습니다.
- Apple·제조사 자료는 API·제품명 확인에만 사용했으며 code, 표, LUT, 이미지와 측정 데이터를 복사하지
  않았습니다.
- 특허 문서는 claim 경계 비교에만 사용했고 식, code, figure를 구현 근거로 복사하지 않았습니다.
