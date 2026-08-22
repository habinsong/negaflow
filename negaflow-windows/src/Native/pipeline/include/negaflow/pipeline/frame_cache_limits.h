#pragma once

#include <cstdint>

namespace negaflow::pipeline {

// 설정 창 "메모리 캐시" 가 고른 상주 한도입니다.
//
// macOS 는 `FrameCacheResidencyStore.onLimitsChange` 가 `FrameCacheManager` 에 곧바로
// 한도를 겁니다. Windows 는 상주 캐시가 두 곳에 나뉘어 있습니다 — managed
// `ThumbnailService` 의 표시본과, 여기 네이티브의 디코드 원본·프리뷰 프록시입니다.
// 앞 판은 네이티브 두 곳이 설치 메모리만 보고 예산을 정해, **설정에서 무엇을 골라도
// 아무 것도 바뀌지 않았습니다.** 이 자리가 그 값을 받는 자리입니다.
//
// 단위는 macOS 와 같은 **프레임 수**입니다. 프레임 하나의 값은
// `FrameCacheBudget::cleaned_raw_megabytes_per_frame` · `developed_megabytes_per_frame`
// 이며, 설정 창이 "예상 상주 메모리" 로 보여 주는 것과 같은 셈입니다.
struct FrameCacheResidencyLimits final {
    // 0 이면 자동입니다 — 설치 메모리에서 macOS 비율로 예산을 잡습니다.
    std::uint32_t cleaned_raw_frames{0};
    std::uint32_t developed_frames{0};
};

// 셸이 설정을 읽거나 사용자가 값을 바꿀 때마다 부릅니다. 둘 다 0 이면 자동으로 돌아갑니다.
// 캐시가 하는 일은 그대로이며 **상한만** 바뀝니다 — 낮추면 다음 축출에서 오래된 것부터
// 내려놓고, 올리면 그만큼 더 담습니다.
void set_frame_cache_residency_limits(FrameCacheResidencyLimits limits) noexcept;

// 지금 걸려 있는 한도입니다. 시험과 진단이 씁니다.
[[nodiscard]] FrameCacheResidencyLimits frame_cache_residency_limits() noexcept;

}  // namespace negaflow::pipeline
