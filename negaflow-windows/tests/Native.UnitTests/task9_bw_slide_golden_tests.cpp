#include "negaflow_abi.h"
#include "negaflow/imageio/wic_tiff_decoder.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-task9-golden-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "task9 temporary output directory is created");
    }

    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;

    ~TempDirectory() {
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept { return path_; }

private:
    std::filesystem::path path_{};
};

[[nodiscard]] nf_develop_export_result_v3 make_result() {
    nf_develop_export_result_v3 result{};
    result.struct_size = static_cast<std::uint32_t>(sizeof(result));
    return result;
}

[[nodiscard]] nf_develop_run_state_v1 make_run_state() {
    nf_develop_run_state_v1 state{};
    state.struct_size = static_cast<std::uint32_t>(sizeof(state));
    return state;
}

struct Case final {
    const wchar_t* directory;
    const wchar_t* output;
    std::uint32_t film_type;
    std::uint32_t polarity;
    std::uint32_t target;
    std::uint32_t output_color_space;
    const wchar_t* scanner_profile_id;
};

[[nodiscard]] nf_develop_export_request_v32 make_request(
    const std::filesystem::path& source,
    const std::filesystem::path& destination,
    const Case& entry) {
    nf_develop_export_request_v32 request;
    std::memset(&request, 0, sizeof(request));
    auto& v30 = request.v31.v30;
    auto& v29 = v30.v29;
    auto& v28 = v29.v28;
    auto& v27 = v28.v27;
    auto& v26 = v27.v26;
    auto& v25 = v26.v25;
    auto& v24 = v25.v24;
    auto& v21 = v24.v21;
    auto& v20 = v21.v20;
    auto& v19 = v20.v19;
    auto& v18 = v19.v18;
    auto& v17 = v18.v17;
    auto& v16 = v17.v16;
    auto& v15 = v16.v15;
    auto& v14 = v15.v14;
    auto& v13 = v14.v13;
    auto& v12 = v13.v12;
    auto& v11 = v12.v11;
    auto& v9 = v11.v10.v9;
    auto& v8 = v9.v8;
    v8.struct_size = static_cast<std::uint32_t>(sizeof(request));
    v8.source_path = source.c_str();
    v8.destination_path = destination.c_str();
    v8.output_format = NF_EXPORT_FORMAT_TIFF16;
    v8.film_type = entry.film_type;
    v8.base_estimation_mode = NF_BASE_ESTIMATION_AUTO;
    v8.film_look_source_kind = NF_DEVELOP_SOURCE_FILM_SCAN;
    v8.film_emulation_intensity = 0.5;
    v8.rows_per_copy = 64U;
    v8.color_grading_blending = 0.5F;
    v9.noise_reduction_luma = 0.5F;
    v9.noise_reduction_chroma = 0.5F;
    v9.noise_reduction_dark_tone = 0.5F;
    v9.noise_reduction_detail = 0.5F;
    v9.noise_reduction_film_profile = entry.film_type == NF_FILM_TYPE_BLACK_AND_WHITE
        ? NF_FILM_SCAN_DENOISE_BLACK_AND_WHITE_NEGATIVE
        : (entry.polarity == NF_FILM_POLARITY_POSITIVE
            ? NF_FILM_SCAN_DENOISE_COLOR_POSITIVE
            : NF_FILM_SCAN_DENOISE_COLOR_NEGATIVE);
    v11.crop_width = 1.0;
    v11.crop_height = 1.0;
    v17.film_polarity = entry.polarity;
    v15.develop_target = entry.target;
    v16.scanner_profile_id = entry.scanner_profile_id;
    v30.tiff_compression = NF_TIFF_COMPRESSION_NONE;
    request.v31.output_bit_depth = 16U;
    request.output_color_space = entry.output_color_space;
    return request;
}

struct ChannelDifference final {
    int median{0};
    int maximum_absolute{0};
    std::uint16_t maximum_actual{0U};
    std::uint16_t maximum_expected{0U};
};

