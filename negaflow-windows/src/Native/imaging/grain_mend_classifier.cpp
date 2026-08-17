#include "negaflow/imaging/grain_mend_classifier.h"

#include "grain_mend_shape.h"

#include <algorithm>
#include <cmath>

namespace negaflow::imaging::grain_mend_detail {
namespace {

// 스크래치 주축 각도 → 방향 분류 경계(도). macOS `DefectClassifier` 와 같은 값입니다.
constexpr double horizontal_band = 30.0;
constexpr double vertical_band = 30.0;

// 극성 판정 링의 여유(화소). macOS `pad = 3`.
constexpr int ring_padding = 3;

// pinhole 판정: 밝은 쪽으로 이만큼은 튀어야 합니다.
constexpr double pinhole_minimum_polarity = 0.015;
constexpr double pinhole_maximum_aspect = 2.5;
constexpr double pinhole_minimum_fill = 0.4;

// emulsion damage 판정: 넓으면서 불규칙하거나 두꺼운 것.
constexpr double emulsion_maximum_fill = 0.5;
constexpr double emulsion_minimum_thickness = 8.0;

// confidence = 0.2 + 0.5·strong 비율 + 0.3·min(1, snr/8).
constexpr double confidence_floor = 0.2;
constexpr double confidence_strong_weight = 0.5;
constexpr double confidence_snr_weight = 0.3;
constexpr double confidence_snr_scale = 8.0;
constexpr double minimum_noise = 1.0e-4;

[[nodiscard]] float sample(
    const std::vector<float>* values,
    const std::size_t index) noexcept {
    return values != nullptr && index < values->size() ? (*values)[index] : 0.0F;
}

struct Evidence final {
    double confidence{0.5};
    double polarity{0.0};
};

// macOS `componentEvidence`. strong 코어 비율과 진폭/국소그레인 SNR 을 섞고, 채택된
// 컴포넌트의 하한을 0.2 로 두어 "약하지만 채택된" 결함이 0 에 붙지 않게 합니다.
[[nodiscard]] Evidence component_evidence(
    const ClassifiedComponent& component,
    const ClassifierField& field) noexcept {
    double strong_count = 0.0;
    double magnitude = 0.0;
    double noise = 0.0;
    double inside = 0.0;
    for (const std::size_t index : component.pixels) {
        if (field.strong != nullptr && index < field.strong->size() &&
            (*field.strong)[index] != 0U) {
            strong_count += 1.0;
        }
        magnitude += static_cast<double>(std::max(
            sample(field.dust_magnitude, index),
            sample(field.thin_magnitude, index)));
        noise += static_cast<double>(sample(field.noise_scale, index));
        inside += static_cast<double>(sample(field.bright, index));
    }
    const double count = static_cast<double>(std::max<std::size_t>(
        1U,
        component.pixels.size()));
    const double strong_fraction = strong_count / count;
    const double signal_to_noise =
        (magnitude / count) / std::max(minimum_noise, noise / count);
    const double confidence = std::clamp(
        confidence_floor +
            confidence_strong_weight * strong_fraction +
            confidence_snr_weight *
                std::min(1.0, signal_to_noise / confidence_snr_scale),
        0.0,
        1.0);

    // 극성: 컴포넌트 평균 밝기 − 주변 링 평균 밝기(라벨된 화소 제외).
    // 0 보다 크면 주변보다 밝은 결함이며 pinhole 후보입니다.
    const int width = static_cast<int>(field.width);
    const int height = static_cast<int>(field.height);
    const int x0 = std::max(
        0,
        static_cast<int>(component.minimum_x) - ring_padding);
    const int x1 = std::min(
        width - 1,
        static_cast<int>(component.maximum_x) + ring_padding);
    const int y0 = std::max(
        0,
        static_cast<int>(component.minimum_y) - ring_padding);
    const int y1 = std::min(
        height - 1,
        static_cast<int>(component.maximum_y) + ring_padding);
    double ring = 0.0;
    double ring_count = 0.0;
    for (int y = y0; y <= y1; ++y) {
        for (int x = x0; x <= x1; ++x) {
            const std::size_t index =
                static_cast<std::size_t>(y) * field.width +
                static_cast<std::size_t>(x);
            const bool labelled = field.labels != nullptr &&
                index < field.labels->size() && (*field.labels)[index] >= 0;
            if (labelled) {
                continue;
            }
            ring += static_cast<double>(sample(field.bright, index));
            ring_count += 1.0;
        }
    }
    const double polarity =
        ring_count > 0.0 ? inside / count - ring / ring_count : 0.0;
    return {confidence, polarity};
}

// macOS `classification`.
[[nodiscard]] DefectClassification classify_one(
    const ClassifiedComponent& component,
    const std::uint32_t width,
    const double polarity,
    const std::size_t pinhole_maximum_area,
    const std::size_t emulsion_minimum_area) noexcept {
    const PcaMetrics pca = pca_metrics(component.pixels, width);
    if (component.is_scratch) {
        // 주축 방향으로 수평/수직/대각을 가릅니다.
        const double angle = pca.angle_degrees;
        if (angle <= horizontal_band || angle >= 180.0 - horizontal_band) {
            return DefectClassification::scratch_horizontal;
        }
        if (std::abs(angle - 90.0) <= vertical_band) {
            return DefectClassification::scratch_vertical;
        }
        return DefectClassification::scratch_diagonal;
    }

    const std::size_t area = component.pixels.size();
    const std::uint32_t box_width =
        component.maximum_x - component.minimum_x + 1U;
    const std::uint32_t box_height =
        component.maximum_y - component.minimum_y + 1U;
    const double fill_ratio = static_cast<double>(area) /
        static_cast<double>(std::max<std::uint32_t>(
            1U,
            box_width * box_height));
    if (polarity > pinhole_minimum_polarity &&
        area <= pinhole_maximum_area &&
        pca.aspect <= pinhole_maximum_aspect &&
        fill_ratio >= pinhole_minimum_fill) {
        return DefectClassification::pinhole;
    }
    if (area >= emulsion_minimum_area &&
        (fill_ratio <= emulsion_maximum_fill ||
         pca.thickness >= emulsion_minimum_thickness)) {
        return DefectClassification::emulsion_damage;
    }
    return DefectClassification::dust;
}

}  // namespace

void classify_components(
    std::vector<ClassifiedComponent>& components,
    const ClassifierField& field,
    const std::size_t pinhole_maximum_area,
    const std::size_t emulsion_minimum_area) noexcept {
    if (field.width == 0U || field.height == 0U) {
        return;
    }
    for (ClassifiedComponent& component : components) {
        if (component.pixels.empty()) {
            continue;
        }
        const Evidence evidence = component_evidence(component, field);
        component.confidence = evidence.confidence;
        component.classification = classify_one(
            component,
            field.width,
            evidence.polarity,
            pinhole_maximum_area,
            emulsion_minimum_area);
    }
}

}  // namespace negaflow::imaging::grain_mend_detail
