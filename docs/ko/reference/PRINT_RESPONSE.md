# 네거티브 반전 응답

[문서 홈](../README.md)

## MAIN/PRINT와 CS

기본값은 `MAIN`과 자동 밸런스 ON입니다. 스위치는 [Chroma Engine](../product/CHROMA_ENGINE.md)에 설명했습니다.

**자동 밸런스 ON.** 채널마다 장면에서 가장 짙은 0.2% 백분위를 쓰고 범위는 1.8D로 제한합니다. 그 뒤에 `shoulder-print-response-v4` 곡선과 약한 장면용 비브런스가 이어집니다. 필름 프리셋은 측정한 범위에 채널별 상대 계수를 곱합니다. 1.8D 제한은 렌더링 안전장치이고 모든 필름의 측정된 성질이 아닙니다. 짙은 네거티브에서는 영향을 줄 수 있습니다.

**자동 밸런스 OFF.** 같은 v4 곡선에 고정 명목 범위(컬러 1.55D, 흑백 2.17D)를 쓰고, 프리셋을 고르면 프리셋 계수를 곱합니다. 장면 범위 정규화와 약한 장면용 비브런스는 건너뜁니다. 컬러 네거티브는 스캐너와 필름의 채널 범위 보정도 곱합니다. 이 값은 같은 롤(롤이 없으면 같은 스캔 폴더)에서 유효하게 측정된 프레임 세 장 이상의 중앙값이며, 한 번 정해지면 프레임마다 유지됩니다. 프레임이 부족하거나 필름이 섞여 있으면 세 채널이 같은 범위를 씁니다. 그러면 같은 베이스와 설정에서 투과율이 같을 때 한 롤의 프레임들이 같은 결과를 냅니다.

ON은 장면 내용에 따라 밝기와 색이 모두 달라질 수 있습니다. 어느 모드도 측정된 필름 색 정확도를 보증하지 않습니다.

장면 측정은 수동 슬라이더를 움직이는 동안 캐시됩니다. Windows는 미리보기의 반전과 비브런스를 D3D로, 내보내기를 CPU로 처리합니다.

## 다른 타깃과 RAW

명시적인 스캐너 타깃은 장면 분석과 고정 `shoulder-print-response-v4` 기본 곡선을 유지합니다. 장면 분석에는 공통 1.8D 상한이 없습니다. 필름 프리셋은 고정된 상대 계수를 쓰며 프레임마다 몰래 정규화하지 않습니다.

두 플랫폼 모두 네거티브 카메라 RAW를 LibRaw `output_color=0`, 선형 전달, 채널 배수 1로 디코딩합니다. 필름 베이스 측정과 반전은 디모자이크된 카메라 RGB에서 하고, 그 뒤 `rgb_cam`이 포지티브를 선형 sRGB로 옮깁니다. 촬영 화이트 밸런스, 자동 밝기, 장면에 따른 최댓값 조정은 끕니다. 미리보기, 결함 캐시, 내보내기는 행렬 적용을 뒤로 미룬 상태를 유지합니다. 디지털 사진 렌더링은 따로입니다. 지원하지 않는 네이티브 출력은 행렬이 적용된 네거티브로 조용히 대체하지 않고 실패합니다. 이 순서가 측정된 카메라·광원·필름 보정을 대신하지는 않습니다. Raw TIFF와 baked-source TIFF는 반전하지 않은 작업 RGB 이미지라서 색 행렬은 그 출력 경계에서 적용합니다.

### 번들 없는 CLI의 RAW 설정

앱 번들에는 디코더가 들어 있습니다. 번들 없는 macOS CLI나 테스트에서는 같은 라이브러리를 빌드해 프로세스를 시작하기 전에 절대 경로를 지정합니다.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## 검증과 출처

`NegativeAutoBalanceTests`는 범위·곡선·비브런스의 조합, OFF, 캐시 재사용을 확인합니다. Windows 테스트는 범위 상한, 프리셋 계수, OFF, CPU/D3D RAW 반전 순서를 확인합니다.

`FixedNegativeResponseTests`는 EXPIRED가 쓰는 v6 모델 회귀를 유지합니다. 프레임 변동이 0이라는 점과 이상적인 순방향 모델의 색은 MAIN/CS 응답이나 실제 필름의 색 정확도를 검증하지 않습니다. 렌더러와 썸네일 식별자가 현재 결과와 이전 캐시 미리보기를 구분합니다.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