[[nodiscard]] ChannelDifference channel_difference(
    const std::vector<std::uint16_t>& actual,
    const std::vector<std::uint16_t>& expected,
    const std::size_t channel) {
    std::vector<int> differences{};
    differences.reserve(actual.size() / 3U);
    ChannelDifference result{};
    for (std::size_t index = channel; index < actual.size(); index += 3U) {
        const int difference = static_cast<int>(actual[index]) - static_cast<int>(expected[index]);
        differences.push_back(difference);
        result.maximum_absolute = std::max(result.maximum_absolute, std::abs(difference));
        result.maximum_actual = std::max(result.maximum_actual, actual[index]);
        result.maximum_expected = std::max(result.maximum_expected, expected[index]);
    }
    const auto middle = differences.begin() + static_cast<std::ptrdiff_t>(differences.size() / 2U);
    std::nth_element(differences.begin(), middle, differences.end());
    result.median = *middle;
    return result;
}

void run_case(
    const std::filesystem::path& root,
    const TempDirectory& temporary,
    const Case& entry) {
    const std::filesystem::path directory = root / entry.directory;
    const std::filesystem::path source = directory / L"source.tiff";
    const std::filesystem::path expected_path = directory / entry.output;
    const std::filesystem::path actual_path = temporary.path() /
        (std::wstring{entry.directory} + L"-" + entry.output);
    const auto expected = negaflow::imageio::decode_tiff_with_wic(expected_path);
    expect(
        expected.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            expected.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16,
        "macOS task9 expected TIFF decodes as RGB16");
    if (expected.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        return;
    }

    const nf_develop_export_request_v32 request = make_request(source, actual_path, entry);
    nf_develop_run_state_v1 state = make_run_state();
    nf_develop_export_result_v3 result = make_result();
    const nf_status_t status = nf_develop_export_v32(&request, &state, &result);
    expect(
        status == NF_STATUS_OK && result.succeeded == 1U,
        "Windows task9 Develop export completes");
    if (status != NF_STATUS_OK || result.succeeded != 1U) {
        std::cerr << "  export failed: "
                  << std::filesystem::path(entry.output).string() << " stage="
                  << result.failed_stage << " name=" << result.failure_name << '\n';
        return;
    }

    const auto actual = negaflow::imageio::decode_tiff_with_wic(actual_path);
    expect(
        actual.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            actual.image.width == expected.image.width &&
            actual.image.height == expected.image.height &&
            actual.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16 &&
            actual.image.samples.size() == expected.image.samples.size(),
        "Windows task9 TIFF decodes with the macOS golden dimensions and layout");
    if (actual.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        actual.image.samples.size() != expected.image.samples.size()) {
        return;
    }

    const ChannelDifference red = channel_difference(actual.image.samples, expected.image.samples, 0U);
    const ChannelDifference green = channel_difference(actual.image.samples, expected.image.samples, 1U);
    const ChannelDifference blue = channel_difference(actual.image.samples, expected.image.samples, 2U);
    if (entry.polarity == NF_FILM_POLARITY_POSITIVE) {
        expect(
            std::abs(red.median) <= 32 && std::abs(green.median) <= 32 &&
                std::abs(blue.median) <= 32,
            "color-positive task9 median channel differences stay within 32 RGB16 codes");
    }
    std::cout << std::filesystem::path(entry.directory).string() << '/'
              << std::filesystem::path(entry.output).string()
              << " median_delta_rgb=[" << red.median << ',' << green.median << ',' << blue.median
              << "] applied_dmin_rgb=[" << result.applied_dmin[0] << ',' << result.applied_dmin[1] << ','
              << result.applied_dmin[2] << "] base_source=" << result.base_source
              << " max_abs_delta_rgb=[" << red.maximum_absolute << ',' << green.maximum_absolute << ','
              << blue.maximum_absolute
              << "] max_actual_rgb=[" << red.maximum_actual << ',' << green.maximum_actual << ',' << blue.maximum_actual
              << "] max_macos_rgb=[" << red.maximum_expected << ',' << green.maximum_expected << ',' << blue.maximum_expected
              << "]\n";
}

