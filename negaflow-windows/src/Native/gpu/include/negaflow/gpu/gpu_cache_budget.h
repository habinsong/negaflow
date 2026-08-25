#pragma once

// GPU 작업 텍스처가 쓸 수 있는 바이트 상한입니다.
//
// **왜 새로 만드는가** — RAM 쪽 캐시(`FrameCacheBudget`)는 이미 바이트로 재고 설치 메모리의
// 25~35% 안에 묶여 있습니다. 그런데 `GpuImagePool` 이 잡는 텍스처는 **어느 예산에도 들어
// 있지 않았습니다.** 48MP(8496×5664) 한 장이 float32 RGBA 로 770MB 이고 풀은 최대 여섯 장
// + 보존 여섯 장이라, 아무도 안 막으면 한 풀이 9.2GB 를 잡습니다. macOS 는 통합 메모리라
// 이 자리가 없습니다 — Windows 에서만 필요한 예산입니다.
//
// **내장과 외장을 가릅니다.**
// - 외장(`dedicated_video_memory > 0`)은 VRAM 이 따로 있으므로 DXGI 가 알려주는
//   `QueryVideoMemoryInfo(LOCAL).Budget` 에서 몫을 뗍니다. 그 값은 정적 VRAM 용량이 아니라
//   **다른 앱까지 감안해 지금 이 프로세스가 써도 되는 양**이라, 다른 앱이 늘면 같이 줄어듭니다.
// - 내장(`is_integrated`)은 VRAM 이 시스템 RAM 입니다. DXGI 가 공유 메모리를 통째로 예산으로
//   보고하므로 그대로 믿으면 RAM 을 두 번 세게 됩니다. 설치 RAM 에서 뗍니다.
//
// 한도는 "미리 잡아 두는 양" 이 아니라 **상한**입니다. 넘으면 풀이 텍스처를 만들지 않고
// `ensure` 가 false 를 돌려주며, 호출부는 이미 그 경우 CPU 경로로 갑니다.

#include <cstdint>

namespace negaflow::gpu {

class GpuDevice;

struct GpuCacheBudget final {
    // 외장: DXGI 예산의 몫입니다. 나머지는 스왑체인·컴포지션·다른 앱 몫으로 남깁니다.
    static constexpr double discrete_budget_fraction = 0.60;

    // 내장: 설치 RAM 의 몫입니다. RAM 캐시가 이미 25~35% 를 쓰므로 그 위에 얹는 몫입니다.
    static constexpr double integrated_system_fraction = 0.10;

    /// 이 기계의 GPU 를 보고 자동으로 잡은 상한입니다.
    ///
    /// **절대 하한을 두지 않습니다.** 기계마다 VRAM 도 RAM 도 다르므로 바이트 상수를 박으면
    /// 어느 기계에서는 예산이 되고 어느 기계에서는 거짓말이 됩니다. 전부 비율로만 잡습니다.
    /// GPU 가 없거나 용량을 못 읽으면 <b>0</b> 이고, 0 은 "한도 없음" 입니다 — 모르는 것을
    /// 근거로 막으면 멀쩡한 기계에서 GPU 를 꺼 버립니다.
    [[nodiscard]] static std::uint64_t automatic_bytes(const GpuDevice& device) noexcept;

    /// 지금 실제로 적용되는 상한입니다 — 수동값이 있으면 그것, 없으면 자동값입니다.
    [[nodiscard]] static std::uint64_t effective_bytes(const GpuDevice& device) noexcept;
};

/// 설정 창이 건 상한입니다. 0 이면 자동입니다.
void set_gpu_cache_limit_bytes(std::uint64_t bytes) noexcept;

[[nodiscard]] std::uint64_t gpu_cache_limit_bytes() noexcept;

/// 지금 풀이 실제로 들고 있는 텍스처 바이트입니다. 시험과 설정 화면이 보는 자리입니다.
[[nodiscard]] std::uint64_t gpu_pool_resident_bytes() noexcept;

/// <summary>
/// 그중 <b>시스템 RAM</b> 에 있는 몫입니다.
/// </summary>
/// <remarks>
/// 외장 그래픽의 작업 텍스처는 VRAM 에 있어 프로세스 private 바이트에 잡히지 않습니다.
/// 내장 그래픽은 VRAM 이 시스템 RAM 이라 그대로 잡힙니다. RAM 예산이 "캐시가 아닌 몫" 을
/// 셀 때 이 차이를 무시하면, 외장에서 VRAM 만큼을 private 에서 빼 버려 간접비를 과소평가하고
/// 예산이 필요 이상으로 커집니다.
/// </remarks>
[[nodiscard]] std::uint64_t gpu_pool_system_memory_bytes() noexcept;

/// 풀이 잡거나 놓을 때마다 부릅니다. 음수 변화는 `released` 로 넘깁니다.
void add_gpu_pool_resident_bytes(std::uint64_t bytes) noexcept;
void remove_gpu_pool_resident_bytes(std::uint64_t bytes) noexcept;

/// 그중 시스템 RAM 몫을 따로 알립니다. 내장이면 전부, 외장이면 0 입니다.
void set_gpu_pool_system_memory_bytes(std::uint64_t bytes) noexcept;

}  // namespace negaflow::gpu
