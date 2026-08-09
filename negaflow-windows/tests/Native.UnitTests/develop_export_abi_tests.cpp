#include "negaflow_abi.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] nf_develop_export_request_v1 make_request(
    const wchar_t* const source,
    const wchar_t* const destination) {
    nf_develop_export_request_v1 request{};
    request.struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.source_path = source;
    request.destination_path = destination;
    request.output_format = NF_EXPORT_FORMAT_PNG16;
    request.film_type = NF_FILM_TYPE_COLOR;
    request.dmin[0] = 0.25F;
    request.dmin[1] = 0.25F;
    request.dmin[2] = 0.25F;
    request.film_look_source_kind = NF_DEVELOP_SOURCE_FILM_SCAN;
    request.film_emulation = 0U;
    request.film_emulation_intensity = 0.5;
    request.rows_per_copy = 64U;
    return request;
}

[[nodiscard]] nf_develop_export_result_v1 make_result() {
    nf_develop_export_result_v1 result{};
    result.struct_size = static_cast<std::uint32_t>(sizeof(result));
    return result;
}

[[nodiscard]] nf_develop_export_request_v2 make_request_v2(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v2 request{};
    request.struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.source_path = source;
    request.destination_path = destination;
    request.output_format = NF_EXPORT_FORMAT_PNG16;
    request.film_type = NF_FILM_TYPE_COLOR;
    request.base_estimation_mode = base_mode;
    request.film_look_source_kind = NF_DEVELOP_SOURCE_FILM_SCAN;
    request.film_emulation = 0U;
    request.film_emulation_intensity = 0.5;
    request.rows_per_copy = 64U;
    return request;
}

[[nodiscard]] nf_develop_export_result_v2 make_result_v2() {
    nf_develop_export_result_v2 result{};
    result.struct_size = static_cast<std::uint32_t>(sizeof(result));
    return result;
}

[[nodiscard]] nf_develop_export_request_v3 make_request_v3(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v3 request{};
    request.struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.source_path = source;
    request.destination_path = destination;
    request.output_format = NF_EXPORT_FORMAT_PNG16;
    request.film_type = NF_FILM_TYPE_COLOR;
    request.base_estimation_mode = base_mode;
    request.film_look_source_kind = NF_DEVELOP_SOURCE_FILM_SCAN;
    request.film_emulation = 0U;
    request.film_emulation_intensity = 0.5;
    request.rows_per_copy = 64U;
    return request;
}

[[nodiscard]] nf_develop_export_request_v4 make_request_v4(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v4 request{};
    request.struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.source_path = source;
    request.destination_path = destination;
    request.output_format = NF_EXPORT_FORMAT_PNG16;
    request.film_type = NF_FILM_TYPE_COLOR;
    request.base_estimation_mode = base_mode;
    request.film_look_source_kind = NF_DEVELOP_SOURCE_FILM_SCAN;
    request.film_emulation = 0U;
    request.film_emulation_intensity = 0.5;
    request.rows_per_copy = 64U;
    return request;
}

