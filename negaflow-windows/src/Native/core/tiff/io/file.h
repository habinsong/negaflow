#pragma once

#include "negaflow/core/tiff_probe.h"

#include <Windows.h>

#include <cstdint>
#include <filesystem>

namespace negaflow::core::tiff_probe_detail {

// Win32 읽기 전용 무작위 접근. probe 가 쓰는 TiffRandomAccessReader 구현이다.
class ReadOnlyFile final : public TiffRandomAccessReader {
public:
    ReadOnlyFile() noexcept = default;
    ReadOnlyFile(const ReadOnlyFile&) = delete;
    ReadOnlyFile& operator=(const ReadOnlyFile&) = delete;

    ~ReadOnlyFile() noexcept override;

    [[nodiscard]] bool open(const std::filesystem::path& path) noexcept;

    [[nodiscard]] std::uint64_t size() const noexcept override;

    [[nodiscard]] bool read(
        std::uint64_t offset,
        std::uint8_t* destination,
        std::size_t byte_count) const noexcept override;

private:
    HANDLE handle_{INVALID_HANDLE_VALUE};
    std::uint64_t size_{0};
};

}  // namespace negaflow::core::tiff_probe_detail
