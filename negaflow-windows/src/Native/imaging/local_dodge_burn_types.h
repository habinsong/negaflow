#pragma once

#include "negaflow/imaging/local_dodge_burn.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging::local_dodge_burn_detail {

// 국소 닷지/번 전체가 공유하는 조율값 한 표입니다.

// 이보다 작은 조정은 아무것도 하지 않은 것으로 봅니다.
inline constexpr float adjustment_identity_threshold = 1.0e-4F;

// 이보다 작은 흐림은 마스크를 그대로 둡니다.
inline constexpr float mask_blur_identity_threshold = 0.25F;

// 이 시그마까지는 직접 가우시안이 더 빠릅니다. 넘으면 박스 세 번으로 근사합니다.
inline constexpr float direct_gaussian_maximum_sigma = 32.0F;

// 화소 좌표 한 점입니다. 정규 좌표인 LocalDodgeBurnPoint 와 구분하려고 따로 둡니다.
struct PixelPoint final {
    float x;
    float y;
};

// 마스크 한 장과 그것을 만드는 데 쓴 최대 임시 메모리입니다.
struct MaskResult final {
    std::vector<float> weights{};
    std::size_t scratch_peak_bytes{0U};
};

// 곱이 넘치면 할당 실패로 냅니다 - 넘친 채로 계속 가면 버퍼가 모자란 줄 모르고 씁니다.
[[nodiscard]] inline std::size_t pixel_count(const WorkingImage& image) {
    if (image.width == 0U || image.height == 0U ||
        static_cast<std::size_t>(image.width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(image.height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(image.width) * image.height;
}

[[nodiscard]] inline float clamp_unit(const float value) noexcept {
    return std::clamp(value, 0.0F, 1.0F);
}

[[nodiscard]] inline std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t width) noexcept {
    return static_cast<std::size_t>(y) * width + x;
}

[[nodiscard]] inline PixelPoint pixel_point(
    const LocalDodgeBurnPoint point,
    const WorkingImage& image) noexcept {
    return {
        clamp_unit(point.x) * static_cast<float>(image.width),
        clamp_unit(point.y) * static_cast<float>(image.height),
    };
}

}  // namespace negaflow::imaging::local_dodge_burn_detail
