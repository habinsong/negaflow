#include "negaflow/imaging/digital_halation.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

struct Rgb final {
    float red;
    float green;
    float blue;
};

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
}

[[nodiscard]] std::size_t checked_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * height;
}

[[nodiscard]] std::uint32_t clamp_coordinate(
    const std::int64_t value,
    const std::uint32_t upper) noexcept {
    return static_cast<std::uint32_t>(
        std::clamp<std::int64_t>(value, 0, upper));
}

[[nodiscard]] std::vector<float> gaussian_weights(
    const float sigma,
    std::uint32_t& radius) {
    radius = std::max(1U, static_cast<std::uint32_t>(std::ceil(3.0F * sigma)));
    std::vector<float> weights(static_cast<std::size_t>(radius) * 2U + 1U);
    double total = 0.0;
    for (std::int32_t offset = -static_cast<std::int32_t>(radius);
         offset <= static_cast<std::int32_t>(radius); ++offset) {
        const double distance = offset;
        const float weight = static_cast<float>(std::exp(
            -(distance * distance) /
            (2.0 * static_cast<double>(sigma) * sigma)));
        weights[static_cast<std::size_t>(
            offset + static_cast<std::int32_t>(radius))] = weight;
        total += weight;
    }
    for (float& weight : weights) {
        weight = static_cast<float>(weight / total);
    }
    return weights;
}

// 타일 하나를 흐립니다. **타일끼리 겹치지 않으므로** 코어로 나눠도 값이 그대로입니다 —
// 각 타일은 `source` 만 읽고 `accumulator` 의 제 자리에만 씁니다.
void blur_tile(
    const WorkingImage& source,
    const std::uint32_t core_x,
    const std::uint32_t core_y,
    const std::uint32_t core_width,
    const std::uint32_t core_height,
    const std::uint32_t radius,
    const std::vector<float>& weights,
    const std::array<float, 3> scale,
    std::vector<Rgb>& tile,
    std::vector<Rgb>& horizontal,
    std::vector<Rgb>& accumulator) noexcept {
    const std::int32_t signed_radius = static_cast<std::int32_t>(radius);
    const std::uint32_t tile_width = core_width + radius * 2U;
    const std::uint32_t tile_height = core_height + radius * 2U;

    for (std::uint32_t y = 0U; y < tile_height; ++y) {
        const std::uint32_t sy = clamp_coordinate(
            static_cast<std::int64_t>(core_y) + y - radius, source.height - 1U);
        for (std::uint32_t x = 0U; x < tile_width; ++x) {
            const std::uint32_t sx = clamp_coordinate(
                static_cast<std::int64_t>(core_x) + x - radius, source.width - 1U);
            const auto pixel =
                source.pixels[static_cast<std::size_t>(sy) * source.stride_pixels + sx];
            tile[static_cast<std::size_t>(y) * tile_width + x] = {
                pixel.red, pixel.green, pixel.blue};
        }
    }

    // **세로 패스가 읽는 열만** 가로로 흐립니다. 예전에는 halo 열까지 전부 계산하고
    // 버렸습니다 — 반지름이 커질수록 버리는 몫이 커져, 타일 512 에 반지름 113 이면
    // 738 열을 계산해 512 열만 썼습니다.
    for (std::uint32_t y = 0U; y < tile_height; ++y) {
        for (std::uint32_t x = radius; x < radius + core_width; ++x) {
            Rgb sum{};
            for (std::int32_t offset = -signed_radius; offset <= signed_radius; ++offset) {
                const std::uint32_t sx = clamp_coordinate(
                    static_cast<std::int64_t>(x) + offset, tile_width - 1U);
                const float weight =
                    weights[static_cast<std::size_t>(offset + signed_radius)];
                const Rgb sample = tile[static_cast<std::size_t>(y) * tile_width + sx];
                sum.red += sample.red * weight;
                sum.green += sample.green * weight;
                sum.blue += sample.blue * weight;
            }
            horizontal[static_cast<std::size_t>(y) * tile_width + x] = sum;
        }
    }

    for (std::uint32_t y = radius; y < radius + core_height; ++y) {
        for (std::uint32_t x = radius; x < radius + core_width; ++x) {
            Rgb sum{};
            for (std::int32_t offset = -signed_radius; offset <= signed_radius; ++offset) {
                const std::uint32_t sy = clamp_coordinate(
                    static_cast<std::int64_t>(y) + offset, tile_height - 1U);
                const float weight =
                    weights[static_cast<std::size_t>(offset + signed_radius)];
                const Rgb sample =
                    horizontal[static_cast<std::size_t>(sy) * tile_width + x];
                sum.red += sample.red * weight;
                sum.green += sample.green * weight;
                sum.blue += sample.blue * weight;
            }
            Rgb& destination = accumulator[
                static_cast<std::size_t>(core_y + y - radius) * source.width +
                core_x + x - radius];
            destination.red += sum.red * scale[0];
            destination.green += sum.green * scale[1];
            destination.blue += sum.blue * scale[2];
        }
    }
}

