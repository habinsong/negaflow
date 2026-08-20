#include "preview_proxy.h"

#include "export/stages/invert.h"
#include "export/support/outcome.h"
#include "export/support/preview_raw_store.h"

#include "negaflow/imaging/working_image_resample.h"

#include <algorithm>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {
namespace {

// DevelopFrameRenderer.fullMaxDimension — 정착 슬롯 경계.
constexpr double full_max_dimension = 3600.0;

// macOS `cachedPreviewRaw(for:maxDimension:)`:
//   maxDimension >= DevelopFrameRenderer.fullMaxDimension - 0.5 이면 정착 슬롯.
[[nodiscard]] bool is_settled_box(
    const std::uint32_t box_width,
    const std::uint32_t box_height) noexcept {
    const double long_edge = static_cast<double>(std::max(box_width, box_height));
    return long_edge + 0.5 >= full_max_dimension;
}

[[nodiscard]] bool recipe_blocks_proxy(const DevelopExportRequest& request) noexcept {
    return !request.defect_recipe.order.empty();
}

[[nodiscard]] PreviewRawKey key_for(
    const DevelopExportRequest& request,
    const ObservedSource& observed) {
    PreviewRawKey key{};
    key.path = request.source;
    key.observation = observed.before.observation;
    key.base_mode = request.base_estimation_mode;
    key.film_type = request.negative.film_type;
    key.polarity = request.film_polarity;
    key.has_preset = request.film_stock_preset.has_value() &&
        request.base_estimation_mode == NegativeBaseEstimationMode::preset;
    if (key.has_preset) {
        key.preset_dmin = request.film_stock_preset->dmin;
        key.preset_dmax = request.film_stock_preset->dmax_normalized;
        key.preset_light_gain = request.film_stock_preset->light_gain;
    }
    return key;
}

// 캐시된 화상을 호출자 버퍼로 옮깁니다. `invert_source` 가 제자리에서 고치므로 사본이
// 필요합니다. 복사가 실패해도(메모리 부족) 캐시 버퍼는 `shared_ptr` 이 지키고 있으므로
// 여기서 예외를 삼켜 "캐시 없음"으로 되돌리는 것이 안전합니다.
[[nodiscard]] bool copy_into(
    const PreviewRawImage& cached,
    const PreviewProxyHint& cached_hint,
    negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept {
    try {
        image = *cached;
    } catch (...) {
        return false;
    }
    hint = cached_hint;
    hint.image_is_proxy = true;
    return true;
}

}  // namespace

bool preview_proxy_try_take(
    const DevelopExportRequest& request,
    const ObservedSource& observed,
    const PreviewTarget& preview,
    negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept {
    if (recipe_blocks_proxy(request) || preview.maximum_width == 0U ||
        preview.maximum_height == 0U) {
        return false;
    }

    PreviewRawKey key{};
    try {
        key = key_for(request, observed);
    } catch (...) {
        return false;
    }

    PreviewRawImage cached{};
    PreviewProxyHint cached_hint{};
    if (is_settled_box(preview.maximum_width, preview.maximum_height)) {
        return preview_raw_take_settled(key, cached, cached_hint) &&
            copy_into(cached, cached_hint, image, hint);
    }

    if (preview_raw_take_interactive(
            key, preview.maximum_width, preview.maximum_height, cached, cached_hint)) {
        return copy_into(cached, cached_hint, image, hint);
    }

    // macOS `DevelopFrameRenderer+Input.swift:51-52` 주석 원문:
    //   "요청 치수 캐시가 없어도 정착(풀) raw 프록시가 있으면 GPU 다운스케일로 파생한다.
    //    수십 MP 원본을 디스크에서 재디코딩(수백 ms)하는 대신 한 번의 Lanczos 축소로 끝난다."
    // `makeSnapshot` 의 `preloadedFullPreviewRaw` 자리입니다.
    if (!preview_raw_take_settled(key, cached, cached_hint)) {
        return false;
    }

    std::uint32_t width = 0U;
    std::uint32_t height = 0U;
    preview_fit_size(
        cached->width,
        cached->height,
        preview.maximum_width,
        preview.maximum_height,
        width,
        height);
    if (width == 0U || height == 0U) {
        return false;
    }
    // macOS: `max(extent) <= proxyMaxDimension` 이면 정착본을 **그대로** 씁니다.
    if (width >= cached->width && height >= cached->height) {
        return copy_into(cached, cached_hint, image, hint);
    }

    PreviewRawImage derived{};
    try {
        auto resampled = negaflow::imaging::resample_working_image_lanczos3(
            *cached, width, height);
        if (resampled.status != negaflow::imaging::WorkingImageResampleStatus::ok) {
            return false;
        }
        derived = std::make_shared<const negaflow::imaging::WorkingImage>(
            std::move(resampled.image));
    } catch (...) {
        return false;
    }
    if (!copy_into(derived, cached_hint, image, hint)) {
        return false;
    }
    // macOS `applyPreviewRawCache` — 파생한 프록시도 인터랙티브 슬롯에 남깁니다.
    preview_raw_put_interactive(
        key, preview.maximum_width, preview.maximum_height, std::move(derived), hint);
    return true;
}

std::optional<DevelopExportOutcome> preview_proxy_materialize(
    const DevelopExportRequest& request,
    const ObservedSource& observed,
    const PreviewTarget& preview,
    negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept {
    if (preview.maximum_width == 0U || preview.maximum_height == 0U) {
        return fail(DevelopExportStage::decode, "invalid_preview_target");
    }

    if (request.film_polarity == FilmPolarity::negative &&
        (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate ||
         request.base_estimation_mode == NegativeBaseEstimationMode::preset)) {
        if (auto failed = resolve_negative_base(request, image, hint)) {
            return failed;
        }
    }

    std::uint32_t width = 0U;
    std::uint32_t height = 0U;
    preview_fit_size(
        image.width,
        image.height,
        preview.maximum_width,
        preview.maximum_height,
        width,
        height);
    if (width == 0U || height == 0U) {
        return fail(DevelopExportStage::decode, "empty_preview_source");
    }
    if (width < image.width || height < image.height) {
        // macOS DevelopFrameRenderer.displayProxy — CILanczosScaleTransform.
        auto resampled = negaflow::imaging::resample_working_image_lanczos3(
            image,
            width,
            height);
        if (resampled.status != negaflow::imaging::WorkingImageResampleStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::working_image_resample_status_name(resampled.status));
        }
        image = std::move(resampled.image);
    }

    hint.image_is_proxy = true;
    if (recipe_blocks_proxy(request)) {
        return std::nullopt;
    }

    try {
        const PreviewRawKey key = key_for(request, observed);
        PreviewRawImage stored =
            std::make_shared<const negaflow::imaging::WorkingImage>(image);
        if (is_settled_box(preview.maximum_width, preview.maximum_height)) {
            preview_raw_put_settled(key, std::move(stored), hint);
        } else {
            preview_raw_put_interactive(
                key,
                preview.maximum_width,
                preview.maximum_height,
                std::move(stored),
                hint);
        }
    } catch (...) {
        // 캐시에 못 남겨도 이번 렌더 결과는 이미 `image` 에 있습니다.
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
