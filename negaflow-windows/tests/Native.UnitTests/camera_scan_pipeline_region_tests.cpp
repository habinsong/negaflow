// 디지털 카메라 스캔의 크롭(측정 영역)이 현상 파이프라인 단계까지 이어지는지의 시험입니다.
// 합성 프레임만 씁니다 — `camera_scan_measurement_tests.cpp` 와 같은 모양(백라이트·홀더·
// 리베이트·이웃 프레임·사진 영역)입니다. 실사진은 쓰지 않습니다.
//
// 지키는 것:
//   ① 베이스 해석이 요청의 크롭을 영역으로 넘깁니다(크롭 바깥 띠 우선). 크롭이 없으면 예전과
//      같은 전체 프레임 해석입니다.
//   ② 반전 단계가 같은 영역을 반전 측정과 뒤 단계(장면 보정·타깃·톤)에 넘깁니다.
//   ③ 프리뷰 raw 캐시는 크롭을 키에 넣지 않습니다(넣으면 크롭마다 원본 재디코드). 대신 크롭이
//      바뀌면 화상은 그대로 두고 베이스만 다시 풀고, 그 값을 두 슬롯에 남겨 같은 크롭의 다음
//      틱은 다시 풀지 않습니다.

#include "export/stages/invert.h"
#include "export/stages/observe.h"
#include "export/support/preview_proxy.h"
#include "export/support/preview_raw_store.h"

#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_stock_base_resolver.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <utility>

