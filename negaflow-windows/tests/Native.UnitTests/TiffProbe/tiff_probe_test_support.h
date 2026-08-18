#pragma once

/* TIFF probe suite 가 공유하는 타입과 선언입니다. 바이트를 어떻게 짓는지는
   tiff_probe_test_fixtures.cpp 가, 무엇을 검사할지는 각 suite 파일이 소유합니다. */

#include "negaflow/core/tiff_probe.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

namespace tiff_probe_tests {

using negaflow::core::TiffByteOrder;
using negaflow::core::TiffOrganization;
using negaflow::core::TiffProbeLimits;
using negaflow::core::TiffProbeStatus;
using negaflow::core::TiffVariant;

// 실패 개수는 suite 전체가 공유합니다. 각 번역 단위가 자기 것을 세면 main 이 합계를 낼 수
// 없습니다.
extern int failures;

void expect(bool condition, const char* message);

// --- 바이트 조립: 엔디안에 맞춰 값을 붙이고 IFD 항목을 씁니다 ---------------------------
void append_u16(std::vector<std::uint8_t>& bytes, std::uint16_t value, TiffByteOrder order);
void append_u32(std::vector<std::uint8_t>& bytes, std::uint32_t value, TiffByteOrder order);
void append_u64(std::vector<std::uint8_t>& bytes, std::uint64_t value, TiffByteOrder order);

[[nodiscard]] std::array<std::uint8_t, 8> inline_short(std::uint16_t value, TiffByteOrder order);
[[nodiscard]] std::array<std::uint8_t, 8> inline_u32(std::uint32_t value, TiffByteOrder order);
[[nodiscard]] std::array<std::uint8_t, 8> inline_u64(std::uint64_t value, TiffByteOrder order);
[[nodiscard]] std::array<std::uint8_t, 8> inline_three_shorts(
    std::uint16_t value,
    TiffByteOrder order);

void append_classic_entry(
    std::vector<std::uint8_t>& bytes,
    TiffByteOrder order,
    std::uint16_t tag,
    std::uint16_t type,
    std::uint32_t count,
    const std::array<std::uint8_t, 8>& value);

void append_big_entry(
    std::vector<std::uint8_t>& bytes,
    TiffByteOrder order,
    std::uint16_t tag,
    std::uint16_t type,
    std::uint64_t count,
    const std::array<std::uint8_t, 8>& value);

// --- fixture: 검사할 TIFF 를 손으로 짓습니다 -----------------------------------------
// probe 가 어느 디렉터리를 고르는지 보려면 축소본을 함께 넣은 파일이 필요합니다.
struct DirectoryPage final {
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t new_subfile_type;
};

[[nodiscard]] std::vector<std::uint8_t> make_classic_tiff(TiffByteOrder order);
[[nodiscard]] std::vector<std::uint8_t> make_classic_multi_directory_tiff(
    TiffByteOrder order,
    const std::vector<DirectoryPage>& pages);
[[nodiscard]] std::vector<std::uint8_t> make_classic_tiled_tiff(TiffByteOrder order);
[[nodiscard]] std::vector<std::uint8_t> make_classic_rgba_tiff(TiffByteOrder order);
[[nodiscard]] std::vector<std::uint8_t> make_bigtiff(TiffByteOrder order);

void patch_u16(
    std::vector<std::uint8_t>& bytes,
    std::size_t offset,
    std::uint16_t value,
    TiffByteOrder order);
void patch_u32(
    std::vector<std::uint8_t>& bytes,
    std::size_t offset,
    std::uint32_t value,
    TiffByteOrder order);

void write_fixture(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes);
[[nodiscard]] std::vector<std::uint8_t> read_fixture(const std::filesystem::path& path);

void expect_status(
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& bytes,
    TiffProbeStatus expected_status,
    const char* message,
    const TiffProbeLimits& limits = {});

class MemoryTiffReader final : public negaflow::core::TiffRandomAccessReader {
public:
    explicit MemoryTiffReader(const std::vector<std::uint8_t>& bytes) noexcept : bytes_(bytes) {}

    [[nodiscard]] std::uint64_t size() const noexcept override {
        return bytes_.size();
    }

    [[nodiscard]] bool read(
        const std::uint64_t offset,
        std::uint8_t* const destination,
        const std::size_t byte_count) const noexcept override {
        if (destination == nullptr || offset > bytes_.size() ||
            byte_count > bytes_.size() - static_cast<std::size_t>(offset)) {
            return false;
        }
        std::copy_n(
            bytes_.data() + static_cast<std::size_t>(offset),
            byte_count,
            destination);
        return true;
    }

private:
    const std::vector<std::uint8_t>& bytes_;
};

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-tiff-probe-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary test directory is created");
    }

    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;

    ~TempDirectory() {
        std::error_code error{};
        for (const auto& entry : std::filesystem::directory_iterator(path_, error)) {
            SetFileAttributesW(entry.path().c_str(), FILE_ATTRIBUTE_NORMAL);
        }
        error.clear();
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_{};
};

// --- suite: 읽기 계약, 정상 배치, 깨진 파일, 디렉터리 선택 -------------------------------
void test_random_access_reader_contract();
void test_valid_classic_and_original_unchanged(const std::filesystem::path& root);
void test_valid_big_endian_variants(const std::filesystem::path& root);
void test_valid_tiled(const std::filesystem::path& root);
void test_extra_samples(const std::filesystem::path& root);
void test_malformed_and_limits(const std::filesystem::path& root);
void test_multi_directory_selection(const std::filesystem::path& root);

}  // namespace tiff_probe_tests
