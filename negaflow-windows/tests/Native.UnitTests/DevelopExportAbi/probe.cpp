#include <cstdio>
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

    // 촬영 기록 프로브. 이 PNG 는 우리가 내보낸 것이라 EXIF 촬영 태그가 없으므로, 값을
    // 지어내지 않고 `present_mask` 를 비운 채 성공해야 합니다 - 없는 태그에 숫자를 채우면
    // 화면이 거짓말을 합니다.
    expect(
        nf_probe_image_shot_v1(nullptr, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "a null image shot result is refused");
    nf_image_shot_info_v1 short_shot{};
    short_shot.struct_size = 8U;
    expect(
        nf_probe_image_shot_v1(imported.c_str(), &short_shot) == NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized image shot result is refused");
    nf_image_shot_info_v1 shot{};
    shot.struct_size = static_cast<std::uint32_t>(sizeof(shot));
    expect(
        nf_probe_image_shot_v1(imported.c_str(), &shot) == NF_STATUS_OK &&
            shot.status == NF_IMAGE_SHOT_PROBE_OK && shot.present_mask == 0U &&
            shot.iso_speed == 0U && shot.exposure_time_seconds == 0.0 &&
            shot.f_number == 0.0 && shot.focal_length_mm == 0.0,
        "the image shot probe leaves absent EXIF tags absent");

    // v38 — 판 프록시 입력 해상도. 0 이면 v37 과 같은 그림이 나와야 하고, 값을 주면 그
    // 크기로 **풀어서** 나와야 합니다. 콘택트 시트 한 칸을 채우려고 원본을 통째로 푸는 것을
    // 막는 자리이며, macOS `proxyInputLongEdge` 와 같은 뜻입니다.
    {
        const std::filesystem::path proxy_destination =
            std::filesystem::temp_directory_path() / L"negaflow-proxy-output.png";
        std::filesystem::remove(proxy_destination, ignored);
        const std::wstring proxy_text = proxy_destination.wstring();
        nf_develop_export_request_v27 proxy_seed = make_request_v27(
            imported_text.c_str(), proxy_text.c_str());
        proxy_seed.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
            .film_look_source_kind = NF_DEVELOP_SOURCE_RENDERED_DIGITAL;
        proxy_seed.v26.v25.v24.v21.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
        // `{}` 로 0 초기화하면 MSVC 의 중첩 이니셜라이저 한계(C1054)에 걸립니다 — 이
        // 구조체는 v8 부터 스물여덟 겹입니다. 바이트로 지우고 필요한 칸만 채웁니다.
        nf_develop_export_request_v38 proxy;
        std::memset(&proxy, 0, sizeof(proxy));
        proxy.v37.v36.v35.v34.v33.v32.v31.v30.v29.v28.v27 = proxy_seed;
        proxy.v37.v36.v35.v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17
            .v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
            static_cast<std::uint32_t>(sizeof(proxy));
        // v31 이후 판은 출력 심도를 요구합니다. v27 씨앗만으로는 0 이라 매핑이
        // `invalid_output_bit_depth` 로 멈춥니다.
        proxy.v37.v36.v35.v34.v33.v32.v31.output_bit_depth = 16U;
        proxy.proxy_input_long_edge = 64U;
        nf_develop_export_result_v3 proxy_result = make_result_v3();
        const nf_status_t proxy_status =
            nf_develop_export_v38(&proxy, nullptr, &proxy_result);
        if (proxy_result.succeeded != 1U) {
            std::printf(
                "proxy export status=%u stage=%u name=%s native=0x%X\n",
                static_cast<unsigned>(proxy_status),
                static_cast<unsigned>(proxy_result.failed_stage),
                proxy_result.failure_name,
                static_cast<unsigned>(proxy_result.native_error_code));
        }
        expect(
            proxy_status == NF_STATUS_OK && proxy_result.succeeded == 1U &&
                std::filesystem::exists(proxy_destination),
            "a proxy-decode export publishes a file");
        // 원본보다 작게 풀렸는지는 나온 그림의 긴 변으로 봅니다 — 상한이 실제로 걸렸다는
        // 증거이고, 이것이 콘택트 시트가 빨라지는 이유 그대로입니다.
        expect(
            proxy_result.image_width <= 64U && proxy_result.image_height <= 64U,
            "a proxy-decode export decodes at the requested long edge");
        // 구조체가 작으면 거부합니다. 다른 판과 같은 규칙입니다.
        nf_develop_export_request_v38 short_proxy = proxy;
        short_proxy.v37.v36.v35.v34.v33.v32.v31.v30.v29.v28.v27.v26.v25.v24.v21.v20.v19
            .v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size = 8U;
        nf_develop_export_result_v3 short_result = make_result_v3();
        expect(
            nf_develop_export_v38(&short_proxy, nullptr, &short_result) ==
                NF_STATUS_STRUCT_TOO_SMALL,
            "an undersized v38 request is refused");
        std::filesystem::remove(proxy_destination, ignored);
    }

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
