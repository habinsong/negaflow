#include "negaflow/core/tiff_probe.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

using negaflow::core::TiffByteOrder;
using negaflow::core::TiffOrganization;
using negaflow::core::TiffProbeLimits;
using negaflow::core::TiffProbeStatus;
using negaflow::core::TiffVariant;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void append_u16(
    std::vector<std::uint8_t>& bytes,
    const std::uint16_t value,
    const TiffByteOrder order) {
    if (order == TiffByteOrder::little_endian) {
        bytes.push_back(static_cast<std::uint8_t>(value & 0xffU));
        bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xffU));
    } else {
        bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xffU));
        bytes.push_back(static_cast<std::uint8_t>(value & 0xffU));
    }
}

void append_u32(
    std::vector<std::uint8_t>& bytes,
    const std::uint32_t value,
    const TiffByteOrder order) {
    if (order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            bytes.push_back(static_cast<std::uint8_t>((value >> (index * 8U)) & 0xffU));
        }
    } else {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            const std::uint32_t shift = (3U - index) * 8U;
            bytes.push_back(static_cast<std::uint8_t>((value >> shift) & 0xffU));
        }
    }
}

void append_u64(
    std::vector<std::uint8_t>& bytes,
    const std::uint64_t value,
    const TiffByteOrder order) {
    if (order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            bytes.push_back(static_cast<std::uint8_t>((value >> (index * 8U)) & 0xffU));
        }
    } else {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            const std::uint32_t shift = (7U - index) * 8U;
            bytes.push_back(static_cast<std::uint8_t>((value >> shift) & 0xffU));
        }
    }
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_short(
    const std::uint16_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u16(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    result[0] = encoded[0];
    result[1] = encoded[1];
    return result;
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_u32(
    const std::uint32_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u32(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    for (std::size_t index = 0; index < 4U; ++index) {
        result[index] = encoded[index];
    }
    return result;
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_u64(
    const std::uint64_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u64(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    for (std::size_t index = 0; index < result.size(); ++index) {
        result[index] = encoded[index];
    }
    return result;
}

[[nodiscard]] std::array<std::uint8_t, 8> inline_three_shorts(
    const std::uint16_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u16(encoded, value, order);
    append_u16(encoded, value, order);
    append_u16(encoded, value, order);
    std::array<std::uint8_t, 8> result{};
    for (std::size_t index = 0; index < encoded.size(); ++index) {
        result[index] = encoded[index];
    }
    return result;
}

void append_classic_entry(
    std::vector<std::uint8_t>& bytes,
    const TiffByteOrder order,
    const std::uint16_t tag,
    const std::uint16_t type,
    const std::uint32_t count,
    const std::array<std::uint8_t, 8>& value) {
    append_u16(bytes, tag, order);
    append_u16(bytes, type, order);
    append_u32(bytes, count, order);
    bytes.insert(bytes.end(), value.begin(), value.begin() + 4);
}

void append_big_entry(
    std::vector<std::uint8_t>& bytes,
    const TiffByteOrder order,
    const std::uint16_t tag,
    const std::uint16_t type,
    const std::uint64_t count,
    const std::array<std::uint8_t, 8>& value) {
    append_u16(bytes, tag, order);
    append_u16(bytes, type, order);
    append_u64(bytes, count, order);
    bytes.insert(bytes.end(), value.begin(), value.end());
}

[[nodiscard]] std::vector<std::uint8_t> make_classic_tiff(const TiffByteOrder order) {
    constexpr std::uint32_t ifd_offset = 8U;
    constexpr std::uint16_t entry_count = 12U;
    constexpr std::uint32_t bits_offset = 158U;
    constexpr std::uint32_t sample_format_offset = 164U;
    constexpr std::uint32_t pixel_offset = 170U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 42U, order);
    append_u32(bytes, ifd_offset, order);
    append_u16(bytes, entry_count, order);
    append_classic_entry(bytes, order, 256U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(bytes, order, 257U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 258U, 3U, 3U, inline_u32(bits_offset, order));
    append_classic_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(bytes, order, 273U, 4U, 1U, inline_u32(pixel_offset, order));
    append_classic_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 277U, 3U, 1U, inline_short(3U, order));
    append_classic_entry(bytes, order, 278U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 279U, 4U, 1U, inline_u32(12U, order));
    append_classic_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(
        bytes,
        order,
        339U,
        3U,
        3U,
        inline_u32(sample_format_offset, order));
    append_u32(bytes, 0U, order);
    append_u16(bytes, 16U, order);
    append_u16(bytes, 16U, order);
    append_u16(bytes, 16U, order);
    append_u16(bytes, 1U, order);
    append_u16(bytes, 1U, order);
    append_u16(bytes, 1U, order);
    for (std::uint8_t value = 0U; value < 12U; ++value) {
        bytes.push_back(value);
    }
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_classic_tiled_tiff(
    const TiffByteOrder order) {
    constexpr std::uint32_t ifd_offset = 8U;
    constexpr std::uint16_t entry_count = 13U;
    constexpr std::uint32_t bits_offset = 170U;
    constexpr std::uint32_t sample_format_offset = 176U;
    constexpr std::uint32_t tile_offsets_offset = 182U;
    constexpr std::uint32_t tile_byte_counts_offset = 198U;
    constexpr std::uint32_t pixel_offset = 214U;
    constexpr std::uint32_t tile_bytes = 24U;
    constexpr std::uint32_t tile_count = 4U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 42U, order);
    append_u32(bytes, ifd_offset, order);
    append_u16(bytes, entry_count, order);
    append_classic_entry(bytes, order, 256U, 4U, 1U, inline_u32(4U, order));
    append_classic_entry(bytes, order, 257U, 4U, 1U, inline_u32(3U, order));
    append_classic_entry(bytes, order, 258U, 3U, 3U, inline_u32(bits_offset, order));
    append_classic_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 277U, 3U, 1U, inline_short(3U, order));
    append_classic_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 322U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(bytes, order, 323U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(
        bytes,
        order,
        324U,
        4U,
        tile_count,
        inline_u32(tile_offsets_offset, order));
    append_classic_entry(
        bytes,
        order,
        325U,
        4U,
        tile_count,
        inline_u32(tile_byte_counts_offset, order));
    append_classic_entry(
        bytes,
        order,
        339U,
        3U,
        3U,
        inline_u32(sample_format_offset, order));
    append_u32(bytes, 0U, order);
    for (std::uint32_t index = 0U; index < 3U; ++index) {
        append_u16(bytes, 16U, order);
    }
    for (std::uint32_t index = 0U; index < 3U; ++index) {
        append_u16(bytes, 1U, order);
    }
    for (std::uint32_t index = 0U; index < tile_count; ++index) {
        append_u32(bytes, pixel_offset + index * tile_bytes, order);
    }
    for (std::uint32_t index = 0U; index < tile_count; ++index) {
        append_u32(bytes, tile_bytes, order);
    }
    for (std::uint32_t index = 0U; index < tile_count * tile_bytes; ++index) {
        bytes.push_back(static_cast<std::uint8_t>(index));
    }
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_classic_rgba_tiff(
    const TiffByteOrder order) {
    constexpr std::uint32_t ifd_offset = 8U;
    constexpr std::uint16_t entry_count = 13U;
    constexpr std::uint32_t bits_offset = 170U;
    constexpr std::uint32_t sample_format_offset = 178U;
    constexpr std::uint32_t pixel_offset = 186U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 42U, order);
    append_u32(bytes, ifd_offset, order);
    append_u16(bytes, entry_count, order);
    append_classic_entry(bytes, order, 256U, 4U, 1U, inline_u32(2U, order));
    append_classic_entry(bytes, order, 257U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 258U, 3U, 4U, inline_u32(bits_offset, order));
    append_classic_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(bytes, order, 273U, 4U, 1U, inline_u32(pixel_offset, order));
    append_classic_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 277U, 3U, 1U, inline_short(4U, order));
    append_classic_entry(bytes, order, 278U, 4U, 1U, inline_u32(1U, order));
    append_classic_entry(bytes, order, 279U, 4U, 1U, inline_u32(16U, order));
    append_classic_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_classic_entry(bytes, order, 338U, 3U, 1U, inline_short(2U, order));
    append_classic_entry(
        bytes,
        order,
        339U,
        3U,
        4U,
        inline_u32(sample_format_offset, order));
    append_u32(bytes, 0U, order);
    for (std::uint32_t index = 0U; index < 4U; ++index) {
        append_u16(bytes, 16U, order);
    }
    for (std::uint32_t index = 0U; index < 4U; ++index) {
        append_u16(bytes, 1U, order);
    }
    for (std::uint8_t value = 0U; value < 16U; ++value) {
        bytes.push_back(value);
    }
    return bytes;
}

[[nodiscard]] std::vector<std::uint8_t> make_bigtiff(const TiffByteOrder order) {
    constexpr std::uint64_t ifd_offset = 16U;
    constexpr std::uint64_t entry_count = 12U;
    constexpr std::uint64_t pixel_offset = 272U;

    std::vector<std::uint8_t> bytes{};
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    bytes.push_back(order == TiffByteOrder::little_endian ? 'I' : 'M');
    append_u16(bytes, 43U, order);
    append_u16(bytes, 8U, order);
    append_u16(bytes, 0U, order);
    append_u64(bytes, ifd_offset, order);
    append_u64(bytes, entry_count, order);
    append_big_entry(bytes, order, 256U, 4U, 1U, inline_u32(2U, order));
    append_big_entry(bytes, order, 257U, 4U, 1U, inline_u32(1U, order));
    append_big_entry(bytes, order, 258U, 3U, 3U, inline_three_shorts(16U, order));
    append_big_entry(bytes, order, 259U, 3U, 1U, inline_short(1U, order));
    append_big_entry(bytes, order, 262U, 3U, 1U, inline_short(2U, order));
    append_big_entry(bytes, order, 273U, 16U, 1U, inline_u64(pixel_offset, order));
    append_big_entry(bytes, order, 274U, 3U, 1U, inline_short(1U, order));
    append_big_entry(bytes, order, 277U, 3U, 1U, inline_short(3U, order));
    append_big_entry(bytes, order, 278U, 4U, 1U, inline_u32(1U, order));
    append_big_entry(bytes, order, 279U, 16U, 1U, inline_u64(12U, order));
    append_big_entry(bytes, order, 284U, 3U, 1U, inline_short(1U, order));
    append_big_entry(bytes, order, 339U, 3U, 3U, inline_three_shorts(1U, order));
    append_u64(bytes, 0U, order);
    for (std::uint8_t value = 0U; value < 12U; ++value) {
        bytes.push_back(value);
    }
    return bytes;
}

void patch_u16(
    std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::uint16_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u16(encoded, value, order);
    bytes[offset] = encoded[0];
    bytes[offset + 1U] = encoded[1];
}

void patch_u32(
    std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::uint32_t value,
    const TiffByteOrder order) {
    std::vector<std::uint8_t> encoded{};
    append_u32(encoded, value, order);
    for (std::size_t index = 0; index < encoded.size(); ++index) {
        bytes[offset + index] = encoded[index];
    }
}

void write_fixture(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size()));
    output.close();
    expect(output.good(), "synthetic TIFF fixture is written");
}

[[nodiscard]] std::vector<std::uint8_t> read_fixture(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    return std::vector<std::uint8_t>(
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>());
}

void expect_status(
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& bytes,
    const TiffProbeStatus expected_status,
    const char* const message,
    const TiffProbeLimits& limits = {}) {
    write_fixture(path, bytes);
    const auto result = negaflow::core::probe_tiff_file(path, limits);
    expect(result.status == expected_status, message);
}

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

void test_random_access_reader_contract() {
    const auto bytes = make_classic_tiff(TiffByteOrder::little_endian);
    const MemoryTiffReader reader{bytes};
    const auto result = negaflow::core::probe_tiff(reader);

    expect(result.status == TiffProbeStatus::ok, "random-access reader probes");
    expect(result.info.file_bytes == bytes.size(), "reader size is preserved");
    expect(result.info.width == 2U && result.info.height == 1U, "reader dimensions match");
}

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

void test_valid_classic_and_original_unchanged(const std::filesystem::path& root) {
    const auto bytes = make_classic_tiff(TiffByteOrder::little_endian);
    const std::filesystem::path path = root / L"읽기 전용 원본.tiff";
    write_fixture(path, bytes);
    const auto modified_before = std::filesystem::last_write_time(path);
    expect(
        SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_READONLY) != 0,
        "fixture is marked read-only");

    const auto result = negaflow::core::probe_tiff_file(path);
    expect(result.status == TiffProbeStatus::ok, "little-endian Classic TIFF probes");
    expect(result.info.variant == TiffVariant::classic, "Classic TIFF variant is reported");
    expect(
        result.info.byte_order == TiffByteOrder::little_endian,
        "little-endian byte order is reported");
    expect(result.info.width == 2U && result.info.height == 1U, "dimensions are reported");
    expect(result.info.samples_per_pixel == 3U, "sample count is reported");
    expect(
        result.info.bits_per_sample_count == 3U && result.info.bits_per_sample[2] == 16U,
        "per-channel bit depths are reported");
    expect(result.info.segment_count == 1U, "strip count is reported");
    expect(result.info.packed_raster_bytes == 12U, "packed raster size is checked");
    expect(result.info.working_rgba32f_bytes == 32U, "working buffer size is checked");
    expect(read_fixture(path) == bytes, "probe leaves original bytes unchanged");
    expect(
        std::filesystem::last_write_time(path) == modified_before,
        "probe leaves original modification time unchanged");
    expect(
        (GetFileAttributesW(path.c_str()) & FILE_ATTRIBUTE_READONLY) != 0U,
        "probe leaves original read-only attribute unchanged");
    SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
}

