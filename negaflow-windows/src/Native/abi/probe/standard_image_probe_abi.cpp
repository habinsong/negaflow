#include "negaflow/abi/source_probe.h"

#include "negaflow/imageio/wic_standard_image_decoder.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <system_error>

// 표준 이미지와 카메라 RAW 의 **원본 정보만** 읽습니다.
//
// 화소는 만들지 않습니다. 예전에는 이 자리가 `decode_standard_image_with_wic` 로 파일을
// 끝까지 현상하고, 그 결과의 전 화소를 훑어 불투명 여부를 검사한 뒤, 전부 버리고
// 가로·세로·파일크기만 썼습니다. 실측(2026-08-26, 제조사별 RAW 8 장)으로 파일당 1~13 초,
// 8 장에 peak 980 MB 였고 폴더 가져오기가 그 때문에 무너졌습니다.
//
// 불투명 검사는 macOS 에 없는 Windows 만의 관문이었습니다. macOS 는
// `CGImageSourceCopyPropertiesAtIndex` 로 크기만 읽고 알파를 이유로 거르지 않습니다.
// 그 관문을 유지하려면 화소를 다 만들어야 하고, 그것이 이 함수를 무겁게 만든 이유입니다.

nf_status_t NF_CALL nf_probe_standard_image_source_v1(
    const wchar_t* const source_path,
    nf_standard_image_source_info_v1* const result) {
    if (result == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (source_path == nullptr || source_path[0] == L'\0') return NF_STATUS_INVALID_ARGUMENT;

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    try {
        const auto probed = negaflow::imageio::probe_standard_image_metadata(
            std::filesystem::path{source_path});
        if (probed.status != negaflow::imageio::StandardImageMetadataStatus::ok) {
            result->status =
                probed.status == negaflow::imageio::StandardImageMetadataStatus::unsupported
                ? NF_STANDARD_IMAGE_SOURCE_PROBE_UNSUPPORTED
                : NF_STANDARD_IMAGE_SOURCE_PROBE_UNREADABLE;
            return NF_STATUS_OK;
        }
        std::error_code error;
        const std::uintmax_t bytes = std::filesystem::file_size(source_path, error);
        if (error || bytes == 0U || bytes > std::numeric_limits<std::uint64_t>::max()) {
            result->status = NF_STANDARD_IMAGE_SOURCE_PROBE_UNREADABLE;
            return NF_STATUS_OK;
        }
        result->status = NF_STANDARD_IMAGE_SOURCE_PROBE_OK;
        result->pixel_width = probed.metadata.pixel_width;
        result->pixel_height = probed.metadata.pixel_height;
        // 디코더 계약이 rgba16 · unassociated alpha · orientation 적용 완료이므로, 이 값들은
        // 파일이 아니라 **디코드 결과**를 서술합니다. 예전 구현도 같은 상수를 썼습니다.
        result->samples_per_pixel = 4U;
        result->bits_per_sample = 16U;
        result->sample_format = 1U;
        result->orientation = 1U;
        result->file_bytes = static_cast<std::uint64_t>(bytes);
        return NF_STATUS_OK;
    } catch (...) {
        result->status = NF_STANDARD_IMAGE_SOURCE_PROBE_UNREADABLE;
        return NF_STATUS_OK;
    }
}


// 촬영 기록만 읽습니다. 화소도, 크기도 만들지 않습니다 - 현상 인스펙터 머리줄이 한 장을
// 열 때만 부릅니다(macOS `DevelopInspectorHeaderSummary.importedMetadata` 자리).
nf_status_t NF_CALL nf_probe_image_shot_v1(
    const wchar_t* const source_path,
    nf_image_shot_info_v1* const result) {
    if (result == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (source_path == nullptr || source_path[0] == L'\0') return NF_STATUS_INVALID_ARGUMENT;

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    try {
        const auto probed = negaflow::imageio::probe_source_shot_metadata(
            std::filesystem::path{source_path});
        if (probed.status != negaflow::imageio::StandardImageMetadataStatus::ok) {
            result->status =
                probed.status == negaflow::imageio::StandardImageMetadataStatus::unsupported
                ? NF_IMAGE_SHOT_PROBE_UNSUPPORTED
                : NF_IMAGE_SHOT_PROBE_UNREADABLE;
            return NF_STATUS_OK;
        }
        result->status = NF_IMAGE_SHOT_PROBE_OK;
        if (probed.shot.has_iso_speed) {
            result->present_mask |= NF_IMAGE_SHOT_HAS_ISO_SPEED;
            result->iso_speed = probed.shot.iso_speed;
        }
        if (probed.shot.has_exposure_time) {
            result->present_mask |= NF_IMAGE_SHOT_HAS_EXPOSURE_TIME;
            result->exposure_time_seconds = probed.shot.exposure_time_seconds;
        }
        if (probed.shot.has_f_number) {
            result->present_mask |= NF_IMAGE_SHOT_HAS_F_NUMBER;
            result->f_number = probed.shot.f_number;
        }
        if (probed.shot.has_focal_length) {
            result->present_mask |= NF_IMAGE_SHOT_HAS_FOCAL_LENGTH;
            result->focal_length_mm = probed.shot.focal_length_mm;
        }
        return NF_STATUS_OK;
    } catch (...) {
        result->status = NF_IMAGE_SHOT_PROBE_UNREADABLE;
        return NF_STATUS_OK;
    }
}
