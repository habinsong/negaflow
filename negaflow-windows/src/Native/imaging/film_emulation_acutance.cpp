#include "negaflow/imaging/film_emulation_acutance.h"

#include "film_emulation_acutance_profiles.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace negaflow::imaging {
namespace {

constexpr double identity_threshold = 1.0e-3;
constexpr std::size_t kernel_width =
    static_cast<std::size_t>(film_emulation_acutance_scratch_rows);

using detail::FilmEmulationAcutanceProfileData;

struct GaussianKernel final {
    std::array<float, kernel_width> weights{};
};

struct AddressRange final {
    std::uintptr_t begin;
    std::uintptr_t end;
};

[[nodiscard]] bool try_make_address_range(
    const void* const address,
    const std::size_t element_count,
    const std::size_t element_size,
    AddressRange& range) noexcept {
    const std::size_t maximum = std::numeric_limits<std::size_t>::max();
    if (element_count > maximum / element_size) {
        return false;
    }
    const std::size_t byte_count = element_count * element_size;
    const std::uintptr_t begin = reinterpret_cast<std::uintptr_t>(address);
    if (byte_count > std::numeric_limits<std::uintptr_t>::max() - begin) {
        return false;
    }
    range = {begin, begin + byte_count};
    return true;
}

[[nodiscard]] bool address_ranges_overlap(
    const AddressRange left,
    const AddressRange right) noexcept {
    return left.begin < right.end && right.begin < left.end;
}

[[nodiscard]] std::size_t image_span_pixel_count(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t stride_pixels) noexcept {
    return (static_cast<std::size_t>(height - 1U) * stride_pixels) + width;
}

[[nodiscard]] negaflow::core::KernelStatus validate_parameters(
    const FilmEmulationAcutanceParameters& parameters) noexcept {
    if (!std::isfinite(parameters.intensity)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }
    return detail::film_emulation_acutance_profile_data(parameters.emulation) ==
                   nullptr
               ? negaflow::core::KernelStatus::invalid_parameter
               : negaflow::core::KernelStatus::ok;
}

[[nodiscard]] GaussianKernel build_kernel(const double sigma) noexcept {
    GaussianKernel kernel{};
    double sum = 0.0;
    const std::int32_t support =
        static_cast<std::int32_t>(film_emulation_acutance_support);
    for (std::int32_t offset = -support; offset <= support; ++offset) {
        const double distance = static_cast<double>(offset);
        const double weight =
            std::exp(-(distance * distance) / (2.0 * sigma * sigma));
        const std::size_t index = static_cast<std::size_t>(offset + support);
        kernel.weights[index] = static_cast<float>(weight);
        sum += weight;
    }
    for (float& weight : kernel.weights) {
        weight = static_cast<float>(static_cast<double>(weight) / sum);
    }
    return kernel;
}

[[nodiscard]] std::uint32_t clamp_coordinate(
    const std::uint32_t center,
    const std::int32_t offset,
    const std::uint32_t upper) noexcept {
    const std::int64_t coordinate =
        static_cast<std::int64_t>(center) + static_cast<std::int64_t>(offset);
    return static_cast<std::uint32_t>(
        std::clamp<std::int64_t>(coordinate, 0, upper));
}

void blur_horizontal_row(
    const negaflow::core::ConstImageView input,
    const std::uint32_t source_row,
    const GaussianKernel& kernel,
    FilmEmulationAcutanceScratchPixel* const destination) noexcept {
    const negaflow::core::Rgba32F* const source =
        input.pixels +
        (static_cast<std::size_t>(source_row) * input.stride_pixels);
    const std::uint32_t upper = input.width - 1U;
    for (std::uint32_t column = 0U; column < input.width; ++column) {
        double red = 0.0;
        double green = 0.0;
        double blue = 0.0;
        const bool is_interior =
            column >= film_emulation_acutance_support &&
            (upper - column) >= film_emulation_acutance_support;
        for (std::size_t index = 0U; index < kernel.weights.size(); ++index) {
            std::uint32_t sample_column = 0U;
            if (is_interior) {
                sample_column =
                    column - film_emulation_acutance_support +
                    static_cast<std::uint32_t>(index);
            } else {
                const std::int32_t offset =
                    static_cast<std::int32_t>(index) -
                    static_cast<std::int32_t>(
                        film_emulation_acutance_support);
                sample_column = clamp_coordinate(column, offset, upper);
            }
            const float weight = kernel.weights[index];
            const negaflow::core::Rgba32F pixel = source[sample_column];
            red += static_cast<double>(pixel.red) * weight;
            green += static_cast<double>(pixel.green) * weight;
            blue += static_cast<double>(pixel.blue) * weight;
        }
        destination[column] = {
            static_cast<float>(red),
            static_cast<float>(green),
            static_cast<float>(blue),
        };
    }
}

void cache_horizontal_row(
    const negaflow::core::ConstImageView input,
    const std::uint32_t source_row,
    const GaussianKernel& kernel,
    const FilmEmulationAcutanceScratch scratch) noexcept {
    const std::size_t slot = static_cast<std::size_t>(
        source_row % film_emulation_acutance_scratch_rows);
    FilmEmulationAcutanceScratchPixel* const destination =
        scratch.pixels + (slot * static_cast<std::size_t>(input.width));
    blur_horizontal_row(input, source_row, kernel, destination);
}

void copy_active_pixels(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output) noexcept {
    for (std::uint32_t row = 0U; row < input.height; ++row) {
        const std::size_t input_offset =
            static_cast<std::size_t>(row) * input.stride_pixels;
        const std::size_t output_offset =
            static_cast<std::size_t>(row) * output.stride_pixels;
        std::copy_n(
            input.pixels + input_offset,
            input.width,
            output.pixels + output_offset);
    }
}

} // namespace

