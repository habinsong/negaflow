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

// 지금 이 프로세스의 메모리 내역입니다.
//
// **왜 필요한가** — 캐시가 저마다 자기 예산 안에 있어도 프로세스 총량은 상한을 넘을 수
// 있습니다. 실측으로 31.8GB 기계에서 자동 상한이 8.27GB 인데 앱은 8.77GB 였고, 그 차이는
// 코드(432MB)·런타임·WinUI·D3D11 스테이징(297MB) 처럼 **어느 예산에도 없던 몫**이었습니다.
// 그 몫을 눈으로 봐야 예산이 제대로 도는지 판정할 수 있습니다.
struct FrameCacheMemoryReport final {
    std::uint64_t process_private_bytes{0};
    std::uint64_t decoded_source_resident_bytes{0};
    std::uint64_t decoded_source_budget_bytes{0};
    std::uint64_t preview_proxy_resident_bytes{0};
    std::uint64_t preview_proxy_budget_bytes{0};
    std::uint64_t gpu_pool_resident_bytes{0};
    std::uint64_t gpu_pool_limit_bytes{0};
    // 그중 시스템 RAM 에 있는 몫입니다 - 스테이징 두 장(+내장이면 텍스처까지).
    // 이 몫은 `non_cache_overhead_bytes` 안에 들어 있습니다.
    std::uint64_t gpu_system_memory_bytes{0};
    // 캐시가 아닌 몫입니다. 자동 예산이 이만큼을 빼고 나눕니다.
    std::uint64_t non_cache_overhead_bytes{0};
    // 이 기계의 자동 상한입니다 - 프로세스 전체가 이 안에 있어야 합니다.
    std::uint64_t automatic_process_ceiling_bytes{0};
};

[[nodiscard]] FrameCacheMemoryReport frame_cache_memory_report() noexcept;

}  // namespace negaflow::pipeline
