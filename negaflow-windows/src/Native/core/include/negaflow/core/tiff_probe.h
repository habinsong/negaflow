#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <stop_token>

namespace negaflow::core {

enum class TiffProbeStatus : std::uint8_t {
    ok = 0,
    io_error,
    file_limit_exceeded,
    truncated_header,
    invalid_header,
    invalid_bigtiff_header,
    invalid_ifd_offset,
    ifd_entry_limit_exceeded,
    truncated_ifd,
    invalid_tag,
    duplicate_tag,
    tag_data_out_of_bounds,
    tag_limit_exceeded,
    invalid_dimensions,
    invalid_layout,
    segment_limit_exceeded,
    compressed_data_limit_exceeded,
    invalid_compressed_data,
    working_memory_limit_exceeded,
    // No single full-resolution image: either every directory is marked as a
    // reduced-resolution or mask page, or several claim to be the full image.
    multiple_directories_unsupported,
    directory_limit_exceeded,
    cancelled,
};

enum class TiffVariant : std::uint8_t {
    classic = 0,
    big,
};

enum class TiffByteOrder : std::uint8_t {
    little_endian = 0,
    big_endian,
};

enum class TiffOrganization : std::uint8_t {
    stripped = 0,
    tiled,
};

struct TiffProbeLimits final {
    std::uint64_t max_file_bytes{0x7fff'ffff'ffff'ffffULL};
    std::uint64_t max_ifd_entries{4'096ULL};
    // A scan carries the full image plus at most a handful of preview or mask pages.
    // The bound also stops a directory chain that loops back on itself.
    std::uint64_t max_directories{16ULL};
    std::uint64_t max_segments{1'048'576ULL};
    std::uint64_t max_single_tag_bytes{64ULL * 1024ULL * 1024ULL};
    std::uint64_t max_icc_profile_bytes{16ULL * 1024ULL * 1024ULL};
    std::uint64_t max_lzw_compressed_bytes{512ULL * 1024ULL * 1024ULL};
    std::uint64_t max_deflate_compressed_bytes{512ULL * 1024ULL * 1024ULL};
    std::uint64_t max_working_rgba32f_bytes{32ULL * 1024ULL * 1024ULL * 1024ULL};
};

struct TiffProbeControl final {
    bool validate_lzw_code_streams{false};
    bool validate_deflate_streams{false};
    std::stop_token stop_token{};
};

struct TiffProbeInfo final {
    TiffVariant variant{TiffVariant::classic};
    TiffByteOrder byte_order{TiffByteOrder::little_endian};
    TiffOrganization organization{TiffOrganization::stripped};
    std::uint64_t file_bytes{0};
    std::uint64_t first_ifd_offset{0};
    // Photoshop and most scanner software write the full image first and append a
    // reduced-resolution preview page. Everything below the directory fields describes
    // the primary image only; the preview pages are located, classified and then left
    // alone. `primary_directory_index` is also the WIC frame index for that image.
    std::uint64_t directory_count{1};
    std::uint64_t primary_directory_index{0};
    std::uint64_t primary_ifd_offset{0};
    std::uint64_t ifd_entry_count{0};
    std::uint64_t width{0};
    std::uint64_t height{0};
    std::uint64_t segment_count{0};
    std::uint64_t compressed_segment_bytes{0};
    std::uint64_t compressed_bytes_validated{0};
    std::uint64_t lzw_code_count{0};
    std::uint64_t lzw_decoded_bytes_validated{0};
    std::uint64_t deflate_decoded_bytes_validated{0};
    std::uint64_t icc_profile_bytes{0};
    std::uint64_t packed_raster_bytes{0};
    std::uint64_t working_rgba32f_bytes{0};
    std::uint16_t samples_per_pixel{1};
    std::uint16_t compression{1};
    std::uint16_t photometric_interpretation{0};
    std::uint16_t planar_configuration{1};
    std::uint16_t orientation{1};
    std::array<std::uint16_t, 8> bits_per_sample{1, 0, 0, 0, 0, 0, 0, 0};
    std::array<std::uint16_t, 8> sample_format{1, 0, 0, 0, 0, 0, 0, 0};
    std::array<std::uint16_t, 8> extra_samples{0, 0, 0, 0, 0, 0, 0, 0};
    std::uint8_t bits_per_sample_count{1};
    std::uint8_t sample_format_count{1};
    std::uint8_t extra_samples_count{0};
    bool lzw_code_streams_validated{false};
    bool deflate_streams_validated{false};
};

struct TiffProbeResult final {
    TiffProbeStatus status{TiffProbeStatus::io_error};
    TiffProbeInfo info{};
};

class TiffRandomAccessReader {
public:
    TiffRandomAccessReader() noexcept = default;
    TiffRandomAccessReader(const TiffRandomAccessReader&) = delete;
    TiffRandomAccessReader& operator=(const TiffRandomAccessReader&) = delete;
    virtual ~TiffRandomAccessReader() = default;

    [[nodiscard]] virtual std::uint64_t size() const noexcept = 0;
    [[nodiscard]] virtual bool read(
        std::uint64_t offset,
        std::uint8_t* destination,
        std::size_t byte_count) const noexcept = 0;
};

[[nodiscard]] TiffProbeResult probe_tiff(
    const TiffRandomAccessReader& reader,
    const TiffProbeLimits& limits = {},
    const TiffProbeControl& control = {}) noexcept;

[[nodiscard]] TiffProbeResult probe_tiff_file(
    const std::filesystem::path& path,
    const TiffProbeLimits& limits = {},
    const TiffProbeControl& control = {}) noexcept;

[[nodiscard]] const char* tiff_probe_status_name(TiffProbeStatus status) noexcept;
[[nodiscard]] const char* tiff_variant_name(TiffVariant variant) noexcept;
[[nodiscard]] const char* tiff_byte_order_name(TiffByteOrder byte_order) noexcept;
[[nodiscard]] const char* tiff_organization_name(TiffOrganization organization) noexcept;

}  // namespace negaflow::core
