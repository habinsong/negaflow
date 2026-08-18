#include "negaflow/imaging/film_scan_denoise.h"

#include "film_scan_denoise_math.h"
#include "film_scan_denoise_tile.h"
#include "film_scan_denoise_types.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::film_scan_denoise_detail;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

}  // namespace

bool valid_film_scan_denoise_parameters(
    const FilmScanDenoiseParameters& parameters) noexcept {
    const auto unit = [](const float value) noexcept {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    };
    return unit(parameters.strength) && unit(parameters.axes.luma) &&
           unit(parameters.axes.chroma) && unit(parameters.axes.dark_tone) &&
           unit(parameters.axes.detail) &&
           unit(parameters.axes.grain_protect) &&
           static_cast<std::uint8_t>(parameters.film_profile) <=
               static_cast<std::uint8_t>(
                   FilmScanDenoiseFilmProfile::black_and_white_positive);
}

FilmScanDenoiseResult apply_film_scan_denoise(
    WorkingImage image,
    const FilmScanDenoiseParameters& parameters,
    const negaflow::core::CancelFlag cancel) noexcept {
    FilmScanDenoiseResult result{};
    result.image = std::move(image);
    if (!valid_film_scan_denoise_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }

    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = FilmScanDenoiseStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= film_scan_denoise_identity_threshold) {
        result.status = FilmScanDenoiseStatus::ok;
        return result;
    }

    try {
        std::vector<Rgb> output(
            pixel_count(result.image.width, result.image.height));
        result.info.output_scratch_bytes = output.size() * sizeof(Rgb);
        const Profile profile = film_scan_denoise_film_scalars(parameters.film_profile);

        // Each tile reads an apron but writes only its own core, and the cores are
        // disjoint. That is what makes the tile rows independent, so splitting them
        // across cores changes nothing but the wall clock. On a 17 MP scan this stage
        // was by far the most expensive in the whole develop.
        const std::uint32_t tile_rows =
            (result.image.height + film_scan_denoise_tile_side - 1U) /
            film_scan_denoise_tile_side;
        std::atomic<std::uint32_t> tiles_processed{0U};
        std::atomic<bool> cancelled{false};
        const std::uint64_t work_units =
            static_cast<std::uint64_t>(result.image.width) *
            static_cast<std::uint64_t>(result.image.height);
        negaflow::core::for_each_row_block(
            tile_rows,
            work_units,
            [&](const std::uint32_t first_tile_row,
                const std::uint32_t tile_row_count) noexcept {
                std::uint32_t processed = 0U;
                for (std::uint32_t index = first_tile_row;
                     index < first_tile_row + tile_row_count;
                     ++index) {
                    if (cancel.requested()) {
                        cancelled.store(true, std::memory_order_relaxed);
                        break;
                    }
                    const std::uint32_t core_y =
                        index * film_scan_denoise_tile_side;
                    for (std::uint32_t core_x = 0U;
                         core_x < result.image.width;
                         core_x += film_scan_denoise_tile_side) {
                        process_tile(
                            result.image,
                            parameters,
                            profile,
                            make_tile(result.image, core_x, core_y),
                            output);
                        ++processed;
                    }
                }
                tiles_processed.fetch_add(processed, std::memory_order_relaxed);
            });
        if (cancelled.load(std::memory_order_relaxed)) {
            result.status = FilmScanDenoiseStatus::cancelled;
            discard_pixels(result.image);
            return result;
        }
        result.info.tiles_processed = tiles_processed.load(std::memory_order_relaxed);

        negaflow::core::for_each_row_block(
            result.image.height,
            work_units,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                    auto* const row = result.image.pixels.data() +
                        static_cast<std::size_t>(y) * result.image.stride_pixels;
                    for (std::uint32_t x = 0U; x < result.image.width; ++x) {
                        const Rgb value =
                            output[index_of(x, y, result.image.width)];
                        row[x].red = value.red;
                        row[x].green = value.green;
                        row[x].blue = value.blue;
                    }
                }
            });
        result.info.applied = true;
        result.status = FilmScanDenoiseStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = FilmScanDenoiseStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = FilmScanDenoiseStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* film_scan_denoise_status_name(
    const FilmScanDenoiseStatus status) noexcept {
    switch (status) {
        case FilmScanDenoiseStatus::cancelled:
            return "cancelled";
        case FilmScanDenoiseStatus::ok:
            return "ok";
        case FilmScanDenoiseStatus::invalid_parameter:
            return "invalid_parameter";
        case FilmScanDenoiseStatus::kernel_failed:
            return "kernel_failed";
        case FilmScanDenoiseStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}


}  // namespace negaflow::imaging
