#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <Windows.h>
#include <icm.h>

#include <cstdint>
#include <span>

namespace negaflow::imaging::detail {

class IcmRgb16Transform final {
public:
    IcmRgb16Transform() noexcept = default;
    IcmRgb16Transform(const IcmRgb16Transform&) = delete;
    IcmRgb16Transform& operator=(const IcmRgb16Transform&) = delete;
    ~IcmRgb16Transform() noexcept;

    /// 원본에 박힌 ICC 에서 표준 sRGB 로 옮깁니다. 스캐너 입력이 지나는 길입니다.
    [[nodiscard]] ScannerToWorkingStatus initialize(
        std::span<const std::uint8_t> source_profile_bytes,
        std::uint32_t& native_error_code);

    /// 표준 sRGB 에서 <b>주어진 프로파일</b>로 옮깁니다. 내보내기가 인화소 ICC 로 나갈 때
    /// 지나는 길이며, macOS 가 `ExportEngine.write(outputProfile:)` 에서 출력 색공간을
    /// 그 프로파일로 바꾸는 자리와 같습니다.
    [[nodiscard]] ScannerToWorkingStatus initialize_to_profile(
        std::span<const std::uint8_t> destination_profile_bytes,
        std::uint32_t& native_error_code);

    /// 8 비트 RGB 를 옮깁니다. 인화소 ICC 로 나가는 JPEG·8bit TIFF 가 지나는 길입니다.
    [[nodiscard]] ScannerToWorkingStatus translate8(
        const std::uint8_t* source,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t source_stride_bytes,
        std::uint8_t* destination,
        std::uint32_t destination_stride_bytes,
        std::uint32_t& native_error_code) const noexcept;

    [[nodiscard]] ScannerToWorkingStatus translate(
        const std::uint16_t* source,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t source_stride_bytes,
        std::uint16_t* destination,
        std::uint32_t destination_stride_bytes,
        std::uint32_t& native_error_code,
        PBMCALLBACKFN progress_callback = nullptr,
        LPARAM callback_data = 0) const noexcept;

private:
    void reset() noexcept;

    /// 두 프로파일을 이어 변환을 만듭니다. 두 initialize 가 같이 씁니다.
    [[nodiscard]] ScannerToWorkingStatus link(std::uint32_t& native_error_code);

    HPROFILE source_profile_{nullptr};
    HPROFILE destination_profile_{nullptr};
    HTRANSFORM transform_{nullptr};
};

}  // namespace negaflow::imaging::detail
