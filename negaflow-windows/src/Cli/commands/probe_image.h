#pragma once

namespace negaflow::cli {

/// `--probe-image <path>` — 표준 이미지 디코더(JPEG/PNG/카메라 RAW)를 그대로 돌리고
/// **어느 디코더가 화소를 만들었는지** 함께 보고합니다.
///
/// 이것이 필요한 이유: Windows 는 카메라 RAW codec 을 기본 제공하지 않습니다. 어떤 기계는
/// Microsoft Store 의 Raw Image Extension 이 깔려 있고 어떤 기계는 없습니다. 결과만 보면
/// 둘을 구분할 수 없으므로, 함께 배포한 `libraw.dll` 이 대신 현상했는지를 증거로 남깁니다.
int run_probe_image(int argument_count, const wchar_t* const arguments[]);

}  // namespace negaflow::cli