// 한 번의 흐림 패스입니다. 타일 격자를 코어로 나눠 돕니다.
//
// 나눠도 값은 **비트까지 같습니다.** 타일마다 더하는 순서가 그대로이고, 서로 다른 타일이
// 같은 자리에 더하지 않기 때문입니다 — 스레드 사이의 축약이 없습니다.
[[nodiscard]] bool accumulate_blur(
    const WorkingImage& source,
    const float sigma,
    const std::array<float, 3> scale,
    std::vector<Rgb>& accumulator,
    std::size_t& scratch_peak_bytes) noexcept {
    std::uint32_t radius = 0U;
    std::vector<float> weights;
    try {
        weights = gaussian_weights(sigma, radius);
    } catch (const std::bad_alloc&) {
        return false;
    }

    const std::uint32_t tile_columns =
        (source.width + digital_halation_tile_side - 1U) / digital_halation_tile_side;
    const std::uint32_t tile_rows =
        (source.height + digital_halation_tile_side - 1U) / digital_halation_tile_side;
    const std::uint64_t tile_total =
        static_cast<std::uint64_t>(tile_columns) * tile_rows;
    if (tile_total == 0U) {
        return true;
    }

    // 한 일꾼이 드는 여벌입니다. 타일마다 새로 잡지 않고 블록마다 한 번만 잡습니다 —
    // 예전에는 타일 수만큼 `std::vector` 두 개를 잡았다 버렸습니다.
    const std::uint32_t widest = std::min(digital_halation_tile_side, source.width) +
        radius * 2U;
    const std::uint32_t tallest = std::min(digital_halation_tile_side, source.height) +
        radius * 2U;
    std::size_t scratch_pair_bytes = 0U;
    try {
        scratch_pair_bytes = checked_count(widest, tallest) * sizeof(Rgb) * 2U;
    } catch (const std::bad_alloc&) {
        return false;
    }

    std::atomic<bool> allocation_failed{false};
    std::atomic<std::uint32_t> blocks{0U};
    // 한 화소마다 가로·세로로 `2r+1` 번씩 곱하고 더합니다. 문턱을 못 넘으면 병렬화가
    // 조용히 꺼지므로, 넘기는 값은 출력 화소 수가 아니라 실제 읽고 쓰는 양이어야 합니다.
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(source.width) * source.height *
        (static_cast<std::uint64_t>(radius) * 2U + 1U) * 2U;
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(tile_total),
        work_units,
        [&](const std::uint32_t first, const std::uint32_t count) noexcept {
            blocks.fetch_add(1U, std::memory_order_relaxed);
            std::vector<Rgb> tile;
            std::vector<Rgb> horizontal;
            try {
                const std::size_t scratch = checked_count(widest, tallest);
                tile.resize(scratch);
                horizontal.resize(scratch);
            } catch (const std::bad_alloc&) {
                allocation_failed.store(true, std::memory_order_relaxed);
                return;
            }
            for (std::uint32_t index = first; index < first + count; ++index) {
                const std::uint32_t core_y =
                    (index / tile_columns) * digital_halation_tile_side;
                const std::uint32_t core_x =
                    (index % tile_columns) * digital_halation_tile_side;
                const std::uint32_t core_height = std::min(
                    digital_halation_tile_side, source.height - core_y);
                const std::uint32_t core_width = std::min(
                    digital_halation_tile_side, source.width - core_x);
                blur_tile(
                    source, core_x, core_y, core_width, core_height, radius, weights,
                    scale, tile, horizontal, accumulator);
            }
        });
    if (allocation_failed.load(std::memory_order_relaxed)) {
        return false;
    }

    // 여벌은 **일꾼 수만큼** 동시에 떠 있습니다. 한 벌만 세면 실제보다 적게 적힙니다.
    const std::size_t workers = std::max<std::size_t>(
        1U, blocks.load(std::memory_order_relaxed));
    scratch_peak_bytes = std::max(
        scratch_peak_bytes,
        accumulator.size() * sizeof(Rgb) + scratch_pair_bytes * workers +
            weights.size() * sizeof(float));
    return true;
}

} // namespace

