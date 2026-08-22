#pragma once

// 디지털 원본 전용 필름 룩 사슬을 **한 번 올려 한 번 내리는** 오케스트레이터입니다.
//
// 사슬: 헐레이션 → 색 큐브 → 아큐턴스 → 색 프리셋 → 그레인.
// CPU 판은 `imaging/working_film_look.cpp` 의 같은 순서입니다.
//
// **왜 이것이 따로 필요한가** — 재료마다 올렸다 내리면 24MP 에서 왕복이 다섯 번이고
// 277 MB × 10 이 오갑니다. 실측으로 그 전송이 커널보다 훨씬 컸습니다
// (재료 다섯을 각자 GPU 로 돌린 상태의 `film_look` 1,926 ms 중 대부분이 전송).
// 04 문서 3절의 *"단계마다 올렸다 내리면 집니다"* 가 여기에 그대로 적용됩니다.
//
// **게이트를 여기서 판정하지 마십시오.** `DigitalFilmLookPlan` 이 이미 CPU 가 내린
// 판정을 담고 있습니다. 여기서 다시 판정하면 두 벌이 되어 갈라집니다. 이 클래스는
// **비어 있지 않은 칸을 순서대로 돌리기만** 합니다.
//
// 텍스처 여섯 장을 씁니다 — 핑퐁 둘(`0`,`1`)과 스크래치 넷(`2`…`5`). 헐레이션이 넷을
// 한꺼번에 쓰므로 그것이 최대치입니다. **그 여섯 장은 호출부가 주는
// `GpuImagePool` 입니다.** 자기 것을 따로 들면 24MP 에서 1.6 GB 가 두 벌이 됩니다.
// 풀을 못 잡으면 **처리하지 않았다고 돌려줍니다** — 호출부가 재료별 경로나 CPU 로 갑니다.

#include <cstdint>

#include "negaflow/gpu/gpu_image_pool.h"
#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/working_film_look.h"

namespace negaflow::gpu {

class GpuDevice;

struct GpuFilmLookResult final {
    // 거짓이면 이미지를 **손대지 않았습니다.** 호출부는 그대로 CPU 로 가면 됩니다.
    bool handled{false};
    imaging::DigitalFilmLookApplied applied{};
};

class GpuFilmLookStage final {
public:
    GpuFilmLookStage() noexcept = default;
    ~GpuFilmLookStage();

    GpuFilmLookStage(const GpuFilmLookStage&) = delete;
    GpuFilmLookStage& operator=(const GpuFilmLookStage&) = delete;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuFilmLookStage& stage) noexcept;

    // `pixels` 는 `stride_pixels * height` 개의 RGBA float 이고 제자리에서 바뀝니다.
    // 성공했을 때만 화소가 바뀝니다 — 중간에 실패하면 **하나도 안 바뀝니다**(내리지
    // 않으므로). 그래야 호출부가 CPU 로 이어서 갈 수 있습니다.
    [[nodiscard]] GpuFilmLookResult apply(
        const GpuDevice& device,
        GpuImagePool& pool,
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::DigitalFilmLookPlan& plan) const noexcept;

    struct BwResult final {
        bool handled{false};
        imaging::DigitalBwFilmLookApplied applied{};
    };

    // 흑백 사슬: 헐레이션 → 유제 응답 → 아큐턴스 → 그레인. 왕복 한 번.
    [[nodiscard]] BwResult apply_bw(
        const GpuDevice& device,
        GpuImagePool& pool,
        float* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        const imaging::DigitalBwFilmLookPlan& plan) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return state_ != nullptr; }

private:
    struct State;
    State* state_{nullptr};
};

} // namespace negaflow::gpu
