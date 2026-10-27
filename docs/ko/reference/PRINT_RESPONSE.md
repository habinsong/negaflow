# 네거티브 반전 응답

[문서 홈](../README.md)

## MAIN/PRINT와 CS

기본값은 `MAIN`과 자동 밸런스 ON입니다. 타깃 제목 오른쪽의 작은 알약 토글로 켜고 끕니다. 컬러·흑백 네거티브의 MAIN(PRINT 포함)과 CS에서만 보입니다. 현재 사진을 기준으로 색과 밝기를 맞추며 OFF에서는 이 단계를 건너뜁니다. 자동 톤·자동 화이트 밸런스·자동 레벨·자동 색상은 별도 기능이며 기본 OFF입니다.

자동 밸런스 ON은 `412bb31`의 MAIN/CS 반전을 복원합니다. 채널마다 장면 최농부 0.2% 백분위로 밀도 범위를 재고 1.8D로 제한한 뒤 기존 `shoulder-print-response-v4` 곡선과 뮤트한 장면의 채도 보정을 적용합니다. 필름 프리셋을 선택하면 측정 범위에 채널별 상대 계수를 곱합니다. 1.8D는 기존 결과를 유지하기 위한 렌더링 제한이며 모든 필름의 실측 물성값이 아닙니다. 밀도가 높은 음화에도 영향을 줄 수 있습니다.

OFF도 같은 v4 곡선을 사용합니다. 밀도 범위는 명목값(컬러 1.55D, 흑백 2.17D)으로 고정하고 선택한 프리셋의 상대 계수를 곱합니다. 장면별 범위 정규화와 채도 보정은 건너뜁니다. 컬러 네거티브의 OFF는 스캐너와 필름의 채널 범위 교정도 곱합니다. 같은 롤(롤을 정하지 않았다면 같은 스캔 폴더)에서 유효하게 측정된 프레임이 세 장 이상일 때 그 프레임들의 중앙값을 쓰고, 한 번 정한 값은 프레임에 그대로 남습니다. 프레임이 모자라거나 필름이 섞여 있으면 세 채널을 같은 범위로 둡니다. 베이스와 설정이 같으면 같은 투과율은 같은 롤의 다른 프레임에서도 같은 결과를 냅니다. ON에서는 장면 구성에 따라 밝기와 색이 모두 달라질 수 있습니다. 어느 모드도 실측 필름 색 정확도를 입증하지는 않습니다.

수동 슬라이더만 바꾸는 동안 장면 측정값을 재사용합니다. Windows 프리뷰는 기존 D3D 반전·채도 보정 경로를 유지하며 내보내기는 CPU 경로를 씁니다. 폐기한 중앙값 gain 구현과 그 성능 측정값은 현재 구현을 설명하지 않습니다. RAW 반전은 계속 카메라 색행렬보다 먼저 실행하고 별도 필름 베이스 수정도 유지합니다. 앱 전체를 `412bb31`로 되돌린 것은 아닙니다.

## 다른 타깃과 RAW

명시적으로 선택한 스캐너 타깃은 장면 분석과 기존 `shoulder-print-response-v4`를 사용합니다. 기존 고정 primitive도 호환용으로 유지합니다. 장면 분석에도 공통 1.8D 상한은 두지 않습니다. 필름 프리셋은 고정 상대 계수를 사용하고 매 프레임을 자동 정규화하지 않습니다.

양쪽 플랫폼은 음화 카메라 RAW를 LibRaw의 `output_color=0`, 선형 전달 함수, 채널 배율 1로 디코드합니다. 데모사이크한 카메라 RGB에서 필름 베이스를 측정하고 반전한 뒤 `rgb_cam`으로 양화를 선형 sRGB로 옮깁니다. 촬영 WB, 자동 밝기, 장면별 maximum 조정은 끕니다. 프리뷰·결함 보정 캐시·내보내기는 지연된 행렬을 유지합니다. 디지털 사진 렌더링은 별도로 처리합니다. 카메라 RGB 출력을 지원하지 않으면 오류를 반환합니다. 이 순서만으로 카메라·광원·필름의 실측 보정이 이루어지지는 않습니다. Raw TIFF와 결함을 적용한 원본 TIFF는 반전하지 않은 작업 RGB 이미지이므로 해당 출력 경계에서 색행렬을 적용합니다.

### 번들 밖 CLI의 RAW 설정

앱 번들에는 디코더를 포함합니다. macOS CLI나 테스트를 번들 밖에서 실행할 때는 같은 라이브러리를 빌드하고 프로세스를 시작하기 전에 절대 경로를 지정합니다.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## 검증과 출처

번들 `Roll_Perforation.tiff`의 한 크롭에 같은 베이스와 설정을 고정하고 별도로 빌드한 `412bb31` 엔진과 비교했습니다. MAIN·PRINT·Studio·Emulsion·필름 프리셋·흑백의 6가지 조건에서 복원한 ON 결과의 32비트 float 화소가 정확히 일치했습니다. 한 입력의 비교이며 모든 스캔이나 카메라 RAW를 검증한 결과는 아닙니다. `NegativeAutoBalanceTests`는 기존 범위·곡선·채도 처리와 OFF, 캐시 재사용을 검사합니다. Windows에서는 범위 제한, 프리셋 계수, OFF, CPU/D3D의 RAW 반전 순서를 검사합니다.

`FixedNegativeResponseTests`에는 EXPIRED가 쓰는 v6 모델 회귀 검사를 남겼습니다. 이 모델의 프레임 간 편차 0과 이상적 순방향 모델의 색 결과가 복원한 MAIN/CS나 실제 필름의 색 정확도를 검증하지는 않습니다. 렌더러와 썸네일 식별자로 이전 캐시와 복원 결과를 구분합니다.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
