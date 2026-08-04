#pragma once

#include <Windows.h>
#include <objidl.h>
#include <wrl/client.h>

#include <cstdint>
#include <filesystem>
#include <memory>

namespace negaflow::output::detail {

enum class AtomicOutputStatus : std::uint8_t {
    ok = 0,
    invalid_path,
    destination_exists,
    destination_query_failed,
    parent_unavailable,
    staging_create_failed,
    allocation_failed,
    flush_failed,
    publish_failed,
    published_file_invalid,
};

class AtomicOutputFile final {
public:
    AtomicOutputFile(const AtomicOutputFile&) = delete;
    AtomicOutputFile& operator=(const AtomicOutputFile&) = delete;
    ~AtomicOutputFile() noexcept;

    [[nodiscard]] static AtomicOutputStatus create(
        const std::filesystem::path& final_path,
        std::unique_ptr<AtomicOutputFile>& output,
        std::uint32_t& native_error_code);

    [[nodiscard]] IStream* stream() const noexcept;
    [[nodiscard]] const std::filesystem::path& staging_path() const noexcept;

    [[nodiscard]] AtomicOutputStatus close_and_flush(
        std::uint32_t& native_error_code) noexcept;

    [[nodiscard]] AtomicOutputStatus publish(
        std::uint64_t expected_file_bytes,
        std::uint32_t& native_error_code) noexcept;

    void discard(std::uint32_t& native_error_code) noexcept;

private:
    AtomicOutputFile(
        std::filesystem::path final_path,
        std::filesystem::path staging_path,
        Microsoft::WRL::ComPtr<IStream> stream) noexcept;

    std::filesystem::path final_path_{};
    std::filesystem::path staging_path_{};
    Microsoft::WRL::ComPtr<IStream> stream_{};
    bool published_{false};
};

}  // namespace negaflow::output::detail
