#pragma once

// 진입점들이 나눠 쓰는 작업 텍스처 묶음입니다.
//
// ☠️ **왜 필요한가** — 텍스처를 호출마다 만들면 24MP 에서 264 MB 텍스처와 그에 딸린
//    스테이징을 **매번 할당·해제**합니다. 실측으로 그 할당이 다운로드 시간의 큰 몫이었고
//    (99 → 62 ms), 스테이징을 들고 있게 바꾼 뒤에도 텍스처 쪽은 그대로였습니다.
//    한 번 잡아 두고 크기가 바뀔 때만 다시 만듭니다.
//
// ☠️ **여러 묶음을 만들지 마십시오.** 24MP 에서 여섯 장이 1.6 GB 입니다. 필름 룩
//    오케스트레이터도 이 묶음을 받아 씁니다 — 자기 것을 따로 들면 3.2 GB 가 됩니다.
//
// 여섯 장인 이유: 헐레이션이 원본 + 스크래치 넷 + 결과를 **한꺼번에** 씁니다.
// 그것이 이 엔진에서 한 번에 필요한 최대치입니다.

#include <cstdint>

#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::gpu {

class GpuDevice;

class GpuImagePool final {
public:
    static constexpr int size = 6;

    // 앞 둘(`0`,`1`)은 핑퐁, 뒤 넷(`2`…`5`)은 스크래치로 쓰는 것이 관례입니다.
    // 헐레이션·아큐턴스·색 프리셋이 스크래치를 연속 배열로 받으므로 그 순서를 지키십시오.
    static constexpr int scratch_first = 2;

    [[nodiscard]] bool ensure(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height) noexcept;

    [[nodiscard]] GpuWorkingImage* images() noexcept { return images_; }
    [[nodiscard]] const GpuWorkingImage* images() const noexcept { return images_; }

    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }

private:
    GpuWorkingImage images_[size]{};
    std::uint32_t width_{0U};
    std::uint32_t height_{0U};
    // 인터랙티브 상자와 정착 3600 이 번갈아 오면 치수가 두 개입니다.
    // 직전 치수 한 벌을 남겨 두면 CreateTexture2D 가 슬라이더마다 6장씩 돌지 않습니다.
    GpuWorkingImage retained_[size]{};
    std::uint32_t retained_width_{0U};
    std::uint32_t retained_height_{0U};
};

}  // namespace negaflow::gpu