bool valid_film_emulation_acutance_parameters(
    const FilmEmulationAcutanceParameters& parameters) noexcept {
    return validate_parameters(parameters) == negaflow::core::KernelStatus::ok;
}

bool try_get_film_emulation_acutance_profile(
    const FilmEmulation emulation,
    FilmEmulationAcutanceProfile& profile) noexcept {
    const FilmEmulationAcutanceProfileData* const data =
        detail::film_emulation_acutance_profile_data(emulation);
    if (data == nullptr) {
        return false;
    }
    profile = {data->radius, data->intensity};
    return true;
}

double film_emulation_acutance_amount(
    const FilmEmulationAcutanceParameters& parameters) noexcept {
    const FilmEmulationAcutanceProfileData* const profile =
        detail::film_emulation_acutance_profile_data(parameters.emulation);
    if (profile == nullptr || !std::isfinite(parameters.intensity)) {
        return 0.0;
    }
    return profile->intensity * std::clamp(parameters.intensity, 0.0, 1.0);
}

bool has_film_emulation_acutance_change(
    const FilmEmulationAcutanceParameters& parameters) noexcept {
    const FilmEmulationAcutanceProfileData* const profile =
        detail::film_emulation_acutance_profile_data(parameters.emulation);
    if (profile == nullptr || parameters.emulation == FilmEmulation::none ||
        !std::isfinite(parameters.intensity)) {
        return false;
    }
    return profile->intensity > identity_threshold &&
           std::clamp(parameters.intensity, 0.0, 1.0) > identity_threshold;
}

FilmEmulationAcutanceSetup prepare_film_emulation_acutance(
    const FilmEmulationAcutanceParameters& parameters) noexcept {
    FilmEmulationAcutanceSetup setup{};
    if (!has_film_emulation_acutance_change(parameters)) {
        return setup;
    }
    const FilmEmulationAcutanceProfileData* const profile =
        detail::film_emulation_acutance_profile_data(parameters.emulation);
    if (profile == nullptr) {
        return setup;
    }
    const GaussianKernel kernel = build_kernel(profile->gaussian_sigma);
    for (std::size_t index = 0U; index < kernel_width; ++index) {
        setup.weights[index] = kernel.weights[index];
    }
    setup.amount = static_cast<float>(film_emulation_acutance_amount(parameters));
    setup.applied = true;
    return setup;
}

std::size_t film_emulation_acutance_scratch_pixel_count(
    const std::uint32_t width) noexcept {
    constexpr std::size_t rows =
        static_cast<std::size_t>(film_emulation_acutance_scratch_rows);
    if (static_cast<std::size_t>(width) >
        std::numeric_limits<std::size_t>::max() / rows) {
        return 0U;
    }
    return static_cast<std::size_t>(width) * rows;
}

