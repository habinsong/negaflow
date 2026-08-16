#include "negaflow_abi.h"
#include "negaflow/imageio/image_content_hash.h"
#include "negaflow/imageio/wic_tiff_decoder.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
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
                (L"negaflow-task1-golden-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "task1 temporary output directory is created");
    }

    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;

    ~TempDirectory() {
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_{};
};

struct Case final {
    const wchar_t* name;
    const wchar_t* output;
    const char* expected_sha256;
    std::uint32_t target;
    std::uint32_t output_color_space;
    const wchar_t* scanner_profile_id;
};

constexpr std::string_view task1_source_sha256 =
    "9e3d0daf2537273a299d5a77ed17c2d3c617131e59cc6afa9d90daf867d1a198";
constexpr int maximum_median_difference = 96;

[[nodiscard]] bool has_sha256(
    const std::filesystem::path& path,
    const std::string_view expected_sha256,
    const char* const description) {
    negaflow::imageio::ImageContentHashControl control{};
    control.mode = negaflow::imageio::ImageContentHashMode::sha256;
    const auto result = negaflow::imageio::hash_image_content(path, control);
    const bool matches = result.status == negaflow::imageio::ImageContentHashStatus::ok &&
        negaflow::imageio::image_sha256_hex(result.sha256) == expected_sha256;
    expect(matches, description);
    return matches;
}

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
    v8.film_type = NF_FILM_TYPE_COLOR;
    v8.base_estimation_mode = NF_BASE_ESTIMATION_AUTO;
    v8.film_look_source_kind = NF_DEVELOP_SOURCE_FILM_SCAN;
    v8.film_emulation_intensity = 0.5;
    v8.rows_per_copy = 64U;
    v8.color_grading_blending = 0.5F;
    v9.noise_reduction_luma = 0.5F;
    v9.noise_reduction_chroma = 0.5F;
    v9.noise_reduction_dark_tone = 0.5F;
    v9.noise_reduction_detail = 0.5F;
    v9.noise_reduction_film_profile = NF_FILM_SCAN_DENOISE_COLOR_NEGATIVE;
    v11.crop_width = 1.0;
    v11.crop_height = 1.0;
    v15.develop_target = entry.target;
    v16.scanner_profile_id = entry.scanner_profile_id;
    v17.film_polarity = NF_FILM_POLARITY_NEGATIVE;
    v30.tiff_compression = NF_TIFF_COMPRESSION_NONE;
    request.v31.output_bit_depth = 16U;
    request.output_color_space = entry.output_color_space;
    return request;
}

struct ChannelDifference final {
    int median{0};
    int maximum_absolute{0};
    std::uint16_t maximum_actual{0U};
    std::uint16_t maximum_macos{0U};
};

[[nodiscard]] ChannelDifference channel_difference(
    const std::vector<std::uint16_t>& actual,
    const std::vector<std::uint16_t>& expected,
    const std::size_t channel) {
    std::vector<int> differences{};
    differences.reserve(actual.size() / 3U);
    ChannelDifference result{};
    for (std::size_t index = channel; index < actual.size(); index += 3U) {
        const int difference =
            static_cast<int>(actual[index]) - static_cast<int>(expected[index]);
        differences.push_back(difference);
        result.maximum_absolute = std::max(result.maximum_absolute, std::abs(difference));
        result.maximum_actual = std::max(result.maximum_actual, actual[index]);
        result.maximum_macos = std::max(result.maximum_macos, expected[index]);
    }
    const auto middle = differences.begin() +
        static_cast<std::ptrdiff_t>(differences.size() / 2U);
    std::nth_element(differences.begin(), middle, differences.end());
    result.median = *middle;
    return result;
}

void run_case(
    const std::filesystem::path& source,
    const std::filesystem::path& golden_root,
    const TempDirectory& temporary,
    const Case& entry) {
    const std::filesystem::path expected_path = golden_root / entry.output;
    if (!has_sha256(
            expected_path,
            entry.expected_sha256,
            "macOS Task 1 output hash matches its manifest")) {
        return;
    }
    const std::filesystem::path actual_path = temporary.path() /
        (std::wstring{entry.name} + L".tif");
    const auto expected = negaflow::imageio::decode_tiff_with_wic(expected_path);
    expect(
        expected.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            expected.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16,
        "macOS Task 1 expected TIFF decodes as RGB16");
    if (expected.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
        return;
    }

    const nf_develop_export_request_v32 request =
        make_request(source, actual_path, entry);
    nf_develop_run_state_v1 state = make_run_state();
    nf_develop_export_result_v3 result = make_result();
    const nf_status_t status = nf_develop_export_v32(&request, &state, &result);
    expect(
        status == NF_STATUS_OK && result.succeeded == 1U,
        "Windows Task 1 Develop export completes");
    if (status != NF_STATUS_OK || result.succeeded != 1U) {
        std::cerr << "  export failed: " << std::filesystem::path(entry.output).string()
                  << " stage=" << result.failed_stage
                  << " name=" << result.failure_name << '\n';
        return;
    }

    const auto actual = negaflow::imageio::decode_tiff_with_wic(actual_path);
    expect(
        actual.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            actual.image.width == expected.image.width &&
            actual.image.height == expected.image.height &&
            actual.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16 &&
            actual.image.samples.size() == expected.image.samples.size(),
        "Windows Task 1 TIFF has the macOS golden layout and dimensions");
    if (actual.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        actual.image.samples.size() != expected.image.samples.size()) {
        return;
    }

    const ChannelDifference red =
        channel_difference(actual.image.samples, expected.image.samples, 0U);
    const ChannelDifference green =
        channel_difference(actual.image.samples, expected.image.samples, 1U);
    const ChannelDifference blue =
        channel_difference(actual.image.samples, expected.image.samples, 2U);
    std::cout << std::filesystem::path(entry.name).string()
              << " median_delta_rgb=[" << red.median << ',' << green.median << ','
              << blue.median << "] applied_dmin_rgb=[" << result.applied_dmin[0] << ','
              << result.applied_dmin[1] << ',' << result.applied_dmin[2]
              << "] base_source=" << result.base_source
              << " max_abs_delta_rgb=[" << red.maximum_absolute << ','
              << green.maximum_absolute << ',' << blue.maximum_absolute
              << "] max_actual_rgb=[" << red.maximum_actual << ','
              << green.maximum_actual << ',' << blue.maximum_actual
              << "] max_macos_rgb=[" << red.maximum_macos << ','
              << green.maximum_macos << ',' << blue.maximum_macos << "]\n";
    expect(
        std::abs(red.median) <= maximum_median_difference &&
            std::abs(green.median) <= maximum_median_difference &&
            std::abs(blue.median) <= maximum_median_difference,
        "Task 1 RGB16 median delta stays within the 8-bit 0.4-level budget");
}

