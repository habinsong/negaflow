#include <cstring>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

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

    nf_develop_export_request_v1 digital = make_request(L"a.tif", L"b.png");
    digital.film_look_source_kind = NF_DEVELOP_SOURCE_RENDERED_DIGITAL;
    nf_develop_export_result_v1 digital_result = make_result();
    expect(
        nf_develop_export_v1(&digital, &digital_result) == NF_STATUS_OK &&
            digital_result.succeeded == 0U &&
            digital_result.failed_stage ==
                NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "a rendered-digital request reaches source observation");

    nf_develop_export_request_v1 black_and_white =
        make_request(L"a.tif", L"b.png");
    black_and_white.film_type = NF_FILM_TYPE_BLACK_AND_WHITE;
    black_and_white.film_look_source_kind =
        NF_DEVELOP_SOURCE_RENDERED_DIGITAL;
    black_and_white.film_emulation = 12U;  // tri_x_400
    nf_develop_export_result_v1 black_and_white_result = make_result();
    expect(
        nf_develop_export_v1(&black_and_white, &black_and_white_result) ==
                NF_STATUS_OK &&
            black_and_white_result.succeeded == 0U &&
            black_and_white_result.failed_stage ==
                NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "a B&W film profile crosses the ABI and reaches source observation");

    nf_develop_export_request_v1 zero_rows = make_request(L"a.tif", L"b.png");
    zero_rows.rows_per_copy = 0U;
    expect_rejected(
        zero_rows, "invalid_rows_per_copy", "a zero row-per-copy control is refused");
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

}  // namespace negaflow::develop_export_abi_tests
