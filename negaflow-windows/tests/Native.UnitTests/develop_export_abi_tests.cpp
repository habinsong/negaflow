#include "negaflow_abi.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/auto_adjust.h"
#include "synthetic_wic_tiff.h"

#include <Windows.h>
#include <bcrypt.h>
#include <wincodec.h>
#include <wrl/client.h>

#ifdef small
#undef small
#endif

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "windowscodecs.lib")

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool sha256(
    const std::vector<std::uint8_t>& bytes,
    std::array<std::uint8_t, 32U>& digest) noexcept {
    if (bytes.size() >
        static_cast<std::size_t>(std::numeric_limits<ULONG>::max())) {
        return false;
    }
    return BCryptHash(
               BCRYPT_SHA256_ALG_HANDLE,
               nullptr,
               0U,
               const_cast<PUCHAR>(bytes.data()),
               static_cast<ULONG>(bytes.size()),
               digest.data(),
               static_cast<ULONG>(digest.size())) >= 0;
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

[[nodiscard]] nf_develop_export_result_v3 make_result_v3() {
    nf_develop_export_result_v3 result{};
    result.struct_size = static_cast<std::uint32_t>(sizeof(result));
    return result;
}

[[nodiscard]] nf_develop_run_state_v1 make_run_state() {
    nf_develop_run_state_v1 state{};
    state.struct_size = static_cast<std::uint32_t>(sizeof(state));
    return state;
}

[[nodiscard]] nf_soft_proof_v1 make_soft_proof() {
    nf_soft_proof_v1 proof{};
    proof.struct_size = static_cast<std::uint32_t>(sizeof(proof));
    proof.paper_white_rgb[0] = 1.0F;
    proof.paper_white_rgb[1] = 1.0F;
    proof.paper_white_rgb[2] = 1.0F;
    return proof;
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

[[nodiscard]] nf_develop_export_request_v5 make_request_v5(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v5 request{};
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

[[nodiscard]] nf_develop_export_request_v6 make_request_v6(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v6 request{};
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

[[nodiscard]] nf_develop_export_request_v7 make_request_v7(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v7 request{};
    request.struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.source_path = source;
    request.destination_path = destination;
    request.output_format = NF_EXPORT_FORMAT_PNG16;
    request.film_type = NF_FILM_TYPE_COLOR;
    request.base_estimation_mode = base_mode;
    request.film_look_source_kind = NF_DEVELOP_SOURCE_FILM_SCAN;
    request.film_emulation_intensity = 0.5;
    request.rows_per_copy = 64U;
    request.color_grading_blending = 0.5F;
    return request;
}

[[nodiscard]] nf_develop_export_request_v8 make_request_v8(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v8 request{};
    const nf_develop_export_request_v7 prefix =
        make_request_v7(source, destination, base_mode);
    std::memcpy(&request, &prefix, sizeof(prefix));
    request.struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v9 make_request_v9(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v9 request{};
    request.v8 = make_request_v8(source, destination, base_mode);
    request.v8.struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.noise_reduction_luma = 0.5F;
    request.noise_reduction_chroma = 0.5F;
    request.noise_reduction_dark_tone = 0.5F;
    request.noise_reduction_detail = 0.5F;
    request.noise_reduction_film_profile =
        NF_FILM_SCAN_DENOISE_COLOR_NEGATIVE;
    return request;
}

[[nodiscard]] nf_develop_export_request_v10 make_request_v10(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v10 request{};
    request.v9 = make_request_v9(source, destination, base_mode);
    request.v9.v8.struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v11 make_request_v11(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v11 request{};
    request.v10 = make_request_v10(source, destination, base_mode);
    request.v10.v9.v8.struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.crop_width = 1.0;
    request.crop_height = 1.0;
    return request;
}

[[nodiscard]] nf_develop_export_request_v12 make_request_v12(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v12 request{};
    request.v11 = make_request_v11(source, destination, base_mode);
    request.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v13 make_request_v13(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v13 request{};
    request.v12 = make_request_v12(source, destination, base_mode);
    request.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v14 make_request_v14(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v14 request{};
    request.v13 = make_request_v13(source, destination, base_mode);
    request.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v15 make_request_v15(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v15 request{};
    request.v14 = make_request_v14(source, destination, base_mode);
    request.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v16 make_request_v16(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v16 request{};
    request.v15 = make_request_v15(source, destination, base_mode);
    request.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v17 make_request_v17(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v17 request{};
    request.v16 = make_request_v16(source, destination, base_mode);
    request.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    request.film_polarity = NF_FILM_POLARITY_NEGATIVE;
    return request;
}

[[nodiscard]] nf_develop_export_request_v18 make_request_v18(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v18 request{};
    request.v17 = make_request_v17(source, destination, base_mode);
    request.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v19 make_request_v19(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v19 request{};
    request.v18 = make_request_v18(source, destination, base_mode);
    request.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v20 make_request_v20(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v20 request{};
    request.v19 = make_request_v19(source, destination, base_mode);
    request.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v21 make_request_v21(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v21 request{};
    request.v20 = make_request_v20(source, destination, base_mode);
    request.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v24 make_request_v24(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode = NF_BASE_ESTIMATION_AUTO) {
    nf_develop_export_request_v24 request{};
    request.v21 = make_request_v21(source, destination, base_mode);
    request.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] bool write_file(
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& bytes) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size()));
    return output.good();
}

[[nodiscard]] std::vector<std::uint8_t> read_file(
    const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    return std::vector<std::uint8_t>(
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>());
}

[[nodiscard]] std::vector<std::uint8_t> decode_png_bgra8(
    const std::filesystem::path& path,
    const std::uint32_t expected_width,
    const std::uint32_t expected_height) {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
        return {};
    }
    const bool uninitialize = SUCCEEDED(initialized);
    Microsoft::WRL::ComPtr<IWICImagingFactory> factory{};
    Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder{};
    Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> frame{};
    Microsoft::WRL::ComPtr<IWICFormatConverter> converter{};
    HRESULT status = CoCreateInstance(
        CLSID_WICImagingFactory2,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (SUCCEEDED(status)) {
        status = factory->CreateDecoderFromFilename(
            path.c_str(),
            nullptr,
            GENERIC_READ,
            WICDecodeMetadataCacheOnLoad,
            &decoder);
    }
    if (SUCCEEDED(status)) {
        status = decoder->GetFrame(0U, &frame);
    }
    UINT width = 0U;
    UINT height = 0U;
    if (SUCCEEDED(status)) {
        status = frame->GetSize(&width, &height);
    }
    if (SUCCEEDED(status) &&
        (width != expected_width || height != expected_height)) {
        status = E_FAIL;
    }
    if (SUCCEEDED(status)) {
        status = factory->CreateFormatConverter(&converter);
    }
    if (SUCCEEDED(status)) {
        status = converter->Initialize(
            frame.Get(),
            GUID_WICPixelFormat32bppBGRA,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom);
    }
    std::vector<std::uint8_t> pixels{};
    if (SUCCEEDED(status)) {
        pixels.resize(static_cast<std::size_t>(width) * height * 4U);
        status = converter->CopyPixels(
            nullptr,
            width * 4U,
            static_cast<UINT>(pixels.size()),
            pixels.data());
    }
    if (FAILED(status)) {
        pixels.clear();
    }
    converter.Reset();
    frame.Reset();
    decoder.Reset();
    factory.Reset();
    if (uninitialize) {
        CoUninitialize();
    }
    return pixels;
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

void test_v5_contract() {
    expect(sizeof(nf_point_curve_v1) == 1032U, "v5 point curve layout is fixed");
    expect(sizeof(nf_develop_export_request_v5) == 4256U, "v5 request layout is fixed");
    nf_develop_export_request_v5 request = make_request_v5(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v5(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v5 null request is rejected");
    expect(
        nf_develop_export_v5(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v5 null result is rejected");

    nf_develop_export_request_v5 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v5(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v5 undersized request is rejected");

    request.point_curve_rgb.reserved = 1U;
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_point_curves") == 0,
        "v5 reserved Point Curve bytes are rejected");

    request = make_request_v5(L"a.tif", L"b.png");
    request.point_curve_rgb.point_count = NF_POINT_CURVE_MAX_POINTS + 1U;
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_point_curves") == 0,
        "v5 oversized Point Curve is rejected");

    request = make_request_v5(L"a.tif", L"b.png");
    request.point_curve_rgb.point_count = 2U;
    request.point_curve_rgb.points[0U] = {0.5, 0.4};
    request.point_curve_rgb.points[1U] = {0.5, 0.6};
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_point_curves") == 0,
        "v5 duplicate Point Curve coordinate is rejected");

    request = make_request_v5(L"a.tif", L"b.png");
    request.point_curve_rgb.point_count = 3U;
    request.point_curve_rgb.points[0U] = {0.0, 0.0};
    request.point_curve_rgb.points[1U] = {0.5, 0.6};
    request.point_curve_rgb.points[2U] = {1.0, 1.0};
    expect(
        nf_develop_export_v5(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v5 Point Curves reach source observation");
}

void test_v6_contract() {
    expect(sizeof(nf_develop_export_request_v6) == 4352U, "v6 request layout is fixed");
    nf_develop_export_request_v6 request = make_request_v6(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v6(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v6 null request is rejected");
    expect(
        nf_develop_export_v6(&request, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "v6 null result is rejected");

    nf_develop_export_request_v6 small = request;
    small.struct_size = 4U;
    expect(
        nf_develop_export_v6(&small, &result) == NF_STATUS_STRUCT_TOO_SMALL,
        "v6 undersized request is rejected");

    request.color_mixer_hue[0U] = 1.01F;
    expect(
        nf_develop_export_v6(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_color_mixer") == 0,
        "v6 out-of-range Color Mixer is rejected");

    request = make_request_v6(L"a.tif", L"b.png");
    request.color_mixer_saturation[1U] = 0.5F;
    expect(
        nf_develop_export_v6(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v6 Color Mixer reaches source observation");
}

void test_v7_contract() {
    expect(sizeof(nf_develop_export_request_v7) == 4400U, "v7 request layout is fixed");
    nf_develop_export_request_v7 request = make_request_v7(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v7(nullptr, &result) == NF_STATUS_INVALID_ARGUMENT,
        "v7 null request is rejected");
    request.color_grading_midtones_saturation = 1.01F;
    expect(
        nf_develop_export_v7(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_color_grading") == 0,
        "v7 out-of-range Color Grading is rejected");
    request = make_request_v7(L"a.tif", L"b.png");
    request.color_grading_highlights_luminance = 0.25F;
    expect(
        nf_develop_export_v7(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v7 Color Grading reaches source observation");
}

void test_v8_contract() {
    expect(sizeof(nf_develop_export_request_v8) == 4408U,
           "v8 request layout is fixed");
    nf_develop_export_request_v8 request = make_request_v8(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.defect_removal_strength = 1.01;
    expect(
        nf_develop_export_v8(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_grain_mend_parameters") == 0,
        "v8 out-of-range GrainMend strength is rejected");
    request = make_request_v8(L"a.tif", L"b.png");
    request.defect_removal_strength = 0.75;
    expect(
        nf_develop_export_v8(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v8 GrainMend strength reaches source observation");
}

void test_v9_contract() {
    expect(sizeof(nf_develop_export_request_v9) == 4440U,
           "v9 request layout is fixed");
    nf_develop_export_request_v9 request = make_request_v9(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.noise_reduction_strength = 1.01F;
    expect(
        nf_develop_export_v9(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(
                result.failure_name,
                "invalid_film_scan_denoise_parameters") == 0,
        "v9 out-of-range FilmScanDenoise strength is rejected");
    request = make_request_v9(L"a.tif", L"b.png");
    request.noise_reduction_strength = 0.75F;
    request.noise_reduction_film_profile =
        NF_FILM_SCAN_DENOISE_COLOR_POSITIVE;
    expect(
        nf_develop_export_v9(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v9 FilmScanDenoise controls reach source observation");
}

void test_v10_contract() {
    expect(sizeof(nf_develop_export_request_v10) == 4464U,
           "v10 request layout is fixed");
    nf_develop_export_request_v10 request =
        make_request_v10(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.texture_clarity = 1.01F;
    expect(
        nf_develop_export_v10(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name, "invalid_texture_parameters") == 0,
        "v10 out-of-range Texture control is rejected");
    request = make_request_v10(L"a.tif", L"b.png");
    request.texture_sharpness = 0.75F;
    expect(
        nf_develop_export_v10(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v10 Texture controls reach source observation");
}

void test_v11_contract() {
    expect(sizeof(nf_develop_export_request_v11) == 4552U,
           "v11 request layout is fixed");
    nf_develop_export_request_v11 request =
        make_request_v11(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.image_rotation = 4U;
    expect(
        nf_develop_export_v11(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            std::strcmp(result.failure_name,
                        "invalid_post_pipeline_parameters") == 0,
        "v11 invalid ImageTransform is rejected");
    request = make_request_v11(L"a.tif", L"b.png");
    request.bw_toning_mode = 1U;
    request.bw_toning_shadow_hue = 285.0;
    request.bw_toning_highlight_hue = 34.0;
    request.bw_toning_strength = 0.5;
    expect(
        nf_develop_export_v11(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v11 B&W toning and transform controls reach source observation");
}

void test_v12_contract() {
    expect(sizeof(nf_develop_export_request_v12) == 4600U,
           "v12 request layout is fixed");
    nf_local_dodge_burn_stroke_v1 stroke{};
    stroke.point_offset = 1U;
    stroke.point_count = 1U;
    stroke.thickness = 0.04F;
    stroke.feather = 0.02F;
    nf_local_dodge_burn_adjustment_v1 adjustment{};
    adjustment.mode = NF_LOCAL_DODGE_BURN_MODE_DODGE;
    adjustment.enabled = 1U;
    adjustment.mask_kind = NF_LOCAL_DODGE_BURN_MASK_BRUSH;
    adjustment.stroke_count = 1U;
    adjustment.amount = 0.5F;
    adjustment.center_x = 0.5F;
    adjustment.center_y = 0.5F;
    adjustment.radius = 0.25F;
    adjustment.feather = 0.25F;
    adjustment.start_x = 0.5F;
    adjustment.end_x = 0.5F;
    adjustment.end_y = 1.0F;
    nf_local_dodge_burn_point_v1 point{0.5F, 0.5F};
    nf_develop_export_request_v12 request =
        make_request_v12(L"a.tif", L"b.png");
    request.local_adjustments = &adjustment;
    request.local_adjustment_count = 1U;
    request.local_strokes = &stroke;
    request.local_stroke_count = 1U;
    request.local_points = &point;
    request.local_point_count = 1U;
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v12(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_local_dodge_burn_payload") == 0,
        "v12 rejects a stroke point range outside the flat payload");
}

void test_v18_contract() {
    nf_develop_export_request_v18 request =
        make_request_v18(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();

    request.defect_region_reserved = 1U;
    expect(
        nf_develop_export_v18(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_region_payload") == 0,
        "v18 rejects a nonzero defect payload reserved field");

    request = make_request_v18(L"a.tif", L"b.png");
    nf_defect_region_edit_v1 edit{};
    edit.enabled = 1U;
    edit.width = 8U;
    edit.height = 8U;
    edit.mask_stride_bytes = 8U;
    edit.mask_byte_count = 64U;
    edit.strength = 1.0;
    std::vector<std::uint8_t> truncated_mask(32U, 0xffU);
    request.defect_region_edits = &edit;
    request.defect_region_edit_count = 1U;
    request.defect_mask_bytes = truncated_mask.data();
    request.defect_mask_byte_count =
        static_cast<std::uint32_t>(truncated_mask.size());
    result = make_result_v2();
    expect(
        nf_develop_export_v18(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_region_payload") == 0,
        "v18 rejects a defect mask range outside the flat payload");
}

void test_v19_contract() {
    nf_develop_export_request_v19 request =
        make_request_v19(L"a.tif", L"b.png");
    nf_develop_export_result_v2 result = make_result_v2();
    request.reserved = 1U;
    expect(
        nf_develop_export_v19(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_source_identity") == 0,
        "v19 rejects a nonzero source-identity reserved field");

    request = make_request_v19(L"a.tif", L"b.png");
    nf_defect_region_edit_v1 edit{};
    edit.enabled = 1U;
    edit.width = 8U;
    edit.height = 8U;
    edit.mask_stride_bytes = 8U;
    edit.mask_byte_count = 64U;
    edit.strength = 1.0;
    std::vector<std::uint8_t> mask(64U, 0xffU);
    request.v18.defect_region_edits = &edit;
    request.v18.defect_region_edit_count = 1U;
    request.v18.defect_mask_bytes = mask.data();
    request.v18.defect_mask_byte_count = static_cast<std::uint32_t>(mask.size());
    result = make_result_v2();
    expect(
        nf_develop_export_v19(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(
                result.failure_name,
                "invalid_defect_source_identity") == 0,
        "v19 rejects an unbound defect recipe before source I/O");
}

void test_v20_contract() {
    expect(sizeof(nf_defect_clone_point_v1) == 16U,
           "v20 clone point layout is fixed");
    expect(sizeof(nf_defect_clone_stroke_v1) == 40U,
           "v20 clone stroke layout is fixed");
    expect(sizeof(nf_defect_clone_edit_v1) == 24U,
           "v20 clone edit layout is fixed");
    expect(sizeof(nf_develop_export_request_v20) == 4784U,
           "v20 request layout is fixed");

    nf_defect_clone_point_v1 point{0.5, 0.5};
    nf_defect_clone_stroke_v1 stroke{};
    stroke.point_count = 1U;
    stroke.offset_x = 0.1;
    stroke.diameter_pixels = 9.0;
    stroke.hardness = 1.0;
    nf_defect_clone_edit_v1 edit{};
    edit.enabled = 1U;
    edit.stroke_count = 1U;
    edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 order{
        NF_DEFECT_RECIPE_EDIT_CLONE, 0U};
    std::array<std::uint8_t, 32U> digest{};

    nf_develop_export_request_v20 request =
        make_request_v20(L"a.tif", L"b.png");
    request.v19.defect_source_file_bytes = 1U;
    request.v19.defect_source_sha256 = digest.data();
    request.v19.has_defect_source_identity = 1U;
    request.defect_clone_edits = &edit;
    request.defect_clone_edit_count = 1U;
    request.defect_clone_strokes = &stroke;
    request.defect_clone_stroke_count = 1U;
    request.defect_clone_points = &point;
    request.defect_clone_point_count = 1U;
    request.defect_edit_order = &order;
    request.defect_edit_order_count = 1U;
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v20(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v20 complete clone payload reaches source observation");

    request.defect_edit_order_count = 0U;
    result = make_result_v2();
    expect(
        nf_develop_export_v20(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_clone_payload") == 0,
        "v20 rejects a clone descriptor omitted from recipe order");
}

void test_v21_contract() {
    expect(sizeof(nf_defect_brush_point_v1) == 16U,
           "v21 brush point layout is fixed");
    expect(sizeof(nf_defect_brush_stroke_v1) == 16U,
           "v21 brush stroke layout is fixed");
    expect(sizeof(nf_defect_brush_edit_v1) == 24U,
           "v21 brush edit layout is fixed");
    expect(sizeof(nf_develop_export_request_v21) == 4832U,
           "v21 request layout is fixed");

    nf_defect_brush_point_v1 point{0.5, 0.5};
    nf_defect_brush_stroke_v1 stroke{};
    stroke.point_count = 1U;
    stroke.thickness = 0.02;
    nf_defect_brush_edit_v1 edit{};
    edit.enabled = 1U;
    edit.stroke_count = 1U;
    edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 order{
        NF_DEFECT_RECIPE_EDIT_BRUSH, 0U};
    std::array<std::uint8_t, 32U> digest{};

    nf_develop_export_request_v21 request =
        make_request_v21(L"a.tif", L"b.png");
    request.v20.v19.defect_source_file_bytes = 1U;
    request.v20.v19.defect_source_sha256 = digest.data();
    request.v20.v19.has_defect_source_identity = 1U;
    request.v20.defect_edit_order = &order;
    request.v20.defect_edit_order_count = 1U;
    request.defect_brush_edits = &edit;
    request.defect_brush_edit_count = 1U;
    request.defect_brush_strokes = &stroke;
    request.defect_brush_stroke_count = 1U;
    request.defect_brush_points = &point;
    request.defect_brush_point_count = 1U;
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_export_v21(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v21 complete brush payload reaches source observation");

    request.v20.defect_edit_order_count = 0U;
    result = make_result_v2();
    expect(
        nf_develop_export_v21(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_clone_payload") == 0,
        "v21 rejects a brush descriptor omitted from recipe order");

    request.v20.defect_edit_order_count = 1U;
    point.x = 2.0;
    result = make_result_v2();
    expect(
        nf_develop_export_v21(&request, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_brush_payload") == 0,
        "v21 rejects out-of-range normalized brush geometry");
}

void test_v24_contract() {
    expect(sizeof(nf_defect_infrared_edit_v1) == 24U,
           "v24 infrared descriptor layout is fixed");
    expect(sizeof(nf_develop_export_request_v24) == 4864U,
           "v24 request layout is fixed");
    expect(offsetof(nf_develop_export_request_v24, defect_infrared_edits) == 4832U,
           "v24 infrared descriptor offset is fixed");
    expect(offsetof(nf_develop_export_request_v24,
                    defect_infrared_attenuation_bytes) == 4848U,
           "v24 attenuation payload offset is fixed");

    std::array<std::uint8_t, 64U> core{};
    std::array<std::uint8_t, 128U> attenuation{};
    std::array<std::uint8_t, 32U> digest{};
    nf_defect_region_edit_v1 region{};
    region.enabled = 1U;
    region.width = 8U;
    region.height = 8U;
    region.mask_stride_bytes = 8U;
    region.mask_byte_count = static_cast<std::uint32_t>(core.size());
    region.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 order{NF_DEFECT_RECIPE_EDIT_REGION, 0U};
    nf_defect_infrared_edit_v1 infrared{};
    infrared.has_attenuation = 1U;
    infrared.attenuation_stride_bytes = 16U;
    infrared.attenuation_byte_count =
        static_cast<std::uint32_t>(attenuation.size());

    nf_develop_export_request_v24 request = make_request_v24(L"a.tif", L"b.png");
    request.v21.v20.v19.defect_source_file_bytes = 1U;
    request.v21.v20.v19.defect_source_sha256 = digest.data();
    request.v21.v20.v19.has_defect_source_identity = 1U;
    request.v21.v20.v19.v18.defect_region_edits = &region;
    request.v21.v20.v19.v18.defect_region_edit_count = 1U;
    request.v21.v20.v19.v18.defect_mask_bytes = core.data();
    request.v21.v20.v19.v18.defect_mask_byte_count =
        static_cast<std::uint32_t>(core.size());
    request.v21.v20.defect_edit_order = &order;
    request.v21.v20.defect_edit_order_count = 1U;
    request.defect_infrared_edits = &infrared;
    request.defect_infrared_edit_count = 1U;
    request.defect_infrared_attenuation_bytes = attenuation.data();
    request.defect_infrared_attenuation_byte_count =
        static_cast<std::uint32_t>(attenuation.size());
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_export_v24(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE,
        "v24 complete infrared payload reaches source observation");

    infrared.attenuation_byte_count--;
    result = make_result_v3();
    expect(
        nf_develop_export_v24(&request, nullptr, &result) == NF_STATUS_OK &&
            result.succeeded == 0U &&
            result.failed_stage == NF_DEVELOP_STAGE_REQUEST_VALIDATION &&
            std::strcmp(result.failure_name, "invalid_defect_infrared_payload") == 0,
        "v24 rejects an infrared attenuation size mismatch");
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

void test_v5_point_curve_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v5 neutral = make_request_v5(source_text.c_str(), nullptr);
    nf_develop_export_request_v5 adjusted = neutral;
    adjusted.point_curve_rgb.point_count = 3U;
    adjusted.point_curve_rgb.points[0U] = {0.0, 0.0};
    adjusted.point_curve_rgb.points[1U] = {0.5, 0.65};
    adjusted.point_curve_rgb.points[2U] = {1.0, 1.0};
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> neutral_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> adjusted_pixels(neutral_pixels.size(), 0U);
    nf_develop_export_result_v2 neutral_result = make_result_v2();
    nf_develop_export_result_v2 adjusted_result = make_result_v2();

    expect(
        nf_develop_preview_v5(
            &neutral, box, box, neutral_pixels.data(),
            static_cast<std::uint32_t>(neutral_pixels.size()), &neutral_result) == NF_STATUS_OK &&
            neutral_result.succeeded == 1U,
        "v5 neutral preview succeeds");
    expect(
        nf_develop_preview_v5(
            &adjusted, box, box, adjusted_pixels.data(),
            static_cast<std::uint32_t>(adjusted_pixels.size()), &adjusted_result) == NF_STATUS_OK &&
            adjusted_result.succeeded == 1U,
        "v5 Point Curve preview succeeds");
    expect(
        neutral_result.image_width == adjusted_result.image_width &&
            neutral_result.image_height == adjusted_result.image_height &&
            neutral_pixels != adjusted_pixels,
        "v5 Point Curve changes preview pixels");
}

void test_v6_color_mixer_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v6 neutral = make_request_v6(source_text.c_str(), nullptr);
    nf_develop_export_request_v6 adjusted = neutral;
    adjusted.color_mixer_saturation[0U] = -0.75F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> neutral_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> adjusted_pixels(neutral_pixels.size(), 0U);
    nf_develop_export_result_v2 neutral_result = make_result_v2();
    nf_develop_export_result_v2 adjusted_result = make_result_v2();
    expect(
        nf_develop_preview_v6(
            &neutral, box, box, neutral_pixels.data(),
            static_cast<std::uint32_t>(neutral_pixels.size()), &neutral_result) == NF_STATUS_OK &&
            neutral_result.succeeded == 1U,
        "v6 neutral preview succeeds");
    expect(
        nf_develop_preview_v6(
            &adjusted, box, box, adjusted_pixels.data(),
            static_cast<std::uint32_t>(adjusted_pixels.size()), &adjusted_result) == NF_STATUS_OK &&
            adjusted_result.succeeded == 1U,
        "v6 Color Mixer preview succeeds");
    expect(
        neutral_result.image_width == adjusted_result.image_width &&
            neutral_result.image_height == adjusted_result.image_height &&
            neutral_pixels != adjusted_pixels,
        "v6 Color Mixer changes preview pixels");
}

void test_v8_grain_mend_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v8 request =
        make_request_v8(source_text.c_str(), nullptr);
    request.defect_removal_strength = 0.75;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v8(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK &&
            result.succeeded == 1U,
        "v8 nonzero GrainMend preview succeeds through the shared pipeline");
}

// Neutrality of a monochrome develop is a property of the working image. The 8-bit
// preview adds under one code value of dither per channel — as the macOS display path
// does — so the check is "no visible tint", not "identical bytes". A real tint from the
// B&W graph would be far larger than one step.
[[nodiscard]] bool preview_is_neutral(
    const std::vector<std::uint8_t>& pixels) noexcept {
    for (std::size_t offset = 0U; offset + 3U < pixels.size(); offset += 4U) {
        const int blue = pixels[offset];
        const int green = pixels[offset + 1U];
        const int red = pixels[offset + 2U];
        const int highest = std::max(red, std::max(green, blue));
        const int lowest = std::min(red, std::min(green, blue));
        if (highest - lowest > 1) {
            return false;
        }
    }
    return true;
}

void test_v9_film_scan_denoise_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v9 request =
        make_request_v9(source_text.c_str(), nullptr);
    request.noise_reduction_strength = 0.7F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v9(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK &&
            result.succeeded == 1U,
        "v9 nonzero FilmScanDenoise preview succeeds through the shared pipeline");
    // FilmScanDenoise runs its tile rows concurrently. The tiles write disjoint cores, so
    // the split must not move a pixel; this fingerprint is what makes that checkable on a
    // real scan rather than argued from the code. Forcing the whole engine inline
    // reproduces exactly this value.
    std::uint64_t fingerprint = 1469598103934665603ULL;
    for (const std::uint8_t value : pixels) {
        fingerprint = (fingerprint ^ value) * 1099511628211ULL;
    }
    std::cout << "{\"note\":\"denoise_preview_pixels\",\"fnv1a64\":\"" << std::hex
              << fingerprint << std::dec << "\"}" << std::endl;
}

void test_v10_texture_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v10 request =
        make_request_v10(source_text.c_str(), nullptr);
    request.texture_sharpness = 0.6F;
    request.texture_vignette = 0.3F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v10(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK &&
            result.succeeded == 1U,
        "v10 Texture preview succeeds through the shared pipeline");
    // Texture's blur runs its tile rows concurrently on the same disjoint-core contract as
    // FilmScanDenoise, and its grain hashes the absolute coordinate rather than running a
    // sequence. Both claims are only worth anything if the pixels come out the same, so
    // the fingerprint is reported for comparison against a forced-inline build.
    std::uint64_t fingerprint = 1469598103934665603ULL;
    for (const std::uint8_t value : pixels) {
        fingerprint = (fingerprint ^ value) * 1099511628211ULL;
    }
    std::cout << "{\"note\":\"texture_preview_pixels\",\"fnv1a64\":\"" << std::hex
              << fingerprint << std::dec << "\",\"wall_microseconds\":"
              << result.wall_microseconds << "}" << std::endl;
}

void test_v11_bw_transform_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v11 request =
        make_request_v11(source_text.c_str(), nullptr);
    request.v10.v9.v8.film_type = NF_FILM_TYPE_BLACK_AND_WHITE;
    request.bw_toning_mode = 2U;
    request.bw_toning_shadow_hue = 32.0;
    request.bw_toning_highlight_hue = 48.0;
    request.bw_toning_strength = 0.8;
    request.image_rotation = 1U;
    request.has_crop = 1U;
    request.crop_x = 0.1;
    request.crop_y = 0.1;
    request.crop_width = 0.8;
    request.crop_height = 0.8;
    request.straighten_angle = 3.0;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v11(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            result.image_width > 0U && result.image_height > 0U,
        "v11 B&W toning and ImageTransform preview succeeds through the shared pipeline");
}

void test_v11_rendered_digital_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v11 request =
        make_request_v11(source_text.c_str(), nullptr);
    request.v10.v9.v8.film_look_source_kind =
        NF_DEVELOP_SOURCE_RENDERED_DIGITAL;
    request.v10.v9.v8.film_emulation = 39U;  // Vision3 500T
    request.v10.v9.v8.film_emulation_intensity = 0.7;
    request.v10.texture_grain = 0.45F;
    request.v10.texture_halation = 0.55F;
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v11(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            result.film_look_route == NF_FILM_LOOK_ROUTE_DIGITAL_FILM_LOOK,
        "v11 Vision3 rendered-digital preview completes the dedicated Film Look graph");

    nf_develop_export_request_v11 black_and_white = request;
    black_and_white.v10.v9.v8.film_type = NF_FILM_TYPE_BLACK_AND_WHITE;
    black_and_white.v10.v9.v8.film_emulation = 12U;  // Tri-X 400
    std::vector<std::uint8_t> black_and_white_pixels(pixels.size(), 0U);
    nf_develop_export_result_v2 black_and_white_result = make_result_v2();
    expect(
        nf_develop_preview_v11(
            &black_and_white,
            box,
            box,
            black_and_white_pixels.data(),
            static_cast<std::uint32_t>(black_and_white_pixels.size()),
            &black_and_white_result) == NF_STATUS_OK &&
            black_and_white_result.succeeded == 1U &&
            black_and_white_result.film_look_route ==
                NF_FILM_LOOK_ROUTE_DIGITAL_FILM_LOOK,
        "v11 rendered-digital B&W preview completes the dedicated Film Look graph");
    expect(
        preview_is_neutral(black_and_white_pixels),
        "the rendered-digital B&W Film Look exports neutral RGB");
}

void test_v12_local_dodge_burn_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v12 baseline =
        make_request_v12(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v12(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v12 identity preview succeeds");

    nf_local_dodge_burn_point_v1 points[]{
        {0.38F, 0.50F},
        {0.62F, 0.50F},
    };
    nf_local_dodge_burn_stroke_v1 stroke{};
    stroke.point_count = 2U;
    stroke.thickness = 0.12F;
    stroke.feather = 0.02F;
    nf_local_dodge_burn_adjustment_v1 adjustment{};
    adjustment.mode = NF_LOCAL_DODGE_BURN_MODE_DODGE;
    adjustment.enabled = 1U;
    adjustment.mask_kind = NF_LOCAL_DODGE_BURN_MASK_BRUSH;
    adjustment.stroke_count = 1U;
    adjustment.amount = 0.8F;
    adjustment.center_x = 0.5F;
    adjustment.center_y = 0.5F;
    adjustment.radius = 0.25F;
    adjustment.feather = 0.25F;
    adjustment.start_x = 0.5F;
    adjustment.end_x = 0.5F;
    adjustment.end_y = 1.0F;
    nf_develop_export_request_v12 request = baseline;
    request.local_adjustments = &adjustment;
    request.local_adjustment_count = 1U;
    request.local_strokes = &stroke;
    request.local_stroke_count = 1U;
    request.local_points = points;
    request.local_point_count = 2U;
    std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v12(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            pixels != baseline_pixels,
        "v12 brush Local Dodge/Burn changes the shared preview pipeline");
    // The box blurs carry a running sum along each line and the application is per pixel,
    // so splitting by row and by column must not move a result. Reported so a build with
    // the engine forced inline can be compared against this value.
    std::uint64_t fingerprint = 1469598103934665603ULL;
    for (const std::uint8_t value : pixels) {
        fingerprint = (fingerprint ^ value) * 1099511628211ULL;
    }
    std::cout << "{\"note\":\"dodge_burn_preview_pixels\",\"fnv1a64\":\"" << std::hex
              << fingerprint << std::dec << "\",\"wall_microseconds\":"
              << result.wall_microseconds << "}" << std::endl;
}

void test_v13_color_model_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v13 baseline =
        make_request_v13(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v13(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v13 identity preview succeeds");

    nf_develop_export_request_v13 request = baseline;
    request.warmth = 0.7F;
    request.tint = -0.35F;
    request.color_depth = 0.4F;
    request.vibrance = 0.3F;
    request.saturation = 0.2F;
    request.red_primary = 0.1F;
    request.green_primary = -0.1F;
    request.blue_primary = 0.15F;
    std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v13(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            pixels != baseline_pixels,
        "v13 ColorModel changes the shared preview pipeline");
}

void test_v14_scene_correction_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v14 baseline =
        make_request_v14(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v14(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v14 identity preview succeeds");

    nf_develop_export_request_v14 request = baseline;
    request.auto_levels = 1U;
    request.auto_neutral_balance = 1U;
    std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 result = make_result_v2();
    expect(
        nf_develop_preview_v14(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &result) == NF_STATUS_OK && result.succeeded == 1U &&
            pixels != baseline_pixels,
        "v14 scene correction changes the shared preview pipeline");
}

void test_v15_develop_target_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v15 baseline =
        make_request_v15(source_text.c_str(), nullptr);
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v15(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v15 MAIN target reaches the shared preview pipeline");

    std::vector<std::vector<std::uint8_t>> target_outputs;
    for (const std::uint32_t target : {
             NF_DEVELOP_TARGET_NORITSU,
             NF_DEVELOP_TARGET_SP3000,
             NF_DEVELOP_TARGET_F135,
             NF_DEVELOP_TARGET_HR}) {
        nf_develop_export_request_v15 request = baseline;
        request.develop_target = target;
        std::vector<std::uint8_t> pixels(baseline_pixels.size(), 0U);
        nf_develop_export_result_v2 result = make_result_v2();
        expect(
            nf_develop_preview_v15(
                &request,
                box,
                box,
                pixels.data(),
                static_cast<std::uint32_t>(pixels.size()),
                &result) == NF_STATUS_OK && result.succeeded == 1U &&
                pixels != baseline_pixels,
            "v15 scanner target changes the shared preview pixels");
        target_outputs.push_back(std::move(pixels));
    }
    expect(target_outputs[0] != target_outputs[1] &&
               target_outputs[1] != target_outputs[2] &&
               target_outputs[2] != target_outputs[3],
           "v15 scanner targets remain distinct in shared preview");

    nf_develop_export_request_v15 rescue = baseline;
    rescue.develop_target = NF_DEVELOP_TARGET_RESCUE;
    std::vector<std::uint8_t> rescue_pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 rescue_result = make_result_v2();
    expect(
        nf_develop_preview_v15(
            &rescue,
            box,
            box,
            rescue_pixels.data(),
            static_cast<std::uint32_t>(rescue_pixels.size()),
            &rescue_result) == NF_STATUS_OK && rescue_result.succeeded == 1U,
        "v15 Rescue target reaches the shared preview pipeline");
}

void test_v16_scanner_profile_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> baseline_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> profile_pixels(baseline_pixels.size(), 0U);

    nf_develop_export_request_v16 baseline =
        make_request_v16(source_text.c_str(), nullptr);
    nf_develop_export_result_v2 baseline_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &baseline,
            box,
            box,
            baseline_pixels.data(),
            static_cast<std::uint32_t>(baseline_pixels.size()),
            &baseline_result) == NF_STATUS_OK && baseline_result.succeeded == 1U,
        "v16 baseline preview succeeds");

    nf_develop_export_request_v16 profiled = baseline;
    profiled.scanner_profile_id =
        L"noritsu__color-nega__kodak-ultramax-400";
    nf_develop_export_result_v2 profile_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &profiled,
            box,
            box,
            profile_pixels.data(),
            static_cast<std::uint32_t>(profile_pixels.size()),
            &profile_result) == NF_STATUS_OK && profile_result.succeeded == 1U &&
            profile_pixels != baseline_pixels,
        "v16 scanner profile changes the shared preview pixels");

    nf_develop_export_request_v16 common_target = baseline;
    common_target.v15.develop_target = NF_DEVELOP_TARGET_NORITSU;
    std::vector<std::uint8_t> common_target_pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 common_target_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &common_target,
            box,
            box,
            common_target_pixels.data(),
            static_cast<std::uint32_t>(common_target_pixels.size()),
            &common_target_result) == NF_STATUS_OK &&
            common_target_result.succeeded == 1U,
        "v16 NORITSU common relative target preview succeeds");

    nf_develop_export_request_v16 matched_target = common_target;
    matched_target.scanner_profile_id =
        L"noritsu__color-nega__kodak-ektar-100";
    std::vector<std::uint8_t> matched_target_pixels(baseline_pixels.size(), 0U);
    nf_develop_export_result_v2 matched_target_result = make_result_v2();
    expect(
        nf_develop_preview_v16(
            &matched_target,
            box,
            box,
            matched_target_pixels.data(),
            static_cast<std::uint32_t>(matched_target_pixels.size()),
            &matched_target_result) == NF_STATUS_OK &&
            matched_target_result.succeeded == 1U &&
            matched_target_pixels != common_target_pixels,
        "v16 matched profile selects a distinct scanner target signature");
}

void test_v17_positive_film_preview(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    constexpr std::uint32_t box = 128U;
    std::vector<std::uint8_t> negative_pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U,
        0U);
    std::vector<std::uint8_t> positive_pixels(negative_pixels.size(), 0U);

    nf_develop_export_request_v17 negative =
        make_request_v17(source_text.c_str(), nullptr);
    nf_develop_export_result_v2 negative_result = make_result_v2();
    expect(
        nf_develop_preview_v17(
            &negative,
            box,
            box,
            negative_pixels.data(),
            static_cast<std::uint32_t>(negative_pixels.size()),
            &negative_result) == NF_STATUS_OK && negative_result.succeeded == 1U,
        "v17 negative film preview succeeds");

    nf_develop_export_request_v17 positive = negative;
    positive.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_export_result_v2 positive_result = make_result_v2();
    expect(
        nf_develop_preview_v17(
            &positive,
            box,
            box,
            positive_pixels.data(),
            static_cast<std::uint32_t>(positive_pixels.size()),
            &positive_result) == NF_STATUS_OK && positive_result.succeeded == 1U &&
            positive_pixels != negative_pixels,
        "v17 positive film bypasses negative inversion");

    nf_develop_export_request_v17 monochrome = positive;
    monochrome.v16.v15.v14.v13.v12.v11.v10.v9.v8.film_type =
        NF_FILM_TYPE_BLACK_AND_WHITE;
    std::vector<std::uint8_t> monochrome_pixels(negative_pixels.size(), 0U);
    nf_develop_export_result_v2 monochrome_result = make_result_v2();
    expect(
        nf_develop_preview_v17(
            &monochrome,
            box,
            box,
            monochrome_pixels.data(),
            static_cast<std::uint32_t>(monochrome_pixels.size()),
            &monochrome_result) == NF_STATUS_OK &&
            monochrome_result.succeeded == 1U,
        "v17 black-and-white positive film preview succeeds");
    expect(
        preview_is_neutral(monochrome_pixels),
        "v17 black-and-white positive output is neutral");
}

// The point of v22 is that a long call can be stopped and watched. Both facilities are
// checked against a real decode/develop/publish run, not a stub, because the interesting
// failure is a stage that ignores the latch or a progress figure that lies about success.
void test_v22_run_state() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    const std::filesystem::path temporary = std::filesystem::temp_directory_path();
    const std::filesystem::path source =
        temporary / L"negaflow-abi-v22-run-state-source.tif";
    const std::filesystem::path cancelled_output =
        temporary / L"negaflow-abi-v22-cancelled.png";
    const std::filesystem::path completed_output =
        temporary / L"negaflow-abi-v22-completed.png";
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    std::filesystem::remove(cancelled_output, ignored);
    std::filesystem::remove(completed_output, ignored);

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "v22 synthetic TIFF is written");
    if (!std::filesystem::exists(source)) {
        return;
    }

    const std::wstring source_text = source.wstring();
    const std::wstring cancelled_text = cancelled_output.wstring();
    const std::wstring completed_text = completed_output.wstring();

    // A run state already latched before the call must stop at the first poll and leave
    // no artifact. This is the shape a superseded preview request takes.
    nf_develop_export_request_v21 cancelled_request = make_request_v21(
        source_text.c_str(),
        cancelled_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    cancelled_request.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_run_state_v1 cancelled_state = make_run_state();
    cancelled_state.cancel_requested = 1U;
    nf_develop_export_result_v3 cancelled_result = make_result_v3();
    expect(
        nf_develop_export_v22(
            &cancelled_request,
            &cancelled_state,
            &cancelled_result) == NF_STATUS_OK &&
            cancelled_result.succeeded == 0U &&
            cancelled_result.cancelled == 1U &&
            std::strcmp(cancelled_result.failure_name, "cancelled") == 0,
        "v22 reports a cancelled run rather than a failure");
    expect(
        !std::filesystem::exists(cancelled_output),
        "a cancelled export publishes no destination file");

    // The same latch must stop a preview without writing display pixels.
    std::vector<std::uint8_t> cancelled_pixels(
        static_cast<std::size_t>(width) * height * 4U,
        0xABU);
    nf_develop_run_state_v1 cancelled_preview_state = make_run_state();
    cancelled_preview_state.cancel_requested = 1U;
    nf_develop_export_result_v3 cancelled_preview_result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &cancelled_request,
            width,
            height,
            cancelled_pixels.data(),
            static_cast<std::uint32_t>(cancelled_pixels.size()),
            &cancelled_preview_state,
            &cancelled_preview_result) == NF_STATUS_OK &&
            cancelled_preview_result.succeeded == 0U &&
            cancelled_preview_result.cancelled == 1U,
        "v22 preview honours the cancel latch");
    bool preview_untouched = true;
    for (const std::uint8_t value : cancelled_pixels) {
        preview_untouched = preview_untouched && value == 0xABU;
    }
    expect(preview_untouched, "a cancelled preview leaves the caller buffer alone");

    // An untouched run state reaches completion and reports it, and the progress figure
    // is only allowed to say "complete" when the run actually succeeded.
    nf_develop_export_request_v21 completed_request = make_request_v21(
        source_text.c_str(),
        completed_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    completed_request.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_run_state_v1 completed_state = make_run_state();
    nf_develop_export_result_v3 completed_result = make_result_v3();
    expect(
        nf_develop_export_v22(
            &completed_request,
            &completed_state,
            &completed_result) == NF_STATUS_OK &&
            completed_result.succeeded == 1U &&
            completed_result.cancelled == 0U,
        "v22 completes a run whose state was never latched");
    expect(
        completed_state.progress_permille == NF_DEVELOP_PROGRESS_COMPLETE,
        "a successful run leaves progress at complete");
    expect(
        completed_state.stage == NF_DEVELOP_STAGE_OUTPUT,
        "the last stage a successful run reports is the publish");
    expect(
        std::filesystem::exists(completed_output),
        "an uncancelled export publishes its destination file");

    // A null run state keeps the pre-v22 behaviour: the call simply runs to the end.
    std::filesystem::remove(completed_output, ignored);
    nf_develop_export_result_v3 stateless_result = make_result_v3();
    expect(
        nf_develop_export_v22(
            &completed_request,
            nullptr,
            &stateless_result) == NF_STATUS_OK &&
            stateless_result.succeeded == 1U &&
            stateless_result.cancelled == 0U,
        "v22 accepts a null run state and behaves as before");

    // A run state the caller under-declared is refused outright: writing four words into
    // three would corrupt whatever follows it.
    nf_develop_run_state_v1 short_state = make_run_state();
    short_state.struct_size = 4U;
    nf_develop_export_result_v3 short_result = make_result_v3();
    expect(
        nf_develop_export_v22(&completed_request, &short_state, &short_result) ==
            NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized run state is refused");

    std::filesystem::remove(source, ignored);
    std::filesystem::remove(cancelled_output, ignored);
    std::filesystem::remove(completed_output, ignored);
}

// The synthetic checks prove the latch is honoured before the first stage. This one runs
// against a real scan and latches from another thread once the engine reports it has
// started, which is the only way to show the mid-run poll points actually fire.
void test_v22_cancel_during_run(const std::filesystem::path& source) {
    const std::filesystem::path destination =
        std::filesystem::temp_directory_path() / L"negaflow-abi-v22-mid-run.png";
    std::error_code ignored{};
    std::filesystem::remove(destination, ignored);

    const std::wstring source_text = source.wstring();
    const std::wstring destination_text = destination.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(),
        destination_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    nf_develop_run_state_v1 state = make_run_state();
    nf_develop_export_result_v3 result = make_result_v3();

    std::atomic<bool> finished{false};
    std::atomic<bool> observed_start{false};
    std::thread watcher{[&state, &finished, &observed_start]() noexcept {
        while (!finished.load(std::memory_order_relaxed)) {
            const std::uint32_t stage =
                std::atomic_ref<std::uint32_t>(state.stage).load(std::memory_order_relaxed);
            if (stage != NF_DEVELOP_STAGE_NONE) {
                observed_start.store(true, std::memory_order_relaxed);
                std::atomic_ref<std::uint32_t>(state.cancel_requested)
                    .store(1U, std::memory_order_relaxed);
                return;
            }
            std::this_thread::yield();
        }
    }};

    const nf_status_t status = nf_develop_export_v22(&request, &state, &result);
    finished.store(true, std::memory_order_relaxed);
    watcher.join();

    expect(status == NF_STATUS_OK, "v22 mid-run export returns a well formed call");
    if (!observed_start.load(std::memory_order_relaxed)) {
        // The run beat the watcher to the finish. Nothing was cancelled, so the only
        // thing to check is that it behaved like an ordinary successful export.
        expect(
            result.succeeded == 1U && result.cancelled == 0U,
            "an uncancelled real export succeeds");
        std::filesystem::remove(destination, ignored);
        return;
    }

    // Reported so the run log shows which branch was taken rather than leaving the
    // reader to guess whether the interesting one ever executed.
    std::cout << "{\"note\":\"v22_cancelled_mid_run\",\"stage\":"
              << result.failed_stage << ",\"wall_microseconds\":"
              << result.wall_microseconds << "}\n";
    expect(
        result.cancelled == 1U && result.succeeded == 0U,
        "a latch set while the run is in flight stops it");
    expect(
        result.failed_stage != NF_DEVELOP_STAGE_NONE,
        "a cancelled run names the stage it was interrupted in");
    expect(
        !std::filesystem::exists(destination),
        "a run cancelled mid-flight publishes no file");
    std::filesystem::remove(destination, ignored);

    // GrainMend is the one stage long enough that stopping only at its boundary would
    // still leave the user waiting seconds. This latches once the run reports it has
    // reached that stage, which exercises the checks inside detection rather than the
    // boundary check in front of it.
    nf_develop_export_request_v21 defect_request = make_request_v21(
        source_text.c_str(),
        destination_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    defect_request.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .defect_removal_strength = 1.0;
    // The interactive case is a preview, not a publish, so the comparison is measured on
    // previews: the same GrainMend-enabled render, once left alone and once cancelled.
    std::vector<std::uint8_t> defect_pixels(
        static_cast<std::size_t>(512U) * 512U * 4U,
        0U);
    nf_develop_run_state_v1 baseline_state = make_run_state();
    nf_develop_export_result_v3 baseline_result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &defect_request,
            512U,
            512U,
            defect_pixels.data(),
            static_cast<std::uint32_t>(defect_pixels.size()),
            &baseline_state,
            &baseline_result) == NF_STATUS_OK &&
            baseline_result.succeeded == 1U,
        "a GrainMend preview completes when nothing cancels it");
    std::cout << "{\"note\":\"v22_grain_mend_preview_baseline\",\"wall_microseconds\":"
              << baseline_result.wall_microseconds << "}\n";

    nf_develop_run_state_v1 defect_state = make_run_state();
    nf_develop_export_result_v3 defect_result = make_result_v3();

    std::atomic<bool> defect_finished{false};
    std::atomic<bool> reached_grain_mend{false};
    std::thread defect_watcher{[&defect_state, &defect_finished, &reached_grain_mend]() noexcept {
        while (!defect_finished.load(std::memory_order_relaxed)) {
            const std::uint32_t stage =
                std::atomic_ref<std::uint32_t>(defect_state.stage)
                    .load(std::memory_order_relaxed);
            if (stage == NF_DEVELOP_STAGE_GRAIN_MEND) {
                reached_grain_mend.store(true, std::memory_order_relaxed);
                std::atomic_ref<std::uint32_t>(defect_state.cancel_requested)
                    .store(1U, std::memory_order_relaxed);
                return;
            }
            std::this_thread::yield();
        }
    }};

    const nf_status_t defect_status =
        nf_develop_export_v22(&defect_request, &defect_state, &defect_result);
    defect_finished.store(true, std::memory_order_relaxed);
    defect_watcher.join();
    expect(defect_status == NF_STATUS_OK, "the GrainMend run is a well formed call");

    if (reached_grain_mend.load(std::memory_order_relaxed)) {
        std::cout << "{\"note\":\"v22_cancelled_inside_grain_mend\",\"stage\":"
                  << defect_result.failed_stage << ",\"wall_microseconds\":"
                  << defect_result.wall_microseconds << "}\n";
        expect(
            defect_result.cancelled == 1U &&
                defect_result.failed_stage == NF_DEVELOP_STAGE_GRAIN_MEND,
            "a cancel arriving during GrainMend stops inside that stage");
        expect(
            !std::filesystem::exists(destination),
            "a GrainMend cancellation publishes no file");
    }
    std::filesystem::remove(destination, ignored);
}

void test_auto_adjust_on_a_real_scan(const std::filesystem::path& source) {
    // Auto adjust reads a *neutral develop*, meaning the tone sliders at zero but the
    // frame otherwise properly rendered. Feeding it a default manual Dmin produces a
    // rendering that is not a photograph, and auto then correctly pushes every slider to
    // its clamp — which proves nothing about the algorithm. Auto base gives it a real
    // starting image.
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_AUTO);
    constexpr std::uint32_t box = 512U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * box * 4U, 0U);
    nf_develop_export_result_v3 result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            nullptr,
            &result) == NF_STATUS_OK && result.succeeded == 1U,
        "the neutral develop preview auto adjust reads succeeds");

    negaflow::imaging::AutoAdjustStats stats{};
    expect(
        negaflow::imaging::compute_auto_adjust_stats(
            pixels.data(),
            result.image_width,
            result.image_height,
            static_cast<std::size_t>(result.image_width) * 4U,
            stats),
        "statistics come back from a real developed frame");

    const negaflow::imaging::AutoToneResult tone =
        negaflow::imaging::auto_tone(stats);
    const negaflow::imaging::AutoWhiteBalanceResult balance =
        negaflow::imaging::auto_white_balance(stats);
    std::cout << "{\"note\":\"auto_adjust_real_scan\",\"exposure\":" << tone.exposure
              << ",\"contrast\":" << tone.contrast
              << ",\"highlights\":" << tone.highlights
              << ",\"shadows\":" << tone.shadows
              << ",\"whites\":" << tone.whites
              << ",\"blacks\":" << tone.blacks
              << ",\"density\":" << tone.density
              << ",\"vibrance\":" << tone.vibrance
              << ",\"warmth\":" << balance.warmth
              << ",\"tint\":" << balance.tint << "}" << std::endl;

    // The engine refuses values outside these ranges, so auto must never propose one.
    expect(
        tone.exposure >= -3.0 && tone.exposure <= 3.0 &&
            tone.contrast >= -0.45 && tone.contrast <= 0.55 &&
            tone.highlights <= 0.0 && tone.highlights >= -1.0 &&
            tone.shadows >= 0.0 && tone.shadows <= 0.8 &&
            tone.whites >= -1.0 && tone.whites <= 1.0 &&
            tone.blacks >= -1.0 && tone.blacks <= 0.15 &&
            tone.density >= -0.4 && tone.density <= 0.4 &&
            tone.vibrance >= 0.0 && tone.vibrance <= 0.6,
        "every automatic tone value on a real scan is inside the engine's range");
    expect(
        balance.warmth >= -0.6 && balance.warmth <= 0.6 &&
            balance.tint >= -0.6 && balance.tint <= 0.6,
        "the automatic white balance on a real scan is inside its clamp");
}

void test_v18_defect_region_preview_and_export() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    const std::filesystem::path temporary = std::filesystem::temp_directory_path();
    const std::filesystem::path source =
        temporary / L"negaflow-abi-v18-defect-source.tif";
    const std::filesystem::path identity_output =
        temporary / L"negaflow-abi-v18-defect-identity.png";
    const std::filesystem::path repaired_output =
        temporary / L"negaflow-abi-v18-defect-repaired.png";
    const std::filesystem::path mismatched_output =
        temporary / L"negaflow-abi-v19-defect-mismatch.png";
    const std::filesystem::path cloned_output =
        temporary / L"negaflow-abi-v20-clone.png";
    const std::filesystem::path brushed_output =
        temporary / L"negaflow-abi-v21-brush.png";
    const std::filesystem::path infrared_output =
        temporary / L"negaflow-abi-v24-infrared.png";
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    std::filesystem::remove(identity_output, ignored);
    std::filesystem::remove(repaired_output, ignored);
    std::filesystem::remove(mismatched_output, ignored);
    std::filesystem::remove(cloned_output, ignored);
    std::filesystem::remove(brushed_output, ignored);
    std::filesystem::remove(infrared_output, ignored);

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(
            width,
            height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "v18 synthetic defect TIFF is written");
    if (!std::filesystem::exists(source)) {
        return;
    }
    std::array<std::uint8_t, 32U> source_identity{};
    expect(
        sha256(source_bytes, source_identity),
        "v19 source identity is calculated for the synthetic TIFF");

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v18 identity =
        make_request_v18(source_text.c_str(), nullptr, NF_BASE_ESTIMATION_MANUAL);
    identity.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    std::vector<std::uint8_t> identity_pixels(
        static_cast<std::size_t>(width) * height * 4U,
        0U);
    nf_develop_export_result_v2 identity_result = make_result_v2();
    expect(
        nf_develop_preview_v18(
            &identity,
            width,
            height,
            identity_pixels.data(),
            static_cast<std::uint32_t>(identity_pixels.size()),
            &identity_result) == NF_STATUS_OK &&
            identity_result.succeeded == 1U &&
            identity_result.image_width == width &&
            identity_result.image_height == height,
        "v18 identity preview succeeds at source resolution");

    constexpr std::uint32_t roi_x = 24U;
    constexpr std::uint32_t roi_top = 36U;
    constexpr std::uint32_t roi_width = 16U;
    constexpr std::uint32_t roi_height = 24U;
    constexpr std::uint32_t roi_y_up = height - roi_top - roi_height;
    std::vector<std::uint8_t> mask(
        static_cast<std::size_t>(roi_width) * roi_height,
        0U);
    for (std::uint32_t source_y = (height * 5U) / 8U;
         source_y < (height * 7U) / 8U;
         ++source_y) {
        const std::uint32_t local_y = source_y - roi_top;
        mask[static_cast<std::size_t>(local_y) * roi_width + 8U] = 0xffU;
        mask[static_cast<std::size_t>(local_y) * roi_width + 7U] = 0xffU;
    }
    nf_defect_region_edit_v1 edit{};
    edit.enabled = 1U;
    edit.roi_x = roi_x;
    edit.roi_y = roi_y_up;
    edit.width = roi_width;
    edit.height = roi_height;
    edit.mask_stride_bytes = roi_width;
    edit.mask_byte_count = static_cast<std::uint32_t>(mask.size());
    edit.strength = 1.0;
    edit.has_preferred_angle = 1U;
    edit.preferred_angle_degrees = 90.0;

    nf_develop_export_request_v18 repaired = identity;
    repaired.defect_region_edits = &edit;
    repaired.defect_region_edit_count = 1U;
    repaired.defect_mask_bytes = mask.data();
    repaired.defect_mask_byte_count = static_cast<std::uint32_t>(mask.size());
    std::vector<std::uint8_t> repaired_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 repaired_result = make_result_v2();
    const bool repaired_preview_ok =
        nf_develop_preview_v18(
            &repaired,
            width,
            height,
            repaired_pixels.data(),
            static_cast<std::uint32_t>(repaired_pixels.size()),
            &repaired_result) == NF_STATUS_OK &&
        repaired_result.succeeded == 1U;
    expect(
        repaired_preview_ok && repaired_pixels != identity_pixels,
        "v18 ordered region repair changes the shared preview pipeline");

    nf_develop_export_request_v19 bound = make_request_v19(
        source_text.c_str(),
        nullptr,
        NF_BASE_ESTIMATION_MANUAL);
    bound.v18 = repaired;
    bound.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(bound));
    bound.defect_source_file_bytes = source_bytes.size();
    bound.defect_source_sha256 = source_identity.data();
    bound.has_defect_source_identity = 1U;
    std::vector<std::uint8_t> bound_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 bound_result = make_result_v2();
    expect(
        nf_develop_preview_v19(
            &bound,
            width,
            height,
            bound_pixels.data(),
            static_cast<std::uint32_t>(bound_pixels.size()),
            &bound_result) == NF_STATUS_OK &&
            bound_result.succeeded == 1U &&
            bound_pixels == repaired_pixels,
        "v19 matching source identity preserves the shared defect preview pixels");

    nf_defect_clone_point_v1 clone_point{0.75, 0.25};
    nf_defect_clone_stroke_v1 clone_stroke{};
    clone_stroke.point_count = 1U;
    clone_stroke.offset_x = -0.5;
    clone_stroke.diameter_pixels = 10.0;
    clone_stroke.hardness = 1.0;
    nf_defect_clone_edit_v1 clone_edit{};
    clone_edit.enabled = 1U;
    clone_edit.stroke_count = 1U;
    clone_edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 clone_order{
        NF_DEFECT_RECIPE_EDIT_CLONE, 0U};
    nf_develop_export_request_v20 cloned = make_request_v20(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_MANUAL);
    cloned.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    cloned.v19.defect_source_file_bytes = source_bytes.size();
    cloned.v19.defect_source_sha256 = source_identity.data();
    cloned.v19.has_defect_source_identity = 1U;
    cloned.defect_clone_edits = &clone_edit;
    cloned.defect_clone_edit_count = 1U;
    cloned.defect_clone_strokes = &clone_stroke;
    cloned.defect_clone_stroke_count = 1U;
    cloned.defect_clone_points = &clone_point;
    cloned.defect_clone_point_count = 1U;
    cloned.defect_edit_order = &clone_order;
    cloned.defect_edit_order_count = 1U;
    std::vector<std::uint8_t> cloned_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 cloned_result = make_result_v2();
    const bool cloned_preview_ok =
        nf_develop_preview_v20(
            &cloned,
            width,
            height,
            cloned_pixels.data(),
            static_cast<std::uint32_t>(cloned_pixels.size()),
            &cloned_result) == NF_STATUS_OK &&
        cloned_result.succeeded == 1U;
    expect(
        cloned_preview_ok && cloned_pixels != identity_pixels,
        "v20 Clone Stamp changes the shared preview pipeline");

    std::array<nf_defect_brush_point_v1, 2U> brush_points{{
        {0.5, 0.625},
        {0.5, 0.875},
    }};
    nf_defect_brush_stroke_v1 brush_stroke{};
    brush_stroke.point_count = static_cast<std::uint32_t>(brush_points.size());
    brush_stroke.thickness = 0.04;
    nf_defect_brush_edit_v1 brush_edit{};
    brush_edit.enabled = 1U;
    brush_edit.stroke_count = 1U;
    brush_edit.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 brush_order{
        NF_DEFECT_RECIPE_EDIT_BRUSH, 0U};
    nf_develop_export_request_v21 brushed = make_request_v21(
        source_text.c_str(), nullptr, NF_BASE_ESTIMATION_MANUAL);
    brushed.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    brushed.v20.v19.defect_source_file_bytes = source_bytes.size();
    brushed.v20.v19.defect_source_sha256 = source_identity.data();
    brushed.v20.v19.has_defect_source_identity = 1U;
    brushed.v20.defect_edit_order = &brush_order;
    brushed.v20.defect_edit_order_count = 1U;
    brushed.defect_brush_edits = &brush_edit;
    brushed.defect_brush_edit_count = 1U;
    brushed.defect_brush_strokes = &brush_stroke;
    brushed.defect_brush_stroke_count = 1U;
    brushed.defect_brush_points = brush_points.data();
    brushed.defect_brush_point_count =
        static_cast<std::uint32_t>(brush_points.size());
    std::vector<std::uint8_t> brushed_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 brushed_result = make_result_v2();
    const bool brushed_preview_ok =
        nf_develop_preview_v21(
            &brushed,
            width,
            height,
            brushed_pixels.data(),
            static_cast<std::uint32_t>(brushed_pixels.size()),
            &brushed_result) == NF_STATUS_OK &&
        brushed_result.succeeded == 1U;
    expect(
        brushed_preview_ok && brushed_pixels != identity_pixels,
        "v21 Brush changes the shared preview pipeline");

    std::vector<std::uint8_t> infrared_core(mask.size(), 0U);
    std::vector<std::uint8_t> infrared_attenuation(mask.size() * 2U, 0U);
    for (std::size_t offset = 0U;
         offset < infrared_attenuation.size();
         offset += 2U) {
        infrared_attenuation[offset] = 0x00U;
        infrared_attenuation[offset + 1U] = 0x40U;
    }
    nf_defect_region_edit_v1 infrared_region{};
    infrared_region.enabled = 1U;
    infrared_region.roi_x = roi_x;
    infrared_region.roi_y = roi_y_up;
    infrared_region.width = roi_width;
    infrared_region.height = roi_height;
    infrared_region.mask_stride_bytes = roi_width;
    infrared_region.mask_byte_count =
        static_cast<std::uint32_t>(infrared_core.size());
    infrared_region.strength = 1.0;
    nf_defect_recipe_edit_ref_v1 infrared_order{
        NF_DEFECT_RECIPE_EDIT_REGION, 0U};
    nf_defect_infrared_edit_v1 infrared_edit{};
    infrared_edit.has_attenuation = 1U;
    infrared_edit.attenuation_stride_bytes = roi_width * 2U;
    infrared_edit.attenuation_byte_count =
        static_cast<std::uint32_t>(infrared_attenuation.size());
    const std::wstring infrared_output_text = infrared_output.wstring();
    nf_develop_export_request_v24 infrared = make_request_v24(
        source_text.c_str(),
        infrared_output_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    infrared.v21.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    infrared.v21.v20.v19.defect_source_file_bytes = source_bytes.size();
    infrared.v21.v20.v19.defect_source_sha256 = source_identity.data();
    infrared.v21.v20.v19.has_defect_source_identity = 1U;
    infrared.v21.v20.v19.v18.defect_region_edits = &infrared_region;
    infrared.v21.v20.v19.v18.defect_region_edit_count = 1U;
    infrared.v21.v20.v19.v18.defect_mask_bytes = infrared_core.data();
    infrared.v21.v20.v19.v18.defect_mask_byte_count =
        static_cast<std::uint32_t>(infrared_core.size());
    infrared.v21.v20.defect_edit_order = &infrared_order;
    infrared.v21.v20.defect_edit_order_count = 1U;
    infrared.defect_infrared_edits = &infrared_edit;
    infrared.defect_infrared_edit_count = 1U;
    infrared.defect_infrared_attenuation_bytes = infrared_attenuation.data();
    infrared.defect_infrared_attenuation_byte_count =
        static_cast<std::uint32_t>(infrared_attenuation.size());
    std::vector<std::uint8_t> infrared_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v3 infrared_preview_result = make_result_v3();
    const bool infrared_preview_ok =
        nf_develop_preview_v24(
            &infrared,
            nullptr,
            width,
            height,
            infrared_pixels.data(),
            static_cast<std::uint32_t>(infrared_pixels.size()),
            nullptr,
            &infrared_preview_result) == NF_STATUS_OK &&
        infrared_preview_result.succeeded == 1U;
    bool infrared_changed_inside = false;
    bool infrared_unchanged_outside = true;
    if (infrared_preview_ok) {
        for (std::uint32_t y = 0U; y < height; ++y) {
            for (std::uint32_t x = 0U; x < width; ++x) {
                const std::size_t offset =
                    (static_cast<std::size_t>(y) * width + x) * 4U;
                const bool changed = std::memcmp(
                    identity_pixels.data() + offset,
                    infrared_pixels.data() + offset,
                    4U) != 0;
                const bool inside = x >= roi_x && x < roi_x + roi_width &&
                    y >= roi_top && y < roi_top + roi_height;
                infrared_changed_inside =
                    infrared_changed_inside || (inside && changed);
                infrared_unchanged_outside =
                    infrared_unchanged_outside && (inside || !changed);
            }
        }
    }
    expect(
        infrared_preview_ok && infrared_changed_inside &&
            infrared_unchanged_outside,
        "v24 attenuation-only infrared replay changes only its ROI with a zero core");

    std::array<std::uint8_t, 32U> wrong_digest = source_identity;
    wrong_digest[0] ^= 0xffU;
    nf_develop_export_request_v19 mismatched = bound;
    mismatched.defect_source_sha256 = wrong_digest.data();
    std::vector<std::uint8_t> mismatched_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 mismatched_result = make_result_v2();
    expect(
        nf_develop_preview_v19(
            &mismatched,
            width,
            height,
            mismatched_pixels.data(),
            static_cast<std::uint32_t>(mismatched_pixels.size()),
            &mismatched_result) == NF_STATUS_OK &&
            mismatched_result.succeeded == 0U &&
            mismatched_result.failed_stage ==
                NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE &&
            std::strcmp(
                mismatched_result.failure_name,
                "defect_source_identity_mismatch") == 0,
        "v19 mismatched source identity fails before decode and repair");
    if (repaired_preview_ok) {
        bool changed_inside = false;
        bool unchanged_outside = true;
        for (std::uint32_t y = 0U; y < height; ++y) {
            for (std::uint32_t x = 0U; x < width; ++x) {
                const std::size_t offset =
                    (static_cast<std::size_t>(y) * width + x) * 4U;
                const bool changed = std::memcmp(
                    identity_pixels.data() + offset,
                    repaired_pixels.data() + offset,
                    4U) != 0;
                const bool inside = x >= roi_x && x < roi_x + roi_width &&
                    y >= roi_top && y < roi_top + roi_height;
                changed_inside = changed_inside || (inside && changed);
                unchanged_outside = unchanged_outside && (inside || !changed);
            }
        }
        expect(
            changed_inside && unchanged_outside,
            "v18 converts bottom-origin ROI y and confines repair to that raw region");
    }

    nf_defect_region_edit_v1 outside = edit;
    outside.roi_x = width - roi_width + 1U;
    nf_develop_export_request_v18 invalid = repaired;
    invalid.defect_region_edits = &outside;
    std::vector<std::uint8_t> invalid_pixels(identity_pixels.size(), 0U);
    nf_develop_export_result_v2 invalid_result = make_result_v2();
    expect(
        nf_develop_preview_v18(
            &invalid,
            width,
            height,
            invalid_pixels.data(),
            static_cast<std::uint32_t>(invalid_pixels.size()),
            &invalid_result) == NF_STATUS_OK &&
            invalid_result.succeeded == 0U &&
            invalid_result.failed_stage ==
                NF_DEVELOP_STAGE_DEFECT_COMPONENT_REPAIR &&
            std::strcmp(invalid_result.failure_name, "invalid_argument") == 0,
        "v18 out-of-frame ROI fails closed at the component repair stage");

    const std::wstring identity_output_text = identity_output.wstring();
    nf_develop_export_request_v18 identity_export = make_request_v18(
        source_text.c_str(),
        identity_output_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    identity_export.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_export_result_v2 identity_export_result = make_result_v2();
    const bool identity_export_ok =
        nf_develop_export_v18(&identity_export, &identity_export_result) ==
            NF_STATUS_OK &&
        identity_export_result.succeeded == 1U;

    const std::wstring cloned_output_text = cloned_output.wstring();
    cloned.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        cloned_output_text.c_str();
    nf_develop_export_result_v2 cloned_export_result = make_result_v2();
    const bool cloned_export_ok =
        nf_develop_export_v20(&cloned, &cloned_export_result) == NF_STATUS_OK &&
        cloned_export_result.succeeded == 1U;
    expect(
        identity_export_ok && cloned_export_ok &&
            read_file(identity_output) != read_file(cloned_output),
        "v20 Clone Stamp changes the shared export pipeline");

    const std::wstring brushed_output_text = brushed_output.wstring();
    brushed.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        brushed_output_text.c_str();
    nf_develop_export_result_v2 brushed_export_result = make_result_v2();
    const bool brushed_export_ok =
        nf_develop_export_v21(&brushed, &brushed_export_result) == NF_STATUS_OK &&
        brushed_export_result.succeeded == 1U;
    expect(
        identity_export_ok && brushed_export_ok &&
            read_file(identity_output) != read_file(brushed_output),
        "v21 Brush changes the shared export pipeline");

    nf_develop_export_result_v3 infrared_export_result = make_result_v3();
    const bool infrared_export_ok =
        nf_develop_export_v24(
            &infrared, nullptr, &infrared_export_result) == NF_STATUS_OK &&
        infrared_export_result.succeeded == 1U;
    const std::vector<std::uint8_t> infrared_export_pixels =
        infrared_export_ok
            ? decode_png_bgra8(infrared_output, width, height)
            : std::vector<std::uint8_t>{};
    unsigned maximum_infrared_difference = 0U;
    if (infrared_export_pixels.size() == infrared_pixels.size()) {
        for (std::size_t index = 0U; index < infrared_pixels.size(); ++index) {
            maximum_infrared_difference = std::max(
                maximum_infrared_difference,
                static_cast<unsigned>(std::abs(
                    static_cast<int>(infrared_export_pixels[index]) -
                    static_cast<int>(infrared_pixels[index]))));
        }
    }
    expect(
        infrared_preview_ok && infrared_export_ok &&
            infrared_export_pixels.size() == infrared_pixels.size() &&
            maximum_infrared_difference <= 1U,
        "v24 infrared preview and PNG16 export agree at 8-bit codec quantization");

    const std::wstring repaired_output_text = repaired_output.wstring();
    nf_develop_export_request_v19 repaired_export = bound;
    repaired_export.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        repaired_output_text.c_str();
    nf_develop_export_result_v2 repaired_export_result = make_result_v2();
    const bool repaired_export_ok =
        nf_develop_export_v19(&repaired_export, &repaired_export_result) ==
            NF_STATUS_OK &&
        repaired_export_result.succeeded == 1U;
    expect(
        identity_export_ok && repaired_export_ok,
        "v18 identity and repaired exports both publish");
    if (identity_export_ok && repaired_export_ok) {
        const std::vector<std::uint8_t> identity_file = read_file(identity_output);
        const std::vector<std::uint8_t> repaired_file = read_file(repaired_output);
        expect(
            !identity_file.empty() && !repaired_file.empty() &&
                identity_file != repaired_file,
            "v19 source-bound region repair changes the shared export pipeline");
    }

    const std::wstring mismatched_output_text = mismatched_output.wstring();
    mismatched.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.destination_path =
        mismatched_output_text.c_str();
    mismatched_result = make_result_v2();
    expect(
        nf_develop_export_v19(&mismatched, &mismatched_result) == NF_STATUS_OK &&
            mismatched_result.succeeded == 0U &&
            mismatched_result.failed_stage ==
                NF_DEVELOP_STAGE_OBSERVE_SOURCE_BEFORE &&
            !std::filesystem::exists(mismatched_output),
        "v19 source mismatch publishes no output artifact");
    expect(
        read_file(source) == source_bytes,
        "ordered defect preview and export leave the source TIFF byte-exact");
    std::array<std::uint8_t, 32U> source_identity_after{};
    const std::vector<std::uint8_t> source_bytes_after = read_file(source);
    expect(
        sha256(source_bytes_after, source_identity_after) &&
            source_identity_after == source_identity,
        "v24 infrared preview and export preserve the source SHA-256");

    std::filesystem::remove(source, ignored);
    std::filesystem::remove(identity_output, ignored);
    std::filesystem::remove(repaired_output, ignored);
    std::filesystem::remove(mismatched_output, ignored);
    std::filesystem::remove(cloned_output, ignored);
    std::filesystem::remove(brushed_output, ignored);
    std::filesystem::remove(infrared_output, ignored);
}

}  // namespace

// Soft proof exists only on the preview. There is no export entry point that accepts one,
// which is the structural half of the guarantee; this covers the behavioural half.
void test_v23_soft_proof_preview() {
    const std::uint32_t width = 96U;
    const std::uint32_t height = 64U;
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() / "negaflow_abi_v23_soft_proof.tif";

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "v23 synthetic TIFF is written");
    if (!std::filesystem::exists(source)) {
        return;
    }

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(),
        L"unused.png",
        NF_BASE_ESTIMATION_MANUAL);
    request.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;

    const std::size_t pixel_bytes = static_cast<std::size_t>(width) * height * 4U;
    const auto render = [&](const nf_soft_proof_v1* const proof,
                            std::vector<std::uint8_t>& pixels) {
        pixels.assign(pixel_bytes, 0U);
        nf_develop_export_result_v3 result = make_result_v3();
        const nf_status_t status = nf_develop_preview_v23(
            &request,
            proof,
            width,
            height,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            nullptr,
            &result);
        return status == NF_STATUS_OK && result.succeeded == 1U;
    };

    // The v22 pixels are the reference. Every way of saying "no proof" has to reproduce
    // them byte for byte, or the affine is not an identity when it is switched off.
    std::vector<std::uint8_t> reference(pixel_bytes, 0U);
    nf_develop_export_result_v3 reference_result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &request,
            width,
            height,
            reference.data(),
            static_cast<std::uint32_t>(reference.size()),
            nullptr,
            &reference_result) == NF_STATUS_OK &&
            reference_result.succeeded == 1U,
        "the unproofed v22 preview renders");

    std::vector<std::uint8_t> pixels{};
    expect(render(nullptr, pixels), "v23 renders with a null soft proof");
    expect(pixels == reference, "a null soft proof reproduces the v22 preview exactly");

    nf_soft_proof_v1 disabled = make_soft_proof();
    expect(render(&disabled, pixels), "v23 renders with proofing switched off");
    expect(pixels == reference, "a disabled soft proof reproduces the v22 preview exactly");

    // Profile-only proofing selects the space the frame is shown in. It is not a change
    // to the values, so the pixels the engine hands back must not move.
    nf_soft_proof_v1 profile_only = make_soft_proof();
    profile_only.enabled = 1U;
    expect(render(&profile_only, pixels), "v23 renders in profile-only proofing");
    expect(
        pixels == reference,
        "profile-only proofing does not alter the rendered values");

    // A dim, warm paper, the shape a press profile has. The ink is heavier than any real
    // one: this frame never gets darker than code 103, so a realistic ink would put the
    // floor below everything in it and the bound would pass without being tested. The
    // three channels differ so a transposed channel cannot go unnoticed.
    constexpr float paper_white[3] = {0.877F, 0.877F, 0.906F};
    constexpr float black_ink[3] = {0.20F, 0.19F, 0.22F};
    nf_soft_proof_v1 paper = make_soft_proof();
    paper.enabled = 1U;
    paper.simulate_paper_and_black_ink = 1U;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        paper.paper_white_rgb[channel] = paper_white[channel];
        paper.black_ink_rgb[channel] = black_ink[channel];
    }
    expect(render(&paper, pixels), "v23 renders the paper and ink simulation");
    expect(
        pixels != reference,
        "simulating paper and ink changes the picture");

    // The two claims the feature actually makes: a print cannot be brighter than its
    // paper, and it cannot be darker than its ink. Both bounds are computed through the
    // same encode the preview quantises in, with one code of slack for the dither.
    const auto encoded_code = [](const float linear) {
        return negaflow::color::linear_to_srgb_encoded(linear) * 255.0F;
    };
    // Guard against a vacuous pass: the bounds only mean something if the unproofed frame
    // actually reaches outside them.
    std::uint8_t reference_low = 0xFFU;
    std::uint8_t reference_high = 0U;
    for (std::size_t offset = 0U; offset < reference.size(); offset += 4U) {
        for (std::size_t slot = 0U; slot < 3U; ++slot) {
            reference_low = std::min(reference_low, reference[offset + slot]);
            reference_high = std::max(reference_high, reference[offset + slot]);
        }
    }
    expect(
        static_cast<float>(reference_low) < encoded_code(black_ink[1]),
        "the unproofed frame goes darker than the ink, so the floor is a real bound");
    expect(
        static_cast<float>(reference_high) > encoded_code(paper_white[1]),
        "the unproofed frame goes brighter than the paper, so the ceiling is a real bound");

    bool within_paper = true;
    bool above_ink = true;
    bool opaque = true;
    // BGRA, so buffer slot 0 is blue and slot 2 is red.
    const std::size_t channel_of_slot[3] = {2U, 1U, 0U};
    for (std::size_t offset = 0U; offset < pixels.size(); offset += 4U) {
        for (std::size_t slot = 0U; slot < 3U; ++slot) {
            const std::size_t channel = channel_of_slot[slot];
            // A linear 1 maps to scale + bias, which is the paper white; a linear 0 maps
            // to the bias, which is the ink.
            const float ceiling = encoded_code(paper_white[channel]) + 1.5F;
            const float floor_value = encoded_code(black_ink[channel]) - 1.5F;
            const float value = static_cast<float>(pixels[offset + slot]);
            within_paper = within_paper && value <= ceiling;
            above_ink = above_ink && value >= floor_value;
        }
        opaque = opaque && pixels[offset + 3U] == 0xFFU;
    }
    expect(within_paper, "no proofed pixel is brighter than the simulated paper");
    expect(above_ink, "no proofed pixel is darker than the simulated ink");
    expect(opaque, "the proofed preview stays opaque");

    // Under-declaring the struct would let the engine read past what the caller owns.
    nf_soft_proof_v1 short_proof = make_soft_proof();
    short_proof.struct_size = 8U;
    std::vector<std::uint8_t> ignored_pixels(pixel_bytes, 0U);
    nf_develop_export_result_v3 short_result = make_result_v3();
    expect(
        nf_develop_preview_v23(
            &request,
            &short_proof,
            width,
            height,
            ignored_pixels.data(),
            static_cast<std::uint32_t>(ignored_pixels.size()),
            nullptr,
            &short_result) == NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized soft proof struct is refused");

    std::error_code ignored;
    std::filesystem::remove(source, ignored);
}

void test_read_soft_proof_media() {
    nf_soft_proof_media_v1 media{};
    media.struct_size = static_cast<std::uint32_t>(sizeof(media));
    expect(
        nf_read_soft_proof_media_v1(nullptr, 0U, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "a null result is refused");

    nf_soft_proof_media_v1 short_media{};
    short_media.struct_size = 8U;
    expect(
        nf_read_soft_proof_media_v1(nullptr, 0U, &short_media) ==
            NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized media struct is refused");

    // No profile at all is a legitimate state - proofing simply has nothing to simulate -
    // so it reports an unusable profile rather than failing the call.
    expect(
        nf_read_soft_proof_media_v1(nullptr, 0U, &media) == NF_STATUS_OK &&
            media.is_rgb_output_profile == 0U && media.has_white == 0U &&
            media.has_black == 0U,
        "an absent profile reads as unusable rather than as an error");

    const std::filesystem::path installed =
        "C:\\Windows\\System32\\spool\\drivers\\color\\sRGB Color Space Profile.icm";
    if (!std::filesystem::exists(installed)) {
        std::cout << "skipped (sRGB profile not installed)\n";
        return;
    }
    std::ifstream file(installed, std::ios::binary);
    std::istreambuf_iterator<char> first(file);
    const std::istreambuf_iterator<char> last{};
    const std::vector<std::uint8_t> bytes(first, last);
    media.struct_size = static_cast<std::uint32_t>(sizeof(media));
    expect(
        nf_read_soft_proof_media_v1(
            bytes.data(),
            static_cast<std::uint32_t>(bytes.size()),
            &media) == NF_STATUS_OK &&
            media.is_rgb_output_profile == 1U && media.has_white == 1U,
        "the installed sRGB profile is a usable proof destination");
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect(
            std::abs(media.paper_white_rgb[channel] - 1.0F) < 0.002F,
            "a display profile proofs as identity across the boundary");
    }
}

// The parity claim, made against a real negative and the profiles actually installed on
// this machine: choosing any of them as the proof destination leaves the frame alone,
// which is what macOS produces from its built-ins. If the resolver trusted a v2 `wtpt`
// this would fail on sRGB and Adobe RGB, whose declared white is D65.
void test_soft_proof_on_a_real_scan(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(),
        L"unused.png",
        NF_BASE_ESTIMATION_AUTO);

    const std::uint32_t extent = 512U;
    const std::size_t pixel_bytes = static_cast<std::size_t>(extent) * extent * 4U;
    std::vector<std::uint8_t> reference(pixel_bytes, 0U);
    nf_develop_export_result_v3 reference_result = make_result_v3();
    if (nf_develop_preview_v23(
            &request,
            nullptr,
            extent,
            extent,
            reference.data(),
            static_cast<std::uint32_t>(reference.size()),
            nullptr,
            &reference_result) != NF_STATUS_OK ||
        reference_result.succeeded != 1U) {
        expect(false, "the real scan renders an unproofed preview");
        return;
    }

    const char* const installed[] = {
        "sRGB Color Space Profile.icm",
        "AdobeRGB1998.icc",
        "eciRGB_v2.icc",
        "WideGamutRGB.icc",
    };
    std::size_t checked_profiles = 0U;
    std::vector<std::uint8_t> proofed(pixel_bytes, 0U);
    for (const char* const name : installed) {
        std::filesystem::path path =
            "C:\\Windows\\System32\\spool\\drivers\\color";
        path /= name;
        if (!std::filesystem::exists(path)) {
            continue;
        }
        std::ifstream file(path, std::ios::binary);
        std::istreambuf_iterator<char> first(file);
        const std::istreambuf_iterator<char> last{};
        const std::vector<std::uint8_t> bytes(first, last);

        nf_soft_proof_media_v1 media{};
        media.struct_size = static_cast<std::uint32_t>(sizeof(media));
        if (nf_read_soft_proof_media_v1(
                bytes.data(),
                static_cast<std::uint32_t>(bytes.size()),
                &media) != NF_STATUS_OK ||
            media.is_rgb_output_profile != 1U) {
            expect(false, name);
            continue;
        }

        nf_soft_proof_v1 proof = make_soft_proof();
        proof.enabled = 1U;
        proof.simulate_paper_and_black_ink = 1U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper_white_rgb[channel] = media.paper_white_rgb[channel];
            proof.black_ink_rgb[channel] = media.black_ink_rgb[channel];
        }

        proofed.assign(pixel_bytes, 0U);
        nf_develop_export_result_v3 result = make_result_v3();
        const bool rendered =
            nf_develop_preview_v23(
                &request,
                &proof,
                extent,
                extent,
                proofed.data(),
                static_cast<std::uint32_t>(proofed.size()),
                nullptr,
                &result) == NF_STATUS_OK &&
            result.succeeded == 1U;
        expect(rendered, "the real scan renders a proofed preview");
        if (!rendered) {
            continue;
        }

        std::uint32_t largest_difference = 0U;
        for (std::size_t index = 0U; index < proofed.size(); ++index) {
            const std::uint32_t difference = static_cast<std::uint32_t>(
                std::abs(static_cast<int>(proofed[index]) -
                         static_cast<int>(reference[index])));
            largest_difference = std::max(largest_difference, difference);
        }
        if (largest_difference != 0U) {
            std::cerr << "FAIL: " << name << " moved the frame by "
                      << largest_difference << " codes\n";
            ++failures;
        }
        // Reported rather than asserted. The affine runs unconditionally, so what matters
        // is that carrying it costs nothing worth measuring next to the sRGB encode it
        // sits beside; a threshold here would only fail on a busy machine.
        std::cout << name << ": unproofed " << reference_result.wall_microseconds
                  << " us, proofed " << result.wall_microseconds << " us\n";
        ++checked_profiles;
    }
    expect(
        checked_profiles != 0U,
        "at least one installed display profile was measured against the scan");
}

int main(const int argument_count, const char* const arguments[]) {
    test_argument_contract();
    test_request_validation();
    test_v2_contract();
    test_v3_contract();
    test_v4_contract();
    test_v5_contract();
    test_v6_contract();
    test_v7_contract();
    test_v8_contract();
    test_v9_contract();
    test_v10_contract();
    test_v11_contract();
    test_v12_contract();
    test_v18_contract();
    test_v19_contract();
    test_v20_contract();
    test_v21_contract();
    test_v24_contract();
    test_missing_source_is_not_a_validation_error();
    test_v2_missing_source_is_not_a_validation_error();
    test_v18_defect_region_preview_and_export();
    test_v22_run_state();
    test_v23_soft_proof_preview();
    test_read_soft_proof_media();

    if (argument_count >= 2) {
        const std::filesystem::path source{arguments[1]};
        if (std::filesystem::exists(source)) {
            test_full_develop(source);
            test_preview(source);
            test_v2_auto_develop(source);
            test_v2_auto_preview(source);
            test_v3_basic_tone_preview(source);
            test_v4_film_preview(source);
            test_v5_point_curve_preview(source);
            test_v6_color_mixer_preview(source);
            test_v8_grain_mend_preview(source);
            test_v9_film_scan_denoise_preview(source);
            test_v10_texture_preview(source);
            test_v11_bw_transform_preview(source);
            test_v11_rendered_digital_preview(source);
            test_v12_local_dodge_burn_preview(source);
            test_v13_color_model_preview(source);
            test_v14_scene_correction_preview(source);
            test_v15_develop_target_preview(source);
            test_v16_scanner_profile_preview(source);
            test_v17_positive_film_preview(source);
            test_v22_cancel_during_run(source);
            test_auto_adjust_on_a_real_scan(source);
            test_soft_proof_on_a_real_scan(source);
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