negaflow::core::KernelStatus apply_film_emulation_acutance(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const FilmEmulationAcutanceParameters& parameters,
    const FilmEmulationAcutanceScratch scratch) noexcept {
    const negaflow::core::KernelStatus parameter_status =
        validate_parameters(parameters);
    if (parameter_status != negaflow::core::KernelStatus::ok) {
        return parameter_status;
    }
    const negaflow::core::KernelStatus compatibility_status =
        negaflow::core::validate_compatible_views(input, output);
    if (compatibility_status != negaflow::core::KernelStatus::ok) {
        return compatibility_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels(input);
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }
    if (input.pixels == output.pixels &&
        input.stride_pixels != output.stride_pixels) {
        return negaflow::core::KernelStatus::invalid_argument;
    }
    AddressRange input_range{};
    AddressRange output_range{};
    if (!try_make_address_range(
            input.pixels,
            image_span_pixel_count(
                input.width, input.height, input.stride_pixels),
            sizeof(*input.pixels),
            input_range) ||
        !try_make_address_range(
            output.pixels,
            image_span_pixel_count(
                output.width, output.height, output.stride_pixels),
            sizeof(*output.pixels),
            output_range)) {
        return negaflow::core::KernelStatus::size_overflow;
    }
    const bool exact_in_place =
        input.pixels == output.pixels &&
        input.stride_pixels == output.stride_pixels;
    if (!exact_in_place && address_ranges_overlap(input_range, output_range)) {
        return negaflow::core::KernelStatus::invalid_argument;
    }
    if (!has_film_emulation_acutance_change(parameters)) {
        copy_active_pixels(input, output);
        return negaflow::core::KernelStatus::ok;
    }

    const std::size_t required_scratch =
        film_emulation_acutance_scratch_pixel_count(input.width);
    if (required_scratch == 0U) {
        return negaflow::core::KernelStatus::size_overflow;
    }
    if (scratch.pixels == nullptr) {
        return negaflow::core::KernelStatus::invalid_argument;
    }
    if (scratch.pixel_capacity < required_scratch) {
        return negaflow::core::KernelStatus::buffer_too_small;
    }
    AddressRange scratch_range{};
    if (!try_make_address_range(
            scratch.pixels,
            required_scratch,
            sizeof(*scratch.pixels),
            scratch_range)) {
        return negaflow::core::KernelStatus::size_overflow;
    }
    if (address_ranges_overlap(scratch_range, input_range) ||
        address_ranges_overlap(scratch_range, output_range)) {
        return negaflow::core::KernelStatus::invalid_argument;
    }

    const FilmEmulationAcutanceProfileData* const profile =
        detail::film_emulation_acutance_profile_data(parameters.emulation);
    if (profile == nullptr) {
        return negaflow::core::KernelStatus::invalid_parameter;
    }
    // **근사입니다.** CPU 는 두 패스를 `double` 로 누적하고 GPU 는 float 입니다.
    // `ApproximateAcceleratorScope` 안에서만 돕니다 — 내보내기·골든은 CPU 그대로입니다.
    if (exact_in_place && approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->film_emulation_acutance != nullptr &&
            output.stride_pixels <= 0xFFFFFFFFULL) {
            const FilmEmulationAcutanceSetup setup =
                prepare_film_emulation_acutance(parameters);
            if (setup.applied &&
                table->film_emulation_acutance(
                    reinterpret_cast<float*>(output.pixels),
                    output.width,
                    output.height,
                    static_cast<std::uint32_t>(output.stride_pixels),
                    &setup)) {
                return negaflow::core::KernelStatus::ok;
            }
        }
    }

    const GaussianKernel kernel = build_kernel(profile->gaussian_sigma);
    const double amount = film_emulation_acutance_amount(parameters);
    const std::uint32_t support = film_emulation_acutance_support;
    const std::uint32_t initial_last_row =
        std::min(input.height - 1U, support);
    for (std::uint32_t source_row = 0U; source_row <= initial_last_row;
         ++source_row) {
        cache_horizontal_row(input, source_row, kernel, scratch);
    }

    const std::int32_t signed_support = static_cast<std::int32_t>(support);
    for (std::uint32_t row = 0U; row < input.height; ++row) {
        if (row > 0U) {
            const std::uint32_t prior_last = clamp_coordinate(
                row - 1U,
                signed_support,
                input.height - 1U);
            const std::uint32_t next_last = clamp_coordinate(
                row,
                signed_support,
                input.height - 1U);
            if (next_last != prior_last) {
                cache_horizontal_row(input, next_last, kernel, scratch);
            }
        }

        const std::size_t input_offset =
            static_cast<std::size_t>(row) * input.stride_pixels;
        const std::size_t output_offset =
            static_cast<std::size_t>(row) * output.stride_pixels;
        for (std::uint32_t column = 0U; column < input.width; ++column) {
            double red = 0.0;
            double green = 0.0;
            double blue = 0.0;
            for (std::int32_t offset = -signed_support;
                 offset <= signed_support;
                 ++offset) {
                const std::uint32_t sample_row = clamp_coordinate(
                    row,
                    offset,
                    input.height - 1U);
                const std::size_t slot = static_cast<std::size_t>(
                    sample_row % film_emulation_acutance_scratch_rows);
                const FilmEmulationAcutanceScratchPixel pixel =
                    scratch.pixels[
                        (slot * static_cast<std::size_t>(input.width)) + column];
                const float weight = kernel.weights[static_cast<std::size_t>(
                    offset + signed_support)];
                red += static_cast<double>(pixel.red) * weight;
                green += static_cast<double>(pixel.green) * weight;
                blue += static_cast<double>(pixel.blue) * weight;
            }

            const negaflow::core::Rgba32F source =
                input.pixels[input_offset + column];
            const negaflow::core::Rgba32F result{
                static_cast<float>(
                    source.red + (amount * (source.red - red))),
                static_cast<float>(
                    source.green + (amount * (source.green - green))),
                static_cast<float>(
                    source.blue + (amount * (source.blue - blue))),
                source.alpha,
            };
            if (!std::isfinite(result.red) || !std::isfinite(result.green) ||
                !std::isfinite(result.blue)) {
                return negaflow::core::KernelStatus::non_finite_output;
            }
            output.pixels[output_offset + column] = result;
        }
    }
    return negaflow::core::KernelStatus::ok;
}

} // namespace negaflow::imaging
