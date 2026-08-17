#include "develop_export_abi_test_support.h"

#include <cstring>

namespace negaflow::develop_export_abi_tests {

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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
    nf_develop_export_request_v10 request{};
    request.v9 = make_request_v9(source, destination, base_mode);
    request.v9.v8.struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v11 make_request_v11(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
    nf_develop_export_request_v12 request{};
    request.v11 = make_request_v11(source, destination, base_mode);
    request.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v13 make_request_v13(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v13 request{};
    request.v12 = make_request_v12(source, destination, base_mode);
    request.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v14 make_request_v14(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v14 request{};
    request.v13 = make_request_v13(source, destination, base_mode);
    request.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v15 make_request_v15(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v15 request{};
    request.v14 = make_request_v14(source, destination, base_mode);
    request.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v16 make_request_v16(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v16 request{};
    request.v15 = make_request_v15(source, destination, base_mode);
    request.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v17 make_request_v17(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
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
    const std::uint32_t base_mode) {
    nf_develop_export_request_v18 request{};
    request.v17 = make_request_v17(source, destination, base_mode);
    request.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v19 make_request_v19(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v19 request{};
    request.v18 = make_request_v18(source, destination, base_mode);
    request.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v20 make_request_v20(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v20 request{};
    request.v19 = make_request_v19(source, destination, base_mode);
    request.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v21 make_request_v21(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v21 request{};
    request.v20 = make_request_v20(source, destination, base_mode);
    request.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v24 make_request_v24(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v24 request{};
    request.v21 = make_request_v21(source, destination, base_mode);
    request.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size =
        static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v25 make_request_v25(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v25 request;
    std::memset(&request, 0, sizeof(request));
    request.v24 = make_request_v24(source, destination, base_mode);
    auto& v18 = request.v24.v21.v20.v19.v18;
    v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v26 make_request_v26(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v26 request;
    std::memset(&request, 0, sizeof(request));
    request.v25 = make_request_v25(source, destination, base_mode);
    request.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v27 make_request_v27(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v27 request;
    std::memset(&request, 0, sizeof(request));
    request.v26 = make_request_v26(source, destination, base_mode);
    request.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v28 make_request_v28(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v28 request;
    std::memset(&request, 0, sizeof(request));
    request.v27 = make_request_v27(source, destination, base_mode);
    request.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .struct_size = static_cast<std::uint32_t>(sizeof(request));
    request.jpeg_quality = 1.0F;
    return request;
}

[[nodiscard]] nf_develop_export_request_v29 make_request_v29(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v29 request;
    std::memset(&request, 0, sizeof(request));
    request.v28 = make_request_v28(source, destination, base_mode);
    request.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

[[nodiscard]] nf_develop_export_request_v30 make_request_v30(
    const wchar_t* const source,
    const wchar_t* const destination,
    const std::uint32_t base_mode) {
    nf_develop_export_request_v30 request;
    std::memset(&request, 0, sizeof(request));
    request.v29 = make_request_v29(source, destination, base_mode);
    request.v29.v28.v27.v26.v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .struct_size = static_cast<std::uint32_t>(sizeof(request));
    return request;
}

}  // namespace negaflow::develop_export_abi_tests
