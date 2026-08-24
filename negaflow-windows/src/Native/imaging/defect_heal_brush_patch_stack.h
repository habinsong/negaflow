#pragma once

#include "defect_heal_brush_types.h"

#include <cstddef>
#include <vector>

namespace negaflow::imaging::heal_brush_detail {

// 이 패치가 그 화소를 덮는가.
[[nodiscard]] bool contains(const StoredPatch& patch, int x, int y) noexcept;

// 이미 만든 패치를 나중 것부터 훑어 그 화소의 100% 강도 값을 냅니다. 없으면 원본을
// 읽습니다 - 겹친 획이 앞 획의 결과 위에서 다시 고쳐지게 하려는 것입니다.
[[nodiscard]] Rgba32F full_strength_pixel(
    const WorkingImage& base,
    const std::vector<StoredPatch>& patches,
    int x,
    int y) noexcept;

// 반지름 1 가우시안입니다. 패치 경계를 부드럽게 물리는 데만 씁니다.
[[nodiscard]] std::vector<float> gaussian_radius_one(
    const std::vector<float>& source,
    int width,
    int height);

// 16비트 선형으로 한 번 양자화합니다. 미리보기와 내보내기가 같은 값을 보게 합니다.
[[nodiscard]] float quantize_linear16(float value) noexcept;

// 쌓인 패치를 강도만큼 이미지에 앉힙니다. 나중 패치가 이깁니다.
[[nodiscard]] std::size_t composite_patches(
    WorkingImage& image,
    const std::vector<StoredPatch>& patches,
    float strength);

}  // namespace negaflow::imaging::heal_brush_detail
