#include <cstring>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_tiff_source_probe(const std::filesystem::path& source) {
    expect(
        nf_probe_tiff_source_v1(nullptr, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "a null TIFF source result is refused");

    nf_tiff_source_info_v1 short_result{};
    short_result.struct_size = 8U;
    expect(
        nf_probe_tiff_source_v1(source.c_str(), &short_result) == NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized TIFF source result is refused");

    nf_tiff_source_info_v1 result{};
    result.struct_size = static_cast<std::uint32_t>(sizeof(result));
    expect(
        nf_probe_tiff_source_v1(source.c_str(), &result) == NF_STATUS_OK &&
            result.status == NF_TIFF_SOURCE_PROBE_OK && result.file_bytes > 0U &&
            result.pixel_width > 0U && result.pixel_height > 0U &&
            result.samples_per_pixel > 0U && result.bits_per_sample > 0U &&
            result.sample_format > 0U && result.orientation >= 1U && result.orientation <= 8U,
        "the TIFF source probe returns stable import metadata");
}

void test_standard_image_import_and_develop(const std::filesystem::path& source) {
    const std::filesystem::path imported =
        std::filesystem::temp_directory_path() / L"negaflow-standard-input.png";
    const std::filesystem::path destination =
        std::filesystem::temp_directory_path() / L"negaflow-standard-output.png";
    std::error_code ignored{};
    std::filesystem::remove(imported, ignored);
    std::filesystem::remove(destination, ignored);

    const std::wstring source_text = source.wstring();
    const std::wstring imported_text = imported.wstring();
    const std::wstring destination_text = destination.wstring();
    nf_develop_export_request_v27 seed = make_request_v27(
        source_text.c_str(), imported_text.c_str());
    nf_develop_export_result_v3 seed_result = make_result_v3();
    expect(
        nf_develop_export_v27(&seed, nullptr, &seed_result) == NF_STATUS_OK &&
            seed_result.succeeded == 1U && std::filesystem::exists(imported),
        "a TIFF export provides a real PNG standard-image input");
    if (!std::filesystem::exists(imported)) {
        return;
    }

    expect(
        nf_probe_standard_image_source_v1(nullptr, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "a null standard-image source result is refused");
    nf_standard_image_source_info_v1 probe{};
    probe.struct_size = static_cast<std::uint32_t>(sizeof(probe));
    expect(
        nf_probe_standard_image_source_v1(imported.c_str(), &probe) == NF_STATUS_OK &&
            probe.status == NF_STANDARD_IMAGE_SOURCE_PROBE_OK &&
            probe.file_bytes > 0U && probe.pixel_width > 0U && probe.pixel_height > 0U &&
            probe.samples_per_pixel == 4U && probe.bits_per_sample == 16U &&
            probe.sample_format == 1U && probe.orientation == 1U,
        "the standard-image probe reports normalized JPEG PNG import metadata");

    const std::vector<std::uint8_t> before = read_file(imported);
    nf_develop_export_request_v27 request = make_request_v27(
        imported_text.c_str(), destination_text.c_str());
    request.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .film_look_source_kind = NF_DEVELOP_SOURCE_RENDERED_DIGITAL;
    request.v26.v25.v24.v21.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> preview(
        static_cast<std::size_t>(box) * box * 4U, 0U);
    nf_develop_export_result_v3 preview_result = make_result_v3();
    const nf_status_t preview_status = nf_develop_preview_v27(
        &request,
        nullptr,
        box,
        box,
        preview.data(),
        static_cast<std::uint32_t>(preview.size()),
        nullptr,
        &preview_result);
    expect(
        preview_status == NF_STATUS_OK && preview_result.succeeded == 1U,
        "a standard-image source reaches the shared preview pipeline");

    nf_develop_export_result_v3 export_result = make_result_v3();
    const nf_status_t export_status = nf_develop_export_v27(&request, nullptr, &export_result);
    expect(
        export_status == NF_STATUS_OK && export_result.succeeded == 1U &&
            std::filesystem::exists(destination),
        "a standard-image source reaches the shared export pipeline");
    expect(
        read_file(imported) == before,
        "standard-image preview and export leave the source bytes unchanged");
    std::filesystem::remove(imported, ignored);
    std::filesystem::remove(destination, ignored);
}

// The parity claim, made against a real negative and the profiles actually installed on
// this machine: choosing any of them as the proof destination leaves the frame alone,
// which is what macOS produces from its built-ins. If the resolver trusted a v2 `wtpt`

}  // namespace negaflow::develop_export_abi_tests