void test_argument_contract() {
    nf_develop_export_request_v1 request = make_request(L"a.tif", L"b.png");
    nf_develop_export_result_v1 result = make_result();

    expect(
        nf_develop_export_v1(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "a null request is rejected");
    expect(
        nf_develop_export_v1(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "a null result is rejected");

    nf_develop_export_request_v1 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v1(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized request struct is rejected");

    nf_develop_export_result_v1 small_result = make_result();
    small_result.struct_size = 4U;
    expect(
        nf_develop_export_v1(&request, &small_result) == NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized result struct is rejected");

    // A larger caller struct is the forward-compatible case and must be accepted.
    nf_develop_export_result_v1 large_result = make_result();
    large_result.struct_size = static_cast<std::uint32_t>(sizeof(large_result)) + 64U;
    expect(
        nf_develop_export_v1(&request, &large_result) == NF_STATUS_OK,
        "an oversized result struct is accepted");
    expect(large_result.struct_size ==
        static_cast<std::uint32_t>(sizeof(large_result)) + 64U,
        "the caller's declared struct size is preserved");
}

void expect_rejected(
    nf_develop_export_request_v1& request,
    const char* const expected_name,
    const char* const message) {
    nf_develop_export_result_v1 result = make_result();
    const nf_status_t status = nf_develop_export_v1(&request, &result);
    expect(status == NF_STATUS_OK, message);
    expect(result.succeeded == 0U, message);
    expect(
        result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION,
        message);
    expect(std::strcmp(result.failure_name, expected_name) == 0, message);
}

void test_request_validation() {
    nf_develop_export_request_v1 missing_source = make_request(nullptr, L"b.png");
    expect_rejected(missing_source, "missing_path", "a null source path is refused");

    nf_develop_export_request_v1 missing_destination = make_request(L"a.tif", nullptr);
    expect_rejected(
        missing_destination, "missing_path", "a null destination path is refused");

    nf_develop_export_request_v1 unknown_format = make_request(L"a.tif", L"b.png");
    unknown_format.output_format = 99U;
    expect_rejected(
        unknown_format, "unknown_export_format", "an unknown output format is refused");

    nf_develop_export_request_v1 unknown_film = make_request(L"a.tif", L"b.png");
    unknown_film.film_type = 99U;
    expect_rejected(
        unknown_film, "unknown_film_type", "an unknown film type is refused");

    nf_develop_export_request_v1 unknown_source_kind = make_request(L"a.tif", L"b.png");
    unknown_source_kind.film_look_source_kind = 99U;
    expect_rejected(
        unknown_source_kind,
        "unknown_film_look_source_kind",
        "an unknown Film Look source kind is refused");

    nf_develop_export_request_v1 unknown_emulation = make_request(L"a.tif", L"b.png");
    unknown_emulation.film_emulation = 99U;
    expect_rejected(
        unknown_emulation,
        "unknown_film_emulation",
        "an unknown film emulation is refused");

    // The rendered-digital graph is not implemented. It must refuse rather than
    // develop a negative anyway.
    nf_develop_export_request_v1 digital = make_request(L"a.tif", L"b.png");
    digital.film_look_source_kind = NF_DEVELOP_SOURCE_RENDERED_DIGITAL;
    expect_rejected(
        digital,
        "negative_develop_requires_film_scan_source",
        "a rendered-digital source is refused for a negative develop");

    nf_develop_export_request_v1 zero_rows = make_request(L"a.tif", L"b.png");
    zero_rows.rows_per_copy = 0U;
    expect_rejected(
        zero_rows, "invalid_rows_per_copy", "a zero row-per-copy control is refused");
}

void test_v2_contract() {
    expect(sizeof(nf_develop_export_request_v2) == 96U, "v2 request layout is fixed");
    expect(sizeof(nf_develop_export_result_v2) == 152U, "v2 result layout is fixed");

    nf_develop_export_request_v2 request = make_request_v2(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v2(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v2 null request is rejected");
    expect(
        nf_develop_export_v2(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v2 null result is rejected");

    nf_develop_export_request_v2 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v2(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v2 undersized request is rejected");

    nf_develop_export_request_v2 unknown = request;
    unknown.base_estimation_mode = 99U;
    expect(
        nf_develop_export_v2(&unknown, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "unknown_base_estimation_mode") == 0,
        "v2 unknown base mode is refused");

    nf_develop_export_request_v2 preset = request;
    preset.base_estimation_mode = NF_BASE_ESTIMATION_PRESET;
    expect(
        nf_develop_export_v2(&preset, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "unsupported_base_estimation_mode") == 0,
        "v2 preset is not silently treated as auto");
}

void test_v3_contract() {
    expect(sizeof(nf_develop_export_request_v3) == 112U, "v3 request layout is fixed");

    nf_develop_export_request_v3 request = make_request_v3(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v3(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v3 null request is rejected");
    expect(
        nf_develop_export_v3(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v3 null result is rejected");

    nf_develop_export_request_v3 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v3(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v3 undersized request is rejected");

    request.density = 1.0F;
    request.highlight = -1.0F;
    request.shadow = 1.0F;
    request.whites = -1.0F;
    request.blacks = 1.0F;
    expect(
        nf_develop_export_v3(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v3 Basic Tone values reach source observation");
}

void test_v4_contract() {
    expect(sizeof(nf_develop_export_request_v4) == 128U, "v4 request layout is fixed");
    nf_develop_export_request_v4 request = make_request_v4(
        L"a.tif", L"b.png", NF_BASE_ESTIMATION_PRESET);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v4(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v4 null request is rejected");
    expect(
        nf_develop_export_v4(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v4 null result is rejected");

    nf_develop_export_request_v4 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v4(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v4 undersized request is rejected");

    expect(
        nf_develop_export_v4(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "missing_film_stock") == 0,
        "v4 Film mode requires a stock identifier");

    request.film_stock_dmin_id = L"not-a-stock";
    expect(
        nf_develop_export_v4(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "unknown_film_stock_or_light") == 0,
        "v4 unknown stock fails closed");

    request.film_stock_dmin_id = L"kodak-portra-400";
    request.light_source_profile_id = L"warm-led";
    expect(
        nf_develop_export_v4(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v4 known Film identifiers reach source observation");
}

void test_missing_source_is_not_a_validation_error() {
    const std::filesystem::path absent =
        std::filesystem::temp_directory_path() / L"negaflow-abi-absent-source.tif";
    std::error_code ignored{};
    std::filesystem::remove(absent, ignored);
    const std::filesystem::path destination =
        std::filesystem::temp_directory_path() / L"negaflow-abi-absent-output.png";

    const std::wstring source_text = absent.wstring();
    const std::wstring destination_text = destination.wstring();
    nf_develop_export_request_v1 request =
        make_request(source_text.c_str(), destination_text.c_str());
    nf_develop_export_result_v1 result = make_result();

    expect(nf_develop_export_v1(&request, &result) == NF_STATUS_OK, "the call is well formed");
    expect(result.succeeded == 0U, "a missing source does not succeed");
    // The stage matters: a missing file is an observation failure, not a malformed
    // request, and the caller needs to be able to tell those apart.
    expect(
        result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "a missing source fails at source observation");
    expect(
        std::strcmp(result.failure_name, "ok") != 0,
        "a failure carries a name other than ok");
}

void test_v2_missing_source_is_not_a_validation_error() {
    const std::filesystem::path absent =
        std::filesystem::temp_directory_path() / L"negaflow-abi-v2-absent-source.tif";
    std::error_code ignored{};
    std::filesystem::remove(absent, ignored);
    const std::wstring source_text = absent.wstring();
    nf_develop_export_request_v2 request = make_request_v2(source_text.c_str(), nullptr);
    nf_develop_export_result_v2 result = make_result_v2();
    std::vector<std::uint8_t> pixels(64U * 64U * 4U, 0U);

    expect(
        nf_develop_preview_v2(
            &request,
            64U,
            64U,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK,
        "v2 preview missing source is well formed");
    expect(
        result.succeeded == 0U && result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v2 auto reaches source observation without manual dmin");
}

void test_full_develop(const std::filesystem::path& source) {
    const std::filesystem::path destination =
        std::filesystem::temp_directory_path() /
        L"negaflow-abi-develop-export.png";
    std::error_code ignored{};
    std::filesystem::remove(destination, ignored);

    const std::wstring source_text = source.wstring();
    const std::wstring destination_text = destination.wstring();
    nf_develop_export_request_v1 request =
        make_request(source_text.c_str(), destination_text.c_str());
    request.film_emulation = 5U;  // portra_400
    request.film_emulation_intensity = 0.5;
    nf_develop_export_result_v1 result = make_result();

    const nf_status_t status = nf_develop_export_v1(&request, &result);
    expect(status == NF_STATUS_OK, "the develop call is well formed");
    if (result.succeeded == 0U) {
        std::cerr << "FAIL: develop failed at stage " << result.failed_stage
                  << " with " << result.failure_name << '\n';
        ++failures;
        return;
    }
    expect(result.failed_stage == NF_DEVELOP_STAGE_NONE, "a success reports no stage");
    expect(std::strcmp(result.failure_name, "ok") == 0, "a success reports ok");
    expect(result.image_width > 0U && result.image_height > 0U, "dimensions are reported");
    expect(result.source_file_bytes > 0U, "the source size is reported");
    expect(result.output_file_bytes > 0U, "the published artifact size is reported");
    expect(result.film_look_color_applied == 1U, "the Film Look colour stage ran");
    expect(
        std::filesystem::exists(destination),
        "the published file exists on disk");
    expect(
        std::filesystem::file_size(destination, ignored) == result.output_file_bytes,
        "the reported artifact size matches the file on disk");

    // Publishing never overwrites. A second call to the same destination must refuse
    // at the output stage rather than replace the artifact.
    nf_develop_export_result_v1 second = make_result();
    expect(
        nf_develop_export_v1(&request, &second) == NF_STATUS_OK,
        "the repeat call is well formed");
    expect(second.succeeded == 0U, "publishing does not overwrite an existing file");
    expect(
        second.failed_stage == NF_DEVELOP_STAGE_OUTPUT,
        "the refusal comes from the output stage");

    std::filesystem::remove(destination, ignored);
}

void test_v2_auto_develop(const std::filesystem::path& source) {
    const std::filesystem::path destination =
        std::filesystem::temp_directory_path() / L"negaflow-abi-v2-auto-develop.png";
    std::error_code ignored{};
    std::filesystem::remove(destination, ignored);
    const std::wstring source_text = source.wstring();
    const std::wstring destination_text = destination.wstring();
    nf_develop_export_request_v2 request = make_request_v2(
        source_text.c_str(),
        destination_text.c_str());
    nf_develop_export_result_v2 result = make_result_v2();

    expect(
        nf_develop_export_v2(&request, &result) == NF_STATUS_OK,
        "v2 auto develop call is well formed");
    expect(result.succeeded == 1U, "v2 auto develop succeeds");
    expect(
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_CONNECTED_COMPONENT ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_SCENE_EDGE ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_CONTINUOUS_BORDER ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_DISTRIBUTED_MASK ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_STRIP_FALLBACK ||
            result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_FALLBACK,
        "v2 auto develop reports resolver provenance");
    expect(
        result.applied_dmin[0] > 0.0F && result.applied_dmin[1] > 0.0F &&
            result.applied_dmin[2] > 0.0F,
        "v2 auto develop reports applied dmin");
    expect(std::filesystem::exists(destination), "v2 auto develop publishes an artifact");
    std::filesystem::remove(destination, ignored);
}

void test_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v1 request = make_request(source_text.c_str(), nullptr);
    request.film_emulation = 5U;  // portra_400

    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v1 result = make_result();

    expect(
        nf_develop_preview_v1(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK,
        "the preview call is well formed");
    if (result.succeeded == 0U) {
        std::cerr << "FAIL: preview failed at stage " << result.failed_stage << " with "
                  << result.failure_name << '\n';
        ++failures;
        return;
    }

    // A preview writes no file, so a null destination must be accepted where the publish
    // path refuses it.
    expect(result.image_width > 0U && result.image_height > 0U, "preview reports a size");
    expect(result.image_width <= box && result.image_height <= box, "preview fits the box");
    expect(
        result.output_file_bytes ==
            static_cast<std::uint64_t>(result.image_width) * result.image_height * 4U,
        "preview reports the bytes it wrote");

    bool opaque = true;
    bool any_colour = false;
    const std::size_t written =
        static_cast<std::size_t>(result.image_width) * result.image_height * 4U;
    for (std::size_t index = 0U; index < written; index += 4U) {
        opaque = opaque && pixels[index + 3U] == 0xFFU;
        any_colour = any_colour ||
            pixels[index] != 0U || pixels[index + 1U] != 0U || pixels[index + 2U] != 0U;
    }
    expect(opaque, "every preview pixel is opaque");
    // Without this the test would pass on a buffer the callee never touched.
    expect(any_colour, "the preview buffer was actually written");

    // Nothing past the written region may be touched.
    bool tail_untouched = true;
    for (std::size_t index = written; index < pixels.size(); ++index) {
        tail_untouched = tail_untouched && pixels[index] == 0U;
    }
    expect(tail_untouched, "the preview stays inside the region it reported");

    nf_develop_export_result_v1 tiny = make_result();
    expect(
        nf_develop_preview_v1(&request, box, box, pixels.data(), 16U, &tiny) == NF_STATUS_OK,
        "the undersized-buffer call is well formed");
    expect(tiny.succeeded == 0U, "an undersized preview buffer is refused");
    expect(
        tiny.failed_stage == NF_DEVELOP_STAGE_OUTPUT,
        "the undersized buffer is refused at the output stage");

    nf_develop_export_result_v1 null_pixels = make_result();
    expect(
        nf_develop_preview_v1(&request, box, box, nullptr, 0U, &null_pixels) ==
            NF_STATUS_INVALID_ARGUMENT,
        "a null preview buffer is rejected");
}

void test_v2_auto_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v2 request = make_request_v2(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();

    expect(
        nf_develop_preview_v2(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK,
        "v2 auto preview call is well formed");
    expect(result.succeeded == 1U, "v2 auto preview succeeds");
    expect(
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_CONNECTED_COMPONENT ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_SCENE_EDGE ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_CONTINUOUS_BORDER ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_DISTRIBUTED_MASK ||
        result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_STRIP_FALLBACK ||
            result.base_source == NF_DEVELOP_BASE_SOURCE_AUTO_FALLBACK,
        "v2 auto preview reports resolver provenance");
}

void test_v3_basic_tone_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v3 neutral = make_request_v3(source_text.c_str(), nullptr);
    nf_develop_export_request_v3 adjusted = neutral;
    adjusted.density = 0.75F;
    adjusted.highlight = -0.50F;
    adjusted.shadow = 0.50F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> neutral_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> adjusted_pixels(neutral_pixels.size(), 0U);
    nf_develop_export_result_v2 neutral_result = make_result_v2();
    nf_develop_export_result_v2 adjusted_result = make_result_v2();

    expect(
        nf_develop_preview_v3(
            &neutral,
            box,
            box,
            neutral_pixels.data(),
            static_cast<std::uint32_t>(neutral_pixels.size()),
            &neutral_result) == NF_STATUS_OK && neutral_result.succeeded == 1U,
        "v3 neutral preview succeeds");
    expect(
        nf_develop_preview_v3(
            &adjusted,
            box,
            box,
            adjusted_pixels.data(),
            static_cast<std::uint32_t>(adjusted_pixels.size()),
            &adjusted_result) == NF_STATUS_OK && adjusted_result.succeeded == 1U,
        "v3 Basic Tone preview succeeds");
    expect(
        neutral_result.image_width == adjusted_result.image_width &&
            neutral_result.image_height == adjusted_result.image_height &&
            neutral_pixels != adjusted_pixels,
        "v3 Basic Tone changes preview pixels");
}

void test_v4_film_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v4 request = make_request_v4(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_PRESET);
    request.film_stock_dmin_id = L"kodak-portra-400";
    request.light_source_profile_id = L"warm-led";
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v4(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U,
        "v4 Film preview succeeds");
    expect(
        result.base_source == NF_DEVELOP_BASE_SOURCE_PRESET_MEASURED ||
            result.base_source == NF_DEVELOP_BASE_SOURCE_PRESET_FALLBACK,
        "v4 Film preview reports measured-or-fallback provenance");
    expect(
        result.applied_dmin[0] > 0.0F && result.applied_dmin[1] > 0.0F &&
            result.applied_dmin[2] > 0.0F,
        "v4 Film preview reports applied base");
}

}  // namespace

int main(const int argument_count, const char* const arguments[]) {
    test_argument_contract();
    test_request_validation();
    test_v2_contract();
    test_v3_contract();
    test_v4_contract();
    test_missing_source_is_not_a_validation_error();
    test_v2_missing_source_is_not_a_validation_error();

    if (argument_count >= 2) {
        const std::filesystem::path source{arguments[1]};
        if (std::filesystem::exists(source)) {
            test_full_develop(source);
            test_preview(source);
            test_v2_auto_develop(source);
            test_v2_auto_preview(source);
            test_v3_basic_tone_preview(source);
            test_v4_film_preview(source);
        } else {
            std::cerr << "FAIL: the supplied source fixture does not exist\n";
            ++failures;
        }
    }

    if (failures != 0) {
        std::cerr << failures << " check(s) failed\n";
        return 1;
    }
    std::cout << "{\"status\":\"ok\",\"operation\":\"develop_export_abi_tests\"}\n";
    return 0;
}
