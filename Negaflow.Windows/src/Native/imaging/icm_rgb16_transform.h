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
        LPARAM callback_data = 0) const noexcept;

private:
    void reset() noexcept;

    HPROFILE source_profile_{nullptr};
    HPROFILE destination_profile_{nullptr};
    HTRANSFORM transform_{nullptr};
};

}  // namespace negaflow::imaging::detail
