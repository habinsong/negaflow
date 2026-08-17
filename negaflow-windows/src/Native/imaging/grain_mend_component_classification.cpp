#include "grain_mend_component_classification.h"

#include <algorithm>
#include <utility>

namespace negaflow::imaging::grain_mend_detail {

// 조율값은 grain_mend_component_types.h 의 한 표에서만 옵니다.
using namespace tuning;

void collect_classified(
    const std::vector<Component>& dust,
    const std::vector<std::uint8_t>& drop_dust,
    const std::vector<Component>& scratch,
    const std::vector<std::uint8_t>& drop_scratch,
    const DetectionImage& image,
    const CandidateMaps* const candidates,
    const std::size_t maximum_dust_area,
    std::vector<ClassifiedComponent>& result) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    result.clear();
    result.reserve(dust.size() + scratch.size());
    auto append = [&result](const Component& component, const bool is_scratch) {
        ClassifiedComponent entry{};
        entry.pixels = component.pixels;
        entry.minimum_x = component.minimum_x;
        entry.maximum_x = component.maximum_x;
        entry.minimum_y = component.minimum_y;
        entry.maximum_y = component.maximum_y;
        entry.is_scratch = is_scratch;
        result.push_back(std::move(entry));
    };
    for (std::size_t index = 0U; index < dust.size(); ++index) {
        if (drop_dust[index] == 0U) {
            append(dust[index], false);
        }
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        if (drop_scratch[index] == 0U) {
            append(scratch[index], true);
        }
    }
    if (candidates == nullptr || result.empty() ||
        candidates->dust_magnitude.size() != count) {
        return;
    }

    // 극성은 "컴포넌트 평균 밝기 − 주변 링 평균"이고, 링에서 라벨된 화소를 뺍니다.
    std::vector<std::int32_t> labels(count, -1);
    for (std::size_t index = 0U; index < result.size(); ++index) {
        for (const std::size_t pixel : result[index].pixels) {
            labels[pixel] = static_cast<std::int32_t>(index);
        }
    }
    ClassifierField field{};
    field.width = image.width;
    field.height = image.height;
    field.dust_magnitude = &candidates->dust_magnitude;
    field.thin_magnitude = &candidates->thin_magnitude;
    field.noise_scale = &candidates->noise_scale;
    field.bright = &image.brightest_channel;
    field.strong = &candidates->strong;
    field.labels = &labels;
    classify_components(
        result,
        field,
        std::max<std::size_t>(16U, maximum_dust_area / 25U),
        std::max<std::size_t>(200U, maximum_dust_area / 3U));
}

// 형태 측정은 grain_mend_shape 하나만 씁니다 — 게이트와 분류기가 같은 모양을 봐야 합니다.

}  // namespace negaflow::imaging::grain_mend_detail