namespace {

namespace detail = negaflow::pipeline::develop_export_detail;
using negaflow::imaging::AnalysisRegion;
using negaflow::imaging::WorkingImage;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint32_t frame_width = 1500U;
constexpr std::uint32_t frame_height = 1000U;
constexpr std::uint32_t image_x0 = 140U, image_x1 = 1360U;   // 사진 영역(y-down)
constexpr std::uint32_t image_y0 = 170U, image_y1 = 830U;

[[nodiscard]] std::array<double, 3> portra_base() {
    const auto preset = negaflow::imaging::resolve_film_stock_base_preset(
        L"kodak-portra-400", L"neutral", negaflow::imaging::NegativeFilmType::color);
    return {preset->dmin[0], preset->dmin[1], preset->dmin[2]};
}

// 백라이트(위아래) → 홀더 → 리베이트 → 이웃 프레임 → 사진. 백라이트는 웜 LED(1 : 0.88 : 0.72)이고
// 비네팅이 있어, 가장자리의 어두워진 LED 가 베이스만큼 어둡습니다. 프레임 전체를 뒤지면 그 LED 를
// 베이스로 잡고, 크롭 바깥 띠를 먼저 보면 색도로 걸러 리베이트를 잡습니다 — 두 해석이 갈리므로
// 영역이 전달됐는지 값으로 구분됩니다(`camera_scan_measurement_tests` 의 웜 LED 조건).
constexpr std::array<double, 3> warm_light{0.95, 0.836, 0.684};
constexpr double vignette = 0.55;

[[nodiscard]] WorkingImage camera_scan() {
    const std::array<double, 3> base = portra_base();
    WorkingImage image{};
    image.width = frame_width;
    image.height = frame_height;
    image.stride_pixels = frame_width;
    image.pixels.resize(static_cast<std::size_t>(frame_width) * frame_height);
    for (std::uint32_t y = 0U; y < frame_height; ++y) {
        for (std::uint32_t x = 0U; x < frame_width; ++x) {
            const double dx = (static_cast<double>(x) - frame_width / 2.0) / (frame_width / 2.0);
            const double dy = (static_cast<double>(y) - frame_height / 2.0) / (frame_height / 2.0);
            const double falloff = std::max(0.35, 1.0 - vignette * (dx * dx + dy * dy));
            const auto lit = [&](const std::array<double, 3>& transmission) {
                return std::array<double, 3>{
                    transmission[0] * warm_light[0] / 0.95 * falloff,
                    transmission[1] * warm_light[1] / 0.95 * falloff,
                    transmission[2] * warm_light[2] / 0.95 * falloff};
            };
            const auto film = [&](const double r, const double g, const double b) {
                return lit({base[0] * std::pow(10.0, -r), base[1] * std::pow(10.0, -g),
                            base[2] * std::pow(10.0, -b)});
            };
            std::array<double, 3> value{};
            if (y < 50U || y >= 950U) {
                value = lit({0.95, 0.95, 0.95});
            } else if (y < 100U || y >= 900U) {
                value = lit({0.004, 0.004, 0.004});
            } else if (y < image_y0 || y >= image_y1) {
                value = film(0.0, 0.0, 0.0);
            } else if (x < 120U || x >= 1380U) {
                value = film(1.35, 1.20, 0.95);
            } else if (x < image_x0 || x >= image_x1) {
                value = film(0.0, 0.0, 0.0);
            } else {
                const double d = 0.15 + 1.40 * static_cast<double>(x - image_x0) /
                                            static_cast<double>(image_x1 - image_x0);
                value = film(d, d, d);
            }
            image.pixels[static_cast<std::size_t>(y) * frame_width + x] = {
                static_cast<float>(value[0]), static_cast<float>(value[1]),
                static_cast<float>(value[2]), 1.0F};
        }
    }
    return image;
}

[[nodiscard]] negaflow::imaging::ImageTransformParameters photo_crop() {
    negaflow::imaging::ImageTransformParameters transform{};
    transform.has_crop = true;
    transform.crop = {
        static_cast<double>(image_x0) / frame_width,
        static_cast<double>(frame_height - image_y1) / frame_height,
        static_cast<double>(image_x1 - image_x0) / frame_width,
        static_cast<double>(image_y1 - image_y0) / frame_height};
    return transform;
}

[[nodiscard]] negaflow::pipeline::DevelopExportRequest auto_request(
    const negaflow::imaging::ImageTransformParameters& transform) {
    negaflow::pipeline::DevelopExportRequest request{};
    request.source = L"camera-scan-pipeline-region.tif";
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::auto_estimate;
    request.negative.film_type = negaflow::imaging::NegativeFilmType::color;
    request.image_transform = transform;
    return request;
}

// `preview_proxy.cpp` 의 키와 같은 필드입니다(관측은 기본값).
[[nodiscard]] detail::PreviewRawKey key_for(const negaflow::pipeline::DevelopExportRequest& request) {
    detail::PreviewRawKey key{};
    key.path = request.source;
    key.input_gamma = request.input_gamma;
    key.base_mode = request.base_estimation_mode;
    key.film_type = request.negative.film_type;
    key.polarity = request.film_polarity;
    return key;
}

[[nodiscard]] bool same_dmin(const std::array<float, 3>& left, const std::array<float, 3>& right) {
    return left[0] == right[0] && left[1] == right[1] && left[2] == right[2];
}

[[nodiscard]] bool same_region(const std::optional<AnalysisRegion>& left,
                               const std::optional<AnalysisRegion>& right) {
    if (left.has_value() != right.has_value()) {
        return false;
    }
    return !left.has_value() || (left->left == right->left && left->top == right->top &&
                                 left->width == right->width && left->height == right->height);
}

// ① 크롭이 있으면 베이스를 그 영역으로 풀고, 그 영역을 힌트에 남깁니다.
void test_base_resolution_uses_the_crop() {
    const WorkingImage image = camera_scan();
    const auto region = negaflow::imaging::analysis_region_from_transform(
        photo_crop(), frame_width, frame_height);
    expect(region.has_value(), "the photo crop is a measurement region");

    detail::PreviewProxyHint cropped{};
    expect(!detail::resolve_negative_base(auto_request(photo_crop()), image, cropped).has_value(),
           "cropped base resolves");
    const auto ring = negaflow::imaging::resolve_auto_negative_base(
        image, negaflow::imaging::NegativeFilmType::color, region);
    expect(cropped.has_base && same_dmin(cropped.dmin, ring.dmin),
           "cropped base is the band-first resolution");
    expect(same_region(cropped.base_region, region), "hint records the crop region");
    expect(cropped.base_image_width == frame_width && cropped.base_image_height == frame_height,
           "hint records the size the base was resolved at");

    // 띠에서 찾은 베이스는 리베이트(마스크 × 웜 LED) 색도입니다.
    const std::array<double, 3> truth = portra_base();
    const double expected = std::log10((truth[0] * 1.0) / (truth[2] * 0.72));
    expect(std::abs(std::log10(cropped.dmin[0] / cropped.dmin[2]) - expected) <= 0.05,
           "cropped base has the rebate chroma, not the backlight's");

    detail::PreviewProxyHint whole{};
    expect(!detail::resolve_negative_base(auto_request({}), image, whole).has_value(),
           "uncropped base resolves");
    const auto frame = negaflow::imaging::resolve_auto_negative_base(
        image, negaflow::imaging::NegativeFilmType::color);
    expect(same_dmin(whole.dmin, frame.dmin), "no crop keeps the whole-frame resolution");
    expect(!whole.base_region.has_value(), "no crop records no region");
    // 전제: 이 프레임에서는 두 해석이 갈립니다. 같으면 위 검사들이 영역 전달을 구분하지 못합니다.
    expect(!same_dmin(ring.dmin, frame.dmin), "fixture separates band-first from whole-frame");
}

// ② 반전 단계가 영역을 반전 측정과 뒤 단계에 넘깁니다.
void test_invert_stage_carries_the_region() {
    const auto request = auto_request(photo_crop());
    const auto region = negaflow::imaging::analysis_region_from_transform(
        photo_crop(), frame_width, frame_height);
    negaflow::pipeline::DevelopRunControl control{};
    detail::RunTracker tracker{control, 100U};
    detail::InvertStageOutput out{};
    expect(!detail::invert_source(request, tracker, camera_scan(), out).has_value(),
           "invert succeeds");
    expect(same_region(out.analysis_region, region), "invert output carries the crop region");
    expect(same_region(out.negative.analysis_region, region),
           "inversion measures inside the crop");

    // 같은 베이스·같은 영역으로 직접 반전한 값과 같아야 합니다.
    negaflow::imaging::ManualNegativeDevelopParameters parameters{};
    parameters.dmin = out.reference_base;
    parameters.film_type = negaflow::imaging::NegativeFilmType::color;
    parameters.analysis_region = region;
    const auto direct = negaflow::imaging::develop_manual_negative(camera_scan(), parameters);
    expect(same_dmin(out.developed_info.dmax_normalized, direct.info.dmax_normalized),
           "stage density range equals the region-measured inversion");

    detail::InvertStageOutput plain{};
    expect(!detail::invert_source(auto_request({}), tracker, camera_scan(), plain).has_value(),
           "uncropped invert succeeds");
    expect(!plain.analysis_region.has_value() && !plain.negative.analysis_region.has_value(),
           "no crop leaves measurement on the whole frame");
}

// ③ 크롭이 바뀌면 캐시의 화상은 그대로, 베이스만 다시 풉니다.
void test_preview_cache_refreshes_base_when_crop_changes() {
    detail::preview_raw_store_reset();
    const auto cropped_request = auto_request(photo_crop());
    const auto plain_request = auto_request({});
    const auto key = key_for(plain_request);
    const auto region = negaflow::imaging::analysis_region_from_transform(
        photo_crop(), frame_width, frame_height);

    // 정착 슬롯에 크롭 영역으로 푼 것처럼 꾸민 힌트를 넣습니다. 값은 일부러 틀리게 둡니다 —
    // 같은 크롭이면 다시 풀지 않는다는 것을 그 값이 그대로 나오는지로 봅니다.
    const auto stored = std::make_shared<const WorkingImage>(camera_scan());
    detail::PreviewProxyHint planted{};
    planted.image_is_proxy = true;
    planted.has_base = true;
    planted.dmin = {0.5F, 0.4F, 0.3F};
    planted.base_source = negaflow::pipeline::DevelopBaseSource::auto_connected_component;
    planted.base_region = region;
    planted.base_image_width = frame_width;
    planted.base_image_height = frame_height;
    detail::preview_raw_put_settled(key, stored, planted);

    const detail::ObservedSource observed{};
    detail::PreviewTarget settled_box{};
    settled_box.maximum_width = detail::preview_full_max_dimension;
    settled_box.maximum_height = detail::preview_full_max_dimension;

    WorkingImage image{};
    detail::PreviewProxyHint hint{};
    expect(detail::preview_proxy_try_take(cropped_request, observed, settled_box, image, hint),
           "same crop takes the cached raw");
    expect(same_dmin(hint.dmin, planted.dmin), "same crop reuses the cached base");

    // 크롭을 풀면 전체 프레임 해석으로 바뀌어야 합니다.
    expect(detail::preview_proxy_try_take(plain_request, observed, settled_box, image, hint),
           "changed crop still takes the cached raw (no decode)");
    const auto frame = negaflow::imaging::resolve_auto_negative_base(
        *stored, negaflow::imaging::NegativeFilmType::color);
    expect(same_dmin(hint.dmin, frame.dmin), "changed crop re-resolves the base");
    expect(!hint.base_region.has_value(), "re-resolved hint records the new (empty) region");
    expect(image.width == frame_width && image.height == frame_height,
           "the cached raw itself is unchanged");

    detail::PreviewRawImage slot{};
    detail::PreviewProxyHint slot_hint{};
    expect(detail::preview_raw_take_settled(key, slot, slot_hint) && slot == stored,
           "the settled slot keeps the same raw buffer");
    expect(same_dmin(slot_hint.dmin, frame.dmin) && !slot_hint.base_region.has_value(),
           "the settled slot remembers the re-resolved base");

    // 인터랙티브 상자는 정착본에서 파생되며 같은 베이스를 씁니다.
    detail::PreviewTarget interactive_box{};
    interactive_box.maximum_width = 750U;
    interactive_box.maximum_height = 750U;
    expect(detail::preview_proxy_try_take(plain_request, observed, interactive_box, image, hint),
           "interactive box derives from the settled raw");
    expect(same_dmin(hint.dmin, frame.dmin), "interactive preview shares the settled base");

    // 다시 크롭하면 인터랙티브 슬롯도 정착본 기준으로 다시 풀고, 두 슬롯이 같은 값을 갖습니다.
    expect(detail::preview_proxy_try_take(cropped_request, observed, interactive_box, image, hint),
           "interactive box takes the cached raw after re-cropping");
    const auto ring = negaflow::imaging::resolve_auto_negative_base(
        *stored, negaflow::imaging::NegativeFilmType::color, region);
    expect(same_dmin(hint.dmin, ring.dmin), "re-cropping resolves the band from the settled raw");
    expect(detail::preview_raw_take_settled(key, slot, slot_hint) &&
               same_dmin(slot_hint.dmin, ring.dmin) && same_region(slot_hint.base_region, region),
           "both slots carry the re-cropped base");
    detail::preview_raw_store_reset();
}

}  // namespace

int main() {
    test_base_resolution_uses_the_crop();
    test_invert_stage_carries_the_region();
    test_preview_cache_refreshes_base_when_crop_changes();
    if (failures != 0) {
        std::cerr << failures << " camera scan pipeline region check(s) failed\n";
        return 1;
    }
    std::cout << "camera scan pipeline region tests passed\n";
    return 0;
}