void test_task9_goldens(const std::filesystem::path& root, const std::string_view selected_case) {
    constexpr std::array<Case, 15U> cases{{
        {L"bw-negative", L"a-default-main-srgb.tif", NF_FILM_TYPE_BLACK_AND_WHITE, NF_FILM_POLARITY_NEGATIVE, NF_DEVELOP_TARGET_MAIN, 0U, nullptr},
        {L"bw-negative", L"c-target-hs-srgb.tif", NF_FILM_TYPE_BLACK_AND_WHITE, NF_FILM_POLARITY_NEGATIVE, NF_DEVELOP_TARGET_NORITSU, 0U, nullptr},
        {L"bw-negative", L"c-target-sp-srgb.tif", NF_FILM_TYPE_BLACK_AND_WHITE, NF_FILM_POLARITY_NEGATIVE, NF_DEVELOP_TARGET_SP3000, 0U, nullptr},
        {L"bw-negative", L"c-target-f135-srgb.tif", NF_FILM_TYPE_BLACK_AND_WHITE, NF_FILM_POLARITY_NEGATIVE, NF_DEVELOP_TARGET_F135, 0U, nullptr},
        {L"bw-negative", L"c-target-hr-srgb.tif", NF_FILM_TYPE_BLACK_AND_WHITE, NF_FILM_POLARITY_NEGATIVE, NF_DEVELOP_TARGET_HR, 0U, nullptr},
        {L"bw-negative", L"d-main-displayp3.tif", NF_FILM_TYPE_BLACK_AND_WHITE, NF_FILM_POLARITY_NEGATIVE, NF_DEVELOP_TARGET_MAIN, 1U, nullptr},
        {L"bw-negative", L"d-main-adobergb.tif", NF_FILM_TYPE_BLACK_AND_WHITE, NF_FILM_POLARITY_NEGATIVE, NF_DEVELOP_TARGET_MAIN, 2U, nullptr},
        {L"color-positive-slide", L"a-default-main-srgb.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_MAIN, 0U, nullptr},
        {L"color-positive-slide", L"b-main-scannerprofile-srgb.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_MAIN, 0U, L"noritsu__color-slide__kodak-ektachrome-100"},
        {L"color-positive-slide", L"c-target-hs-srgb.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_NORITSU, 0U, nullptr},
        {L"color-positive-slide", L"c-target-sp-srgb.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_SP3000, 0U, nullptr},
        {L"color-positive-slide", L"c-target-f135-srgb.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_F135, 0U, nullptr},
        {L"color-positive-slide", L"c-target-hr-srgb.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_HR, 0U, nullptr},
        {L"color-positive-slide", L"d-main-displayp3.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_MAIN, 1U, nullptr},
        {L"color-positive-slide", L"d-main-adobergb.tif", NF_FILM_TYPE_COLOR, NF_FILM_POLARITY_POSITIVE, NF_DEVELOP_TARGET_MAIN, 2U, nullptr},
    }};
    const TempDirectory temporary{};
    const std::wstring selected_case_wide{selected_case.begin(), selected_case.end()};
    for (const Case& entry : cases) {
        const std::wstring case_name = std::wstring{entry.directory} + L"/" + entry.output;
        if (!selected_case_wide.empty() && selected_case_wide != case_name) {
            continue;
        }
        run_case(root, temporary, entry);
    }
}

}  // namespace

int main(const int argc, char** argv) {
    expect(argc == 2 || argc == 3, "task9 receives a macOS golden directory and optional case filter");
    if (argc == 2 || argc == 3) {
        test_task9_goldens(argv[1], argc == 3 ? std::string_view{argv[2]} : std::string_view{});
    }
    return failures == 0 ? 0 : 1;
}
