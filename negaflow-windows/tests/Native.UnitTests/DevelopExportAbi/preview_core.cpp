#include "develop_export_abi_test_support.h"

#include <cstring>
#include <iostream>

namespace negaflow::develop_export_abi_tests {

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
    // A real film scan already carries the emulsion response, so applying a stock on top
    // of it would feed the same emulsion twice. Selecting one is preserved and ignored.
    // This assertion used to demand the opposite and never ran, because the fixture path
    // it depends on did not resolve.
    expect(
        result.film_look_color_applied == 0U,
        "a film scan does not run the Film Look colour stage");
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
    // The measured base and which sampler found it are the whole point of the estimator,
    // so they are reported rather than only range-checked. A frame that falls back to the
    // fixed constant is the estimator failing, not succeeding.
    std::cout << "{\"note\":\"auto_film_base\",\"source\":" << result.base_source
              << ",\"dmin\":[" << result.applied_dmin[0] << ","
              << result.applied_dmin[1] << "," << result.applied_dmin[2] << "]}"
              << std::endl;
}

}  // namespace negaflow::develop_export_abi_tests
