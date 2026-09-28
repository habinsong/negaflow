#pragma once

#include "icm_rgb16_transform.h"

#include <cstdint>
#include <memory>
#include <span>
#include <vector>

namespace negaflow::imaging::detail {

// 원본 ICC 에서 sRGB 로 옮기는 `IcmRgb16Transform` 을 행 갈래마다 하나씩 둡니다.
//
// ICM 은 화소마다 따로 옮기므로 행을 나눠 옮겨도 값이 같습니다. 다만 변환 핸들 하나를 여러
// 스레드가 함께 써도 되는지는 문서에 없어서 갈래마다 같은 두 프로파일로 핸들을 따로 만듭니다.
// 스캔 한 장(3600x2406)을 한 스레드로 옮기는 데 196 ms 였습니다.
class ParallelIcmRgb16Transform final {
public:
    [[nodiscard]] ScannerToWorkingStatus initialize(
        std::span<const std::uint8_t> source_profile_bytes,
        std::uint32_t& native_error_code);

    [[nodiscard]] ScannerToWorkingStatus translate(
        const std::uint16_t* source,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t source_stride_bytes,
        std::uint16_t* destination,
        std::uint32_t destination_stride_bytes,
        std::uint32_t& native_error_code,
        PBMCALLBACKFN progress_callback = nullptr,
        LPARAM callback_data = 0) noexcept;

private:
    std::vector<std::uint8_t> profile_{};
    std::vector<std::unique_ptr<IcmRgb16Transform>> transforms_{};
};

}  // namespace negaflow::imaging::detail
