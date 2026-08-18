#include "preview_proxy.h"

#include "export/stages/invert.h"
#include "export/support/outcome.h"

#include "negaflow/imaging/working_image_resample.h"

#include <algorithm>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {
namespace {

// DevelopFrameRenderer.fullMaxDimension — 정착 슬롯 경계.
constexpr double full_max_dimension = 3600.0;

struct PreviewRawSlot final {
    std::filesystem::path path{};
    negaflow::imageio::ImageFileObservation observation{};
    std::uint32_t box_width{0};
    std::uint32_t box_height{0};
    NegativeBaseEstimationMode base_mode{NegativeBaseEstimationMode::manual};
    negaflow::imaging::NegativeFilmType film_type{
        negaflow::imaging::NegativeFilmType::color};
    FilmPolarity polarity{FilmPolarity::negative};
    std::array<float, 3> preset_dmin{};
    std::array<float, 3> preset_dmax{};
    std::array<float, 3> preset_light_gain{};
    bool has_preset{false};
    negaflow::imaging::WorkingImage image{};
    PreviewProxyHint hint{};
    bool occupied{false};
};

PreviewRawSlot g_interactive{};
PreviewRawSlot g_settled{};

[[nodiscard]] PreviewRawSlot& slot_for_box(
    const std::uint32_t box_width,
    const std::uint32_t box_height) noexcept {
    const double long_edge = static_cast<double>(std::max(box_width, box_height));
    return long_edge + 0.5 >= full_max_dimension ? g_settled : g_interactive;
}

[[nodiscard]] bool recipe_blocks_proxy(const DevelopExportRequest& request) noexcept {
    return !request.defect_recipe.order.empty();
}

[[nodiscard]] bool same_preset(
    const PreviewRawSlot& slot,
    const DevelopExportRequest& request) noexcept {
    if (request.base_estimation_mode != NegativeBaseEstimationMode::preset) {
        return !slot.has_preset;
    }
    if (!slot.has_preset || !request.film_stock_preset.has_value()) {
        return false;
    }
    return slot.preset_dmin == request.film_stock_preset->dmin &&
        slot.preset_dmax == request.film_stock_preset->dmax_normalized &&
        slot.preset_light_gain == request.film_stock_preset->light_gain;
}

[[nodiscard]] bool slot_matches(
    const PreviewRawSlot& slot,
    const DevelopExportRequest& request,
    const ObservedSource& observed,
    const PreviewTarget& preview) noexcept {
    return slot.occupied &&
        slot.path == request.source &&
        negaflow::imageio::same_image_file_observation(
            slot.observation,
            observed.before.observation) &&
        slot.box_width == preview.maximum_width &&
        slot.box_height == preview.maximum_height &&
        slot.base_mode == request.base_estimation_mode &&
        slot.film_type == request.negative.film_type &&
        slot.polarity == request.film_polarity &&
        same_preset(slot, request);
}

void remember_preset(PreviewRawSlot& slot, const DevelopExportRequest& request) noexcept {
    slot.has_preset = request.film_stock_preset.has_value() &&
        request.base_estimation_mode == NegativeBaseEstimationMode::preset;
    if (slot.has_preset) {
        slot.preset_dmin = request.film_stock_preset->dmin;
        slot.preset_dmax = request.film_stock_preset->dmax_normalized;
        slot.preset_light_gain = request.film_stock_preset->light_gain;
    }
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
    PreviewRawSlot& slot = slot_for_box(preview.maximum_width, preview.maximum_height);
    if (!slot_matches(slot, request, observed, preview)) {
        return false;
    }
    image = slot.image;
    hint = slot.hint;
    hint.image_is_proxy = true;
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

    PreviewRawSlot& slot = slot_for_box(preview.maximum_width, preview.maximum_height);
    slot.path = request.source;
    slot.observation = observed.before.observation;
    slot.box_width = preview.maximum_width;
    slot.box_height = preview.maximum_height;
    slot.base_mode = request.base_estimation_mode;
    slot.film_type = request.negative.film_type;
    slot.polarity = request.film_polarity;
    remember_preset(slot, request);
    slot.image = image;
    slot.hint = hint;
    slot.occupied = true;
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