void test_valid_big_endian_variants(const std::filesystem::path& root) {
    const std::filesystem::path classic_path = root / L"classic-big-endian.tif";
    const auto classic = make_classic_tiff(TiffByteOrder::big_endian);
    write_fixture(classic_path, classic);
    const auto classic_result = negaflow::core::probe_tiff_file(classic_path);
    expect(classic_result.status == TiffProbeStatus::ok, "big-endian Classic TIFF probes");
    expect(
        classic_result.info.byte_order == TiffByteOrder::big_endian,
        "big-endian Classic order is reported");

    const std::filesystem::path big_path = root / L"bigtiff-big-endian.tif";
    const auto big = make_bigtiff(TiffByteOrder::big_endian);
    write_fixture(big_path, big);
    const auto big_result = negaflow::core::probe_tiff_file(big_path);
    expect(big_result.status == TiffProbeStatus::ok, "big-endian BigTIFF probes");
    expect(big_result.info.variant == TiffVariant::big, "BigTIFF variant is reported");
    expect(big_result.info.width == 2U && big_result.info.height == 1U, "BigTIFF dimensions work");
}

void test_valid_tiled(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"classic-tiled.tif";
    const auto bytes = make_classic_tiled_tiff(TiffByteOrder::little_endian);
    write_fixture(path, bytes);

    const auto result = negaflow::core::probe_tiff_file(path);
    expect(result.status == TiffProbeStatus::ok, "tiled Classic TIFF probes");
    expect(result.info.organization == TiffOrganization::tiled, "tiled organization is reported");
    expect(result.info.width == 4U && result.info.height == 3U, "tiled dimensions are reported");
    expect(result.info.segment_count == 4U, "edge tiles are included in tile count");
    expect(result.info.packed_raster_bytes == 72U, "tiled packed raster size is checked");
    expect(result.info.working_rgba32f_bytes == 192U, "tiled working buffer size is checked");

    auto wrong_tile_count = bytes;
    patch_u32(wrong_tile_count, 134U, 3U, TiffByteOrder::little_endian);
    expect_status(
        path,
        wrong_tile_count,
        TiffProbeStatus::invalid_layout,
        "tile array count must match geometry");
}