bool valid_digital_halation_parameters(
    const DigitalHalationParameters& parameters) noexcept {
    return std::isfinite(parameters.strength) &&
           (parameters.emulation == FilmEmulation::none ||
            digital_film_physics(parameters.emulation) != nullptr);
}

DigitalHalationResult apply_digital_halation(
    WorkingImage image,
    const DigitalHalationParameters& parameters) noexcept {
    if (!valid_digital_halation_parameters(parameters)) {
        DigitalHalationResult result{};
        result.image = std::move(image);
        discard_pixels(result.image);
        return result;
    }
    const DigitalFilmPhysics* const physics =
        digital_film_physics(parameters.emulation);
    const DigitalHalationMaterial material = physics == nullptr
        ? DigitalHalationMaterial{}
        : DigitalHalationMaterial{
              physics->scatter_strength,
              physics->halation_strength,
              physics->halation_radius_ratio};
    return apply_digital_halation_material(
        std::move(image), material, parameters.strength);
}

DigitalHalationResult apply_digital_halation_material(
    WorkingImage image,
    const DigitalHalationMaterial& material,
    const double strength) noexcept {
    DigitalHalationResult result{};
    result.image = std::move(image);
    bool valid = std::isfinite(strength) &&
                 std::isfinite(material.radius_ratio) &&
                 material.radius_ratio >= 0.0;
    for (const double value : material.scatter_strength) {
        valid = valid && std::isfinite(value) && value >= 0.0;
    }
    for (const double value : material.halation_strength) {
        valid = valid && std::isfinite(value) && value >= 0.0;
    }
    if (!valid) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DigitalHalationStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    const float amount = static_cast<float>(
        std::clamp(strength, 0.0, 1.0));
    const std::uint32_t reference = std::min(
        result.image.width, result.image.height);
    if (amount <= 1.0e-3F || reference <= 8U ||
        material.radius_ratio <= 0.0) {
        result.status = DigitalHalationStatus::ok;
        return result;
    }

    // **근사입니다**(가우시안 가중치의 곱셈·합). 실측 오차는 delta 0 이지만 그것은
    // 이 가우시안이 직접 컨볼루션이라 러닝 섬의 누적 이력이 없기 때문이고, 산술 자체는
    // 근사 분류입니다. `ApproximateAcceleratorScope` 안에서만 돕니다.
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->digital_halation != nullptr) {
            if (table->digital_halation(
                    reinterpret_cast<float*>(result.image.pixels.data()),
                    result.image.width,
                    result.image.height,
                    result.image.stride_pixels,
                    material.scatter_strength.data(),
                    material.halation_strength.data(),
                    material.radius_ratio,
                    strength)) {
                result.info.applied = true;
                result.info.kernel_status = negaflow::core::KernelStatus::ok;
                result.status = DigitalHalationStatus::ok;
                return result;
            }
        }
    }

    try {
        const std::size_t count = checked_count(
            result.image.width, result.image.height);
        std::vector<Rgb> accumulator(count);
        std::array<float, 3> scatter{};
        std::array<float, 3> halation{};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            scatter[channel] = static_cast<float>(
                material.scatter_strength[channel] * amount);
            halation[channel] = static_cast<float>(
                material.halation_strength[channel] * amount);
        }
        // 행끼리 독립입니다 — 흐림과 같은 이유로 나눠도 값이 그대로입니다.
        negaflow::core::for_each_row_block(
            result.image.height,
            static_cast<std::uint64_t>(result.image.width) * result.image.height * 4U,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                    for (std::uint32_t x = 0U; x < result.image.width; ++x) {
                        const auto pixel = result.image.pixels[
                            static_cast<std::size_t>(y) * result.image.stride_pixels + x];
                        accumulator[
                            static_cast<std::size_t>(y) * result.image.width + x] = {
                            pixel.red * std::max(1.0F - scatter[0] - halation[0], 0.0F),
                            pixel.green * std::max(1.0F - scatter[1] - halation[1], 0.0F),
                            pixel.blue * std::max(1.0F - scatter[2] - halation[2], 0.0F),
                        };
                    }
                }
            });
        const float far_radius = std::max(
            1.0F, static_cast<float>(reference * material.radius_ratio));
        const float near_radius = std::max(0.6F, far_radius * 0.28F);
        const float wide_radius = far_radius * 1.414F;
        bool blurred = accumulate_blur(
            result.image, near_radius, scatter, accumulator,
            result.info.scratch_peak_bytes);
        std::array<float, 3> far_scale{};
        std::array<float, 3> wide_scale{};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            far_scale[channel] = halation[channel] * 0.68F;
            wide_scale[channel] = halation[channel] * 0.32F;
        }
        blurred = accumulate_blur(
            result.image, far_radius, far_scale, accumulator,
            result.info.scratch_peak_bytes) && blurred;
        blurred = accumulate_blur(
            result.image, wide_radius, wide_scale, accumulator,
            result.info.scratch_peak_bytes) && blurred;
        if (!blurred) {
            result.status = DigitalHalationStatus::allocation_failed;
            discard_pixels(result.image);
            return result;
        }
        negaflow::core::for_each_row_block(
            result.image.height,
            static_cast<std::uint64_t>(result.image.width) * result.image.height * 4U,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                    for (std::uint32_t x = 0U; x < result.image.width; ++x) {
                        auto& pixel = result.image.pixels[
                            static_cast<std::size_t>(y) * result.image.stride_pixels + x];
                        const Rgb value = accumulator[
                            static_cast<std::size_t>(y) * result.image.width + x];
                        pixel.red = value.red;
                        pixel.green = value.green;
                        pixel.blue = value.blue;
                    }
                }
            });
    } catch (const std::bad_alloc&) {
        result.status = DigitalHalationStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }

    result.info.applied = true;
    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    result.status = DigitalHalationStatus::ok;
    return result;
}

const char* digital_halation_status_name(
    const DigitalHalationStatus status) noexcept {
    switch (status) {
        case DigitalHalationStatus::ok: return "ok";
        case DigitalHalationStatus::invalid_parameter: return "invalid_parameter";
        case DigitalHalationStatus::invalid_image: return "invalid_image";
        case DigitalHalationStatus::allocation_failed: return "allocation_failed";
        case DigitalHalationStatus::kernel_failed: return "kernel_failed";
    }
    return "unknown_status";
}

} // namespace negaflow::imaging