void measure_task1(
    const std::filesystem::path& source,
    const std::filesystem::path& golden_root,
    const std::string_view selected_case) {
    constexpr std::array<Case, 8U> cases{{
        {L"a-default-main-srgb", L"a-default-main-srgb.tif", "a3a17e736645d9ddb6340c7be5867f9f0580bd74d2cbec23ba1c9061654488e7", NF_DEVELOP_TARGET_MAIN, 0U, nullptr},
        {L"b-main-scannerprofile-portra400-srgb", L"b-main-scannerprofile-portra400-srgb.tif", "cbec99382d4d330f4042c9a1fcac986c2efad59383c60823f5d6872d48ea552e", NF_DEVELOP_TARGET_MAIN, 0U, L"noritsu__color-nega__kodak-portra-400"},
        {L"c-target-hs-srgb", L"c-target-hs-srgb.tif", "8170b2aadb07195bf2ec42c2cdd0f38cef95596bd0ac91981b713ba7c973746f", NF_DEVELOP_TARGET_NORITSU, 0U, nullptr},
        {L"c-target-sp-srgb", L"c-target-sp-srgb.tif", "5331e970ec72ff03410cda371bbad7cb97835316d9cb51feaf03c000ffe3f23a", NF_DEVELOP_TARGET_SP3000, 0U, nullptr},
        {L"c-target-f135-srgb", L"c-target-f135-srgb.tif", "8296c4990a0731a8f1cf53e3482b907edfdfa75a1419cf40b9b8bf9d18a8f172", NF_DEVELOP_TARGET_F135, 0U, nullptr},
        {L"c-target-hr-srgb", L"c-target-hr-srgb.tif", "ae67c78189aebd633153d1cc2ea4e13648867f8a60028cd0477b89e60e9cf877", NF_DEVELOP_TARGET_HR, 0U, nullptr},
        {L"d-main-displayp3", L"d-main-displayp3.tif", "230a3c85406e9f2da65476defd846f96f59b731e0f6fe6dd96366706b21414af", NF_DEVELOP_TARGET_MAIN, 1U, nullptr},
        {L"d-main-adobergb", L"d-main-adobergb.tif", "3915583c65a48e097302129afb3e310be2ecdcf56e328d1dd007fe1910c4c849", NF_DEVELOP_TARGET_MAIN, 2U, nullptr},
    }};
    const TempDirectory temporary{};
    const std::wstring selected_case_wide{selected_case.begin(), selected_case.end()};
    bool selected_case_found = selected_case_wide.empty();
    for (const Case& entry : cases) {
        if (!selected_case_wide.empty() && selected_case_wide != entry.name) {
            continue;
        }
        selected_case_found = true;
        run_case(source, golden_root, temporary, entry);
    }
    expect(selected_case_found, "Task 1 optional case filter names a declared golden case");
}

}  // namespace

int main(const int argc, char** argv) {
    expect(
        argc == 3 || argc == 4,
        "Task 1 receives source TIFF, macOS golden directory, and optional case filter");
    if (argc == 3 || argc == 4) {
        const std::filesystem::path source{argv[1]};
        const std::filesystem::path golden_root{argv[2]};
        expect(std::filesystem::is_regular_file(source), "Task 1 source TIFF exists");
        expect(std::filesystem::is_directory(golden_root), "Task 1 golden directory exists");
        if (std::filesystem::is_regular_file(source) &&
            std::filesystem::is_directory(golden_root)) {
            if (has_sha256(source, task1_source_sha256, "Task 1 source hash matches the manifest")) {
                measure_task1(
                    source,
                    golden_root,
                    argc == 4 ? std::string_view{argv[3]} : std::string_view{});
            }
        }
    }
    return failures == 0 ? 0 : 1;
}