void test_extra_samples(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"classic-rgba.tif";
    const auto bytes = make_classic_rgba_tiff(TiffByteOrder::little_endian);
    write_fixture(path, bytes);

    const auto result = negaflow::core::probe_tiff_file(path);
    expect(result.status == TiffProbeStatus::ok, "RGBA Classic TIFF probes");
    expect(result.info.samples_per_pixel == 4U, "RGBA sample count is reported");
    expect(
        result.info.extra_samples_count == 1U && result.info.extra_samples[0] == 2U,
        "unassociated alpha ExtraSamples value is reported");

    auto invalid_extra_sample = bytes;
    patch_u16(invalid_extra_sample, 150U, 3U, TiffByteOrder::little_endian);
    expect_status(
        path,
        invalid_extra_sample,
        TiffProbeStatus::invalid_layout,
        "invalid ExtraSamples value is rejected");
}

void test_malformed_and_limits(const std::filesystem::path& root) {
    const std::filesystem::path path = root / L"malformed.tif";
    const auto valid = make_classic_tiff(TiffByteOrder::little_endian);

    expect_status(
        path,
        std::vector<std::uint8_t>{'I', 'I', 42U, 0U},
        TiffProbeStatus::truncated_header,
        "truncated header is rejected");

    auto invalid_header = valid;
    invalid_header[0] = 'X';
    expect_status(
        path,
        invalid_header,
        TiffProbeStatus::invalid_header,
        "invalid byte-order signature is rejected");

    auto invalid_ifd = valid;
    patch_u32(invalid_ifd, 4U, 0xfffffff0U, TiffByteOrder::little_endian);
    expect_status(
        path,
        invalid_ifd,
        TiffProbeStatus::truncated_ifd,
        "out-of-file IFD offset is rejected");

    TiffProbeLimits entry_limits{};
    entry_limits.max_ifd_entries = 4U;
    expect_status(
        path,
        valid,
        TiffProbeStatus::ifd_entry_limit_exceeded,
        "IFD entry limit is enforced",
        entry_limits);

    auto zero_width = valid;
    patch_u32(zero_width, 18U, 0U, TiffByteOrder::little_endian);
    expect_status(
        path,
        zero_width,
        TiffProbeStatus::invalid_dimensions,
        "zero width is rejected");

    auto external_array_past_end = valid;
    patch_u32(external_array_past_end, 42U, 0xfffffff0U, TiffByteOrder::little_endian);
    expect_status(
        path,
        external_array_past_end,
        TiffProbeStatus::tag_data_out_of_bounds,
        "external tag array past EOF is rejected");

    auto segment_past_end = valid;
    patch_u32(segment_past_end, 78U, 0xfffffff0U, TiffByteOrder::little_endian);
    expect_status(
        path,
        segment_past_end,
        TiffProbeStatus::tag_data_out_of_bounds,
        "strip offset plus byte count past EOF is rejected");

    auto duplicate_width = valid;
    patch_u16(duplicate_width, 22U, 256U, TiffByteOrder::little_endian);
    expect_status(
        path,
        duplicate_width,
        TiffProbeStatus::duplicate_tag,
        "duplicate critical tag is rejected");

    auto oversized_icc = valid;
    patch_u16(oversized_icc, 10U, 34675U, TiffByteOrder::little_endian);
    patch_u16(oversized_icc, 12U, 7U, TiffByteOrder::little_endian);
    patch_u32(oversized_icc, 14U, 20U * 1024U * 1024U, TiffByteOrder::little_endian);
    expect_status(
        path,
        oversized_icc,
        TiffProbeStatus::tag_limit_exceeded,
        "oversized ICC claim is rejected before allocation");

    auto multiple_directories = valid;
    patch_u32(multiple_directories, 154U, 8U, TiffByteOrder::little_endian);
    expect_status(
        path,
        multiple_directories,
        TiffProbeStatus::multiple_directories_unsupported,
        "multiple IFD policy is explicit");

    TiffProbeLimits memory_limits{};
    memory_limits.max_working_rgba32f_bytes = 16U;
    expect_status(
        path,
        valid,
        TiffProbeStatus::working_memory_limit_exceeded,
        "working RGBA32F memory limit is enforced",
        memory_limits);
}

}  // namespace

int main() {
    TempDirectory temporary{};
    test_random_access_reader_contract();
    test_valid_classic_and_original_unchanged(temporary.path());
    test_valid_big_endian_variants(temporary.path());
    test_valid_tiled(temporary.path());
    test_extra_samples(temporary.path());
    test_malformed_and_limits(temporary.path());

    if (failures != 0) {
        std::cerr << failures << " TIFF probe test(s) failed\n";
        return 1;
    }
    std::cout << "TIFF probe tests passed\n";
    return 0;
}
