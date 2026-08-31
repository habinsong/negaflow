#include "rescue_probe.h"

#include "negaflow/imageio/wic_standard_image_decoder.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/rescue_grade.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cwchar>
#include <filesystem>
#include <iostream>
#include <string_view>
#include <vector>

namespace negaflow::cli {
namespace {

[[nodiscard]] int print_error(const std::string_view code) {
    std::cout << "{\"status\":\"error\",\"code\":\"" << code << "\"}\n";
    return 2;
}

/// 색이 얼마나 벌어져 있는지입니다. 캐스트가 걷히면 이 값이 내려갑니다.
[[nodiscard]] double mean_channel_spread(const negaflow::imaging::WorkingImage& image) {
    double total = 0.0;
    std::size_t count = 0U;
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const negaflow::core::Rgba32F& pixel =
                image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            total += std::max({pixel.red, pixel.green, pixel.blue}) -
                     std::min({pixel.red, pixel.green, pixel.blue});
            ++count;
        }
    }
    return count == 0U ? 0.0 : total / static_cast<double>(count);
}

/// 채널별 평균입니다. 노랗다면 R·G 가 B 보다 높게 나옵니다.
[[nodiscard]] std::array<double, 3> channel_means(
    const negaflow::imaging::WorkingImage& image) {
    std::array<double, 3> total{};
    std::size_t count = 0U;
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const negaflow::core::Rgba32F& pixel =
                image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            total[0] += pixel.red;
            total[1] += pixel.green;
            total[2] += pixel.blue;
            ++count;
        }
    }
    if (count == 0U) {
        return {};
    }
    const double inverse = 1.0 / static_cast<double>(count);
    return {total[0] * inverse, total[1] * inverse, total[2] * inverse};
}

}  // namespace

int run_rescue_probe(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count < 3 || argument_count > 4) {
        return print_error("invalid_argument_count");
    }
    const bool monochrome =
        argument_count == 4 && std::wstring_view{arguments[3]} == L"bw";
    const std::filesystem::path source{arguments[2]};

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = 64U;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        source, {}, {}, decode_control);
    negaflow::imaging::WorkingImage image{};
    if (prepared.decode.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
        prepared.working.status == negaflow::imaging::ScannerToWorkingStatus::ok) {
        image = std::move(prepared.working.image);
    } else {
        const negaflow::imageio::WicStandardImageDecodeResult decoded =
            negaflow::imageio::decode_standard_image_with_wic(source, {}, {}, {});
        if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
            return print_error(
                negaflow::imageio::wic_standard_image_decode_status_name(decoded.status));
        }
        negaflow::imaging::ScannerToWorkingResult working =
            negaflow::imaging::convert_scanner_to_working(decoded.image);
        if (working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return print_error(
                negaflow::imaging::scanner_to_working_status_name(working.status));
        }
        image = std::move(working.image);
    }

    const negaflow::imaging::NegativeFilmType film_type = monochrome
        ? negaflow::imaging::NegativeFilmType::black_and_white
        : negaflow::imaging::NegativeFilmType::color;
    const negaflow::imaging::AutoNegativeBaseResult resolved =
        negaflow::imaging::resolve_auto_negative_base(image, film_type);
    if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
        return print_error(
            negaflow::imaging::auto_negative_base_status_name(resolved.status));
    }

    negaflow::imaging::ManualNegativeDevelopParameters parameters{};
    parameters.dmin = resolved.dmin;
    parameters.film_type = film_type;
    // 베이스를 손으로 넣어 보는 자리입니다. "어두운 것이 베이스 때문인가" 는 다른 베이스로
    // 한 번 현상해 보면 그 자리에서 갈립니다.
    wchar_t* override_text = nullptr;
    std::size_t override_length = 0U;
    if (_wdupenv_s(&override_text, &override_length, L"NEGA_PROBE_DMIN") == 0 &&
        override_text != nullptr) {
        float red = 0.0F;
        float green = 0.0F;
        float blue = 0.0F;
        if (swscanf_s(override_text, L"%f,%f,%f", &red, &green, &blue) == 3 &&
            red > 0.0F && green > 0.0F && blue > 0.0F) {
            parameters.dmin = {red, green, blue};
        }
    }
    std::free(override_text);
    auto developed = negaflow::imaging::develop_manual_negative(
        std::move(image), parameters);
    if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
        return print_error("develop_failed");
    }

    const double before = mean_channel_spread(developed.image);
    const std::array<double, 3> means_before = channel_means(developed.image);

    negaflow::imaging::RescueGradeInfo info{};
    const negaflow::core::KernelStatus status = negaflow::imaging::apply_rescue_grade(
        {
            developed.image.pixels.data(),
            developed.image.pixels.size(),
            developed.image.width,
            developed.image.height,
            developed.image.stride_pixels,
        },
        film_type == negaflow::imaging::NegativeFilmType::color,
        info);
    if (status != negaflow::core::KernelStatus::ok) {
        return print_error(negaflow::core::kernel_status_name(status));
    }
    const double after = mean_channel_spread(developed.image);
    const std::array<double, 3> means_after = channel_means(developed.image);

    std::cout << "{\"status\":\"ok\",\"operation\":\"rescue_probe\""
              << ",\"width\":" << developed.image.width
              << ",\"height\":" << developed.image.height
              << ",\"dmin\":[" << resolved.dmin[0] << ',' << resolved.dmin[1]
              << ',' << resolved.dmin[2] << ']'
              << ",\"dmaxNormalized\":[" << developed.info.dmax_normalized[0] << ','
              << developed.info.dmax_normalized[1] << ','
              << developed.info.dmax_normalized[2] << ']'
              << ",\"applied\":" << (info.applied ? "true" : "false")
              << ",\"eligibleBands\":" << info.eligible_band_count
              << ",\"coveredTiles\":" << info.covered_tile_count
              << ",\"trainingSamples\":" << info.training_sample_count
              << ",\"holdoutSamples\":" << info.holdout_sample_count
              << ",\"spreadBefore\":" << before
              << ",\"spreadAfter\":" << after
              << ",\"meanBefore\":[" << means_before[0] << ',' << means_before[1]
              << ',' << means_before[2] << ']'
              << ",\"meanAfter\":[" << means_after[0] << ',' << means_after[1]
              << ',' << means_after[2] << "]}\n";
    return 0;
}

}  // namespace negaflow::cli
