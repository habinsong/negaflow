#pragma once

// 진입점들이 나눠 쓰는 작업 텍스처 묶음입니다.
//
// **왜 필요한가** — 텍스처를 호출마다 만들면 24MP 에서 264 MB 텍스처와 그에 딸린
// 스테이징을 **매번 할당·해제**합니다. 실측으로 그 할당이 다운로드 시간의 큰 몫이었고
// (99 → 62 ms), 스테이징을 들고 있게 바꾼 뒤에도 텍스처 쪽은 그대로였습니다.
// 한 번 잡아 두고 크기가 바뀔 때만 다시 만듭니다.
//
// **여러 묶음을 만들지 마십시오.** 24MP 에서 여섯 장이 1.6 GB 입니다. 필름 룩
// 오케스트레이터도 이 묶음을 받아 씁니다 — 자기 것을 따로 들면 3.2 GB 가 됩니다.
//
// 최대 여섯 장인 이유: 헐레이션이 원본 + 스크래치 넷 + 결과를 **한꺼번에** 씁니다.
// 호출부가 필요한 장수를 넘기며, 단순 opening/closing은 세 장만 할당합니다.

#include <cstdint>

#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::gpu {

class GpuDevice;

class GpuImagePool final {
public:
    static constexpr int size = 6;

    GpuImagePool() noexcept = default;
    // 풀이 사라질 때 들고 있던 바이트를 전역 회계에서 뺍니다. 안 빼면 그만큼이 영원히
    // 예산을 먹은 것으로 남아, 다음 풀이 멀쩡한 치수를 예산 초과로 거부합니다.
    ~GpuImagePool();

    GpuImagePool(const GpuImagePool&) = delete;
    GpuImagePool& operator=(const GpuImagePool&) = delete;

    // 앞 둘(`0`,`1`)은 핑퐁, 뒤 넷(`2`…`5`)은 스크래치로 쓰는 것이 관례입니다.
    // 헐레이션·아큐턴스·색 프리셋이 스크래치를 연속 배열로 받으므로 그 순서를 지키십시오.
    static constexpr int scratch_first = 2;

    [[nodiscard]] bool ensure(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height,
        int required_image_count = size) noexcept;

    /// 풀해상도 일회 작업 뒤 재생성 가능한 texture/staging 두 치수를 모두 반환합니다.
    void clear() noexcept;

    [[nodiscard]] GpuWorkingImage* images() noexcept { return images_; }
    [[nodiscard]] const GpuWorkingImage* images() const noexcept { return images_; }

    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }

    [[nodiscard]] bool has_retained_size(
        const std::uint32_t width,
        const std::uint32_t height) const noexcept {
        return retained_[0].is_valid() && retained_width_ == width && retained_height_ == height;
    }

private:
    /// 실제 일을 합니다. `ensure` 는 이것을 부르고 **모든 출구에서** 회계를 맞춥니다 —
    /// 출구가 여덟 곳이라 자리마다 적으면 언젠가 하나를 빠뜨립니다.
    [[nodiscard]] bool ensure_impl(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height,
        int required_image_count) noexcept;

    /// 이 치수·장수를 새로 잡아도 GPU 캐시 상한 안인지 봅니다.
    [[nodiscard]] bool fits_budget(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height,
        int required_image_count) const noexcept;

    /// 지금 실제로 들고 있는 바이트를 전역 회계에 반영합니다. `ensure`·`clear` 의 모든
    /// 출구에서 부릅니다 — 한 자리라도 빠뜨리면 회계가 실제와 어긋납니다.
    void sync_resident_bytes() noexcept;

    GpuWorkingImage images_[size]{};
    std::uint32_t width_{0U};
    std::uint32_t height_{0U};
    // 인터랙티브 상자와 정착 3600 이 번갈아 오면 치수가 두 개입니다.
    // 직전 치수 한 벌을 남겨 두면 CreateTexture2D 가 슬라이더마다 6장씩 돌지 않습니다.
    GpuWorkingImage retained_[size]{};
    std::uint32_t retained_width_{0U};
    std::uint32_t retained_height_{0U};
    // 전역 회계에 마지막으로 알린 값입니다. 풀이 여럿일 수 있으므로 절대값이 아니라
    // 차이를 올립니다.
    std::uint64_t reported_bytes_{0ULL};
    // 마지막 `ensure` 가 본 장치가 내장이었는지입니다. 내장이면 텍스처가 시스템 RAM 에
    // 있어 RAM 예산이 그만큼을 캐시 몫으로 세야 합니다.
    bool system_memory_backed_{false};
};

} // namespace negaflow::gpu
