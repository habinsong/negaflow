#include "negaflow/core/tiff_probe.h"

#include "tiff_deflate_validator.h"
#include "tiff_lzw_validator.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace negaflow::core {
namespace {

constexpr std::uint16_t tag_new_subfile_type = 254U;
constexpr std::uint16_t tag_image_width = 256U;
constexpr std::uint16_t tag_image_length = 257U;
constexpr std::uint16_t tag_bits_per_sample = 258U;
constexpr std::uint16_t tag_compression = 259U;
constexpr std::uint16_t tag_photometric = 262U;
constexpr std::uint16_t tag_strip_offsets = 273U;
constexpr std::uint16_t tag_orientation = 274U;
constexpr std::uint16_t tag_samples_per_pixel = 277U;
constexpr std::uint16_t tag_rows_per_strip = 278U;
constexpr std::uint16_t tag_strip_byte_counts = 279U;
constexpr std::uint16_t tag_planar_configuration = 284U;
constexpr std::uint16_t tag_tile_width = 322U;
constexpr std::uint16_t tag_tile_length = 323U;
constexpr std::uint16_t tag_tile_offsets = 324U;
constexpr std::uint16_t tag_tile_byte_counts = 325U;
constexpr std::uint16_t tag_extra_samples = 338U;
constexpr std::uint16_t tag_sample_format = 339U;
constexpr std::uint16_t tag_icc_profile = 34675U;

constexpr std::uint16_t type_byte = 1U;
constexpr std::uint16_t type_short = 3U;
constexpr std::uint16_t type_long = 4U;
constexpr std::uint16_t type_undefined = 7U;
constexpr std::uint16_t type_long8 = 16U;

[[nodiscard]] bool checked_add(
    const std::uint64_t left,
    const std::uint64_t right,
    std::uint64_t& result) noexcept {
    if (right > std::numeric_limits<std::uint64_t>::max() - left) {
        return false;
    }
    result = left + right;
    return true;
}

[[nodiscard]] bool checked_multiply(
    const std::uint64_t left,
    const std::uint64_t right,
    std::uint64_t& result) noexcept {
    if (left != 0U && right > std::numeric_limits<std::uint64_t>::max() / left) {
        return false;
    }
    result = left * right;
    return true;
}

class ReadOnlyFile final : public TiffRandomAccessReader {
public:
    ReadOnlyFile() noexcept = default;
    ReadOnlyFile(const ReadOnlyFile&) = delete;
    ReadOnlyFile& operator=(const ReadOnlyFile&) = delete;

    ~ReadOnlyFile() noexcept {
        if (handle_ != INVALID_HANDLE_VALUE) {
            CloseHandle(handle_);
        }
    }

    [[nodiscard]] bool open(const std::filesystem::path& path) noexcept {
        handle_ = CreateFileW(
            path.c_str(),
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_DELETE,
            nullptr,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_RANDOM_ACCESS,
            nullptr);
        if (handle_ == INVALID_HANDLE_VALUE) {
            return false;
        }

        LARGE_INTEGER size{};
        if (GetFileSizeEx(handle_, &size) == 0 || size.QuadPart < 0) {
            return false;
        }
        size_ = static_cast<std::uint64_t>(size.QuadPart);
        return true;
    }

    [[nodiscard]] std::uint64_t size() const noexcept override {
        return size_;
    }

    [[nodiscard]] bool read(
        const std::uint64_t offset,
        std::uint8_t* const destination,
        const std::size_t byte_count) const noexcept override {
        std::uint64_t end = 0;
        if (destination == nullptr ||
            byte_count > static_cast<std::size_t>(std::numeric_limits<DWORD>::max()) ||
            !checked_add(offset, static_cast<std::uint64_t>(byte_count), end) ||
            end > size_ || offset > static_cast<std::uint64_t>(std::numeric_limits<LONGLONG>::max())) {
            return false;
        }

        LARGE_INTEGER position{};
        position.QuadPart = static_cast<LONGLONG>(offset);
        if (SetFilePointerEx(handle_, position, nullptr, FILE_BEGIN) == 0) {
            return false;
        }

        DWORD bytes_read = 0;
        const DWORD requested = static_cast<DWORD>(byte_count);
        return ReadFile(handle_, destination, requested, &bytes_read, nullptr) != 0 &&
               bytes_read == requested;
    }

private:
    HANDLE handle_{INVALID_HANDLE_VALUE};
    std::uint64_t size_{0};
};

[[nodiscard]] std::uint16_t read_u16(
    const std::uint8_t* const bytes,
    const TiffByteOrder byte_order) noexcept {
    if (byte_order == TiffByteOrder::little_endian) {
        return static_cast<std::uint16_t>(
            static_cast<std::uint16_t>(bytes[0]) |
            static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[1]) << 8U));
    }
    return static_cast<std::uint16_t>(
        static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[0]) << 8U) |
        static_cast<std::uint16_t>(bytes[1]));
}

[[nodiscard]] std::uint32_t read_u32(
    const std::uint8_t* const bytes,
    const TiffByteOrder byte_order) noexcept {
    std::uint32_t value = 0U;
    if (byte_order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            value |= static_cast<std::uint32_t>(bytes[index]) << (index * 8U);
        }
    } else {
        for (std::uint32_t index = 0U; index < 4U; ++index) {
            value = static_cast<std::uint32_t>((value << 8U) | bytes[index]);
        }
    }
    return value;
}

[[nodiscard]] std::uint64_t read_u64(
    const std::uint8_t* const bytes,
    const TiffByteOrder byte_order) noexcept {
    std::uint64_t value = 0U;
    if (byte_order == TiffByteOrder::little_endian) {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            value |= static_cast<std::uint64_t>(bytes[index]) << (index * 8U);
        }
    } else {
        for (std::uint32_t index = 0U; index < 8U; ++index) {
            value = (value << 8U) | bytes[index];
        }
    }
    return value;
}

[[nodiscard]] std::uint8_t type_width(const std::uint16_t type) noexcept {
    switch (type) {
        case 1U:
        case 2U:
        case 6U:
        case 7U:
            return 1U;
        case 3U:
        case 8U:
            return 2U;
        case 4U:
        case 9U:
        case 11U:
        case 13U:
            return 4U;
        case 5U:
        case 10U:
        case 12U:
        case 16U:
        case 17U:
        case 18U:
            return 8U;
        default:
            return 0U;
    }
}

[[nodiscard]] bool is_unsigned_integer_type(const std::uint16_t type) noexcept {
    return type == type_byte || type == type_short || type == type_long || type == type_long8;
}

[[nodiscard]] bool is_offset_or_size_type(const std::uint16_t type) noexcept {
    return type == type_short || type == type_long || type == type_long8;
}

struct DirectoryEntry final {
    std::uint16_t tag{0};
    std::uint16_t type{0};
    std::uint64_t count{0};
    std::uint64_t total_bytes{0};
    std::uint64_t value_offset{0};
    std::uint8_t inline_capacity{0};
    std::array<std::uint8_t, 8> inline_bytes{};
};

[[nodiscard]] bool is_segment_array_tag(const std::uint16_t tag) noexcept {
    return tag == tag_strip_offsets || tag == tag_strip_byte_counts ||
           tag == tag_tile_offsets || tag == tag_tile_byte_counts;
}

[[nodiscard]] TiffProbeStatus parse_entry(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffVariant variant,
    const std::uint64_t entry_offset,
    const std::uint64_t header_bytes,
    const TiffProbeLimits& limits,
    DirectoryEntry& entry) noexcept {
    std::array<std::uint8_t, 20> bytes{};
    const std::size_t entry_bytes = variant == TiffVariant::classic ? 12U : 20U;
    if (!file.read(entry_offset, bytes.data(), entry_bytes)) {
        return TiffProbeStatus::truncated_ifd;
    }

    entry.tag = read_u16(bytes.data(), byte_order);
    entry.type = read_u16(bytes.data() + 2U, byte_order);
    if (variant == TiffVariant::classic && entry.type >= type_long8) {
        return TiffProbeStatus::invalid_tag;
    }
    const std::uint8_t width = type_width(entry.type);
    if (width == 0U) {
        return TiffProbeStatus::invalid_tag;
    }

    const std::size_t value_position = variant == TiffVariant::classic ? 8U : 12U;
    entry.inline_capacity = variant == TiffVariant::classic ? 4U : 8U;
    entry.count = variant == TiffVariant::classic
                      ? static_cast<std::uint64_t>(read_u32(bytes.data() + 4U, byte_order))
                      : read_u64(bytes.data() + 4U, byte_order);
    if (entry.count == 0U ||
        !checked_multiply(entry.count, static_cast<std::uint64_t>(width), entry.total_bytes)) {
        return TiffProbeStatus::invalid_tag;
    }

    std::copy_n(
        bytes.data() + value_position,
        static_cast<std::size_t>(entry.inline_capacity),
        entry.inline_bytes.data());
    entry.value_offset = variant == TiffVariant::classic
                             ? static_cast<std::uint64_t>(
                                   read_u32(entry.inline_bytes.data(), byte_order))
                             : read_u64(entry.inline_bytes.data(), byte_order);

    if (entry.tag == tag_icc_profile && entry.total_bytes > limits.max_icc_profile_bytes) {
        return TiffProbeStatus::tag_limit_exceeded;
    }
    if (!is_segment_array_tag(entry.tag) &&
        entry.total_bytes > limits.max_single_tag_bytes) {
        return TiffProbeStatus::tag_limit_exceeded;
    }

    if (entry.total_bytes > entry.inline_capacity) {
        std::uint64_t value_end = 0;
        if (entry.value_offset < header_bytes || (entry.value_offset & 1U) != 0U ||
            !checked_add(entry.value_offset, entry.total_bytes, value_end) ||
            value_end > file.size()) {
            return TiffProbeStatus::tag_data_out_of_bounds;
        }
    }
    return TiffProbeStatus::ok;
}

[[nodiscard]] TiffProbeStatus read_unsigned_element(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    const std::uint64_t index,
    std::uint64_t& value) noexcept {
    if (!is_unsigned_integer_type(entry.type) || index >= entry.count) {
        return TiffProbeStatus::invalid_tag;
    }

    const std::uint8_t width = type_width(entry.type);
    std::uint64_t element_byte_offset = 0;
    if (!checked_multiply(index, static_cast<std::uint64_t>(width), element_byte_offset)) {
        return TiffProbeStatus::invalid_tag;
    }

    std::array<std::uint8_t, 8> bytes{};
    const std::uint8_t* source = nullptr;
    if (entry.total_bytes <= entry.inline_capacity) {
        source = entry.inline_bytes.data() + static_cast<std::size_t>(element_byte_offset);
    } else {
        std::uint64_t file_offset = 0;
        if (!checked_add(entry.value_offset, element_byte_offset, file_offset) ||
            !file.read(file_offset, bytes.data(), width)) {
            return TiffProbeStatus::tag_data_out_of_bounds;
        }
        source = bytes.data();
    }

    switch (width) {
        case 1U:
            value = source[0];
            return TiffProbeStatus::ok;
        case 2U:
            value = read_u16(source, byte_order);
            return TiffProbeStatus::ok;
        case 4U:
            value = read_u32(source, byte_order);
            return TiffProbeStatus::ok;
        case 8U:
            value = read_u64(source, byte_order);
            return TiffProbeStatus::ok;
        default:
            return TiffProbeStatus::invalid_tag;
    }
}

[[nodiscard]] TiffProbeStatus read_scalar(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint64_t& value) noexcept {
    if (entry.count != 1U) {
        return TiffProbeStatus::invalid_tag;
    }
    return read_unsigned_element(file, byte_order, entry, 0U, value);
}

[[nodiscard]] bool mark_once(bool& seen) noexcept {
    if (seen) {
        return false;
    }
    seen = true;
    return true;
}

struct CapturedEntries final {
    DirectoryEntry bits_per_sample{};
    DirectoryEntry sample_format{};
    DirectoryEntry extra_samples{};
    DirectoryEntry strip_offsets{};
    DirectoryEntry strip_byte_counts{};
    DirectoryEntry tile_offsets{};
    DirectoryEntry tile_byte_counts{};
    bool has_bits_per_sample{false};
    bool has_sample_format{false};
    bool has_extra_samples{false};
    bool has_strip_offsets{false};
    bool has_strip_byte_counts{false};
    bool has_tile_offsets{false};
    bool has_tile_byte_counts{false};
    bool has_width{false};
    bool has_height{false};
    bool has_compression{false};
    bool has_photometric{false};
    bool has_orientation{false};
    bool has_samples_per_pixel{false};
    bool has_rows_per_strip{false};
    bool has_planar_configuration{false};
    bool has_tile_width{false};
    bool has_tile_length{false};
    bool has_icc_profile{false};
    std::uint64_t rows_per_strip{0};
    std::uint64_t tile_width{0};
    std::uint64_t tile_length{0};
};

[[nodiscard]] TiffProbeStatus assign_u16(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    std::uint16_t& target) noexcept {
    std::uint64_t value = 0;
    const TiffProbeStatus status = read_scalar(file, byte_order, entry, value);
    if (status != TiffProbeStatus::ok || value > std::numeric_limits<std::uint16_t>::max()) {
        return TiffProbeStatus::invalid_tag;
    }
    target = static_cast<std::uint16_t>(value);
    return TiffProbeStatus::ok;
}

[[nodiscard]] TiffProbeStatus capture_entry(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    CapturedEntries& captured,
    TiffProbeInfo& info) noexcept {
    switch (entry.tag) {
        case tag_image_width:
            if (!mark_once(captured.has_width)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, info.width);
        case tag_image_length:
            if (!mark_once(captured.has_height)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, info.height);
        case tag_bits_per_sample:
            if (!mark_once(captured.has_bits_per_sample)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.bits_per_sample = entry;
            return TiffProbeStatus::ok;
        case tag_compression:
            if (!mark_once(captured.has_compression)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.compression);
        case tag_photometric:
            if (!mark_once(captured.has_photometric)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.photometric_interpretation);
        case tag_strip_offsets:
            if (!mark_once(captured.has_strip_offsets)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.strip_offsets = entry;
            return TiffProbeStatus::ok;
        case tag_orientation:
            if (!mark_once(captured.has_orientation)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.orientation);
        case tag_samples_per_pixel:
            if (!mark_once(captured.has_samples_per_pixel)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.samples_per_pixel);
        case tag_rows_per_strip:
            if (!mark_once(captured.has_rows_per_strip)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, captured.rows_per_strip);
        case tag_strip_byte_counts:
            if (!mark_once(captured.has_strip_byte_counts)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.strip_byte_counts = entry;
            return TiffProbeStatus::ok;
        case tag_planar_configuration:
            if (!mark_once(captured.has_planar_configuration)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            return assign_u16(file, byte_order, entry, info.planar_configuration);
        case tag_tile_width:
            if (!mark_once(captured.has_tile_width)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, captured.tile_width);
        case tag_tile_length:
            if (!mark_once(captured.has_tile_length)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            return read_scalar(file, byte_order, entry, captured.tile_length);
        case tag_tile_offsets:
            if (!mark_once(captured.has_tile_offsets)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.tile_offsets = entry;
            return TiffProbeStatus::ok;
        case tag_tile_byte_counts:
            if (!mark_once(captured.has_tile_byte_counts)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (!is_offset_or_size_type(entry.type)) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.tile_byte_counts = entry;
            return TiffProbeStatus::ok;
        case tag_sample_format:
            if (!mark_once(captured.has_sample_format)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.sample_format = entry;
            return TiffProbeStatus::ok;
        case tag_extra_samples:
            if (!mark_once(captured.has_extra_samples)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_short) {
                return TiffProbeStatus::invalid_tag;
            }
            captured.extra_samples = entry;
            return TiffProbeStatus::ok;
        case tag_icc_profile:
            if (!mark_once(captured.has_icc_profile)) {
                return TiffProbeStatus::duplicate_tag;
            }
            if (entry.type != type_byte && entry.type != type_undefined) {
                return TiffProbeStatus::invalid_tag;
            }
            info.icc_profile_bytes = entry.total_bytes;
            return TiffProbeStatus::ok;
        default:
            return TiffProbeStatus::ok;
    }
}

[[nodiscard]] TiffProbeStatus read_extra_sample_values(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    const std::uint16_t samples_per_pixel,
    std::array<std::uint16_t, 8>& values,
    std::uint8_t& value_count) noexcept {
    if (entry.type != type_short || entry.count == 0U ||
        entry.count > samples_per_pixel || entry.count > values.size()) {
        return TiffProbeStatus::invalid_layout;
    }

    for (std::uint64_t index = 0; index < entry.count; ++index) {
        std::uint64_t value = 0;
        const TiffProbeStatus status =
            read_unsigned_element(file, byte_order, entry, index, value);
        if (status != TiffProbeStatus::ok || value > 2U) {
            return TiffProbeStatus::invalid_layout;
        }
        values[static_cast<std::size_t>(index)] = static_cast<std::uint16_t>(value);
    }
    value_count = static_cast<std::uint8_t>(entry.count);
    return TiffProbeStatus::ok;
}

[[nodiscard]] TiffProbeStatus read_short_values(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& entry,
    const std::uint16_t samples_per_pixel,
    std::array<std::uint16_t, 8>& values,
    std::uint8_t& value_count) noexcept {
    if (entry.type != type_short ||
        (entry.count != 1U && entry.count != samples_per_pixel) ||
        entry.count > values.size()) {
        return TiffProbeStatus::invalid_layout;
    }

    for (std::uint64_t index = 0; index < entry.count; ++index) {
        std::uint64_t value = 0;
        const TiffProbeStatus status =
            read_unsigned_element(file, byte_order, entry, index, value);
        if (status != TiffProbeStatus::ok || value == 0U || value > 64U) {
            return TiffProbeStatus::invalid_layout;
        }
        values[static_cast<std::size_t>(index)] = static_cast<std::uint16_t>(value);
    }
    value_count = static_cast<std::uint8_t>(entry.count);
    return TiffProbeStatus::ok;
}

[[nodiscard]] TiffProbeStatus validate_segments(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const DirectoryEntry& offsets,
    const DirectoryEntry& byte_counts,
    const TiffProbeLimits& limits,
    const std::uint64_t minimum_data_offset,
    const std::uint64_t expected_segment_count,
    TiffProbeInfo& info) noexcept {
    if (!is_offset_or_size_type(offsets.type) ||
        !is_offset_or_size_type(byte_counts.type) || offsets.count == 0U ||
        offsets.count != byte_counts.count || offsets.count != expected_segment_count) {
        return TiffProbeStatus::invalid_layout;
    }
    if (offsets.count > limits.max_segments) {
        return TiffProbeStatus::segment_limit_exceeded;
    }

    for (std::uint64_t index = 0; index < offsets.count; ++index) {
        std::uint64_t offset = 0;
        std::uint64_t byte_count = 0;
        TiffProbeStatus status = read_unsigned_element(file, byte_order, offsets, index, offset);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        status = read_unsigned_element(file, byte_order, byte_counts, index, byte_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        std::uint64_t segment_end = 0;
        if (offset < minimum_data_offset || byte_count == 0U ||
            !checked_add(offset, byte_count, segment_end) ||
            segment_end > file.size()) {
            return TiffProbeStatus::tag_data_out_of_bounds;
        }
        if (!checked_add(
                info.compressed_segment_bytes,
                byte_count,
                info.compressed_segment_bytes)) {
            return TiffProbeStatus::invalid_layout;
        }
    }
    info.segment_count = offsets.count;
    return TiffProbeStatus::ok;
}

[[nodiscard]] bool compute_segment_row_bytes(
    const TiffProbeInfo& info,
    const std::uint64_t width,
    const std::uint16_t plane,
    std::uint64_t& row_bytes) noexcept {
    std::uint64_t bits_per_pixel = 0U;
    if (info.planar_configuration == 1U) {
        if (info.bits_per_sample_count == 1U) {
            if (!checked_multiply(
                    info.bits_per_sample[0],
                    info.samples_per_pixel,
                    bits_per_pixel)) {
                return false;
            }
        } else {
            for (std::uint8_t index = 0U; index < info.bits_per_sample_count; ++index) {
                if (!checked_add(
                        bits_per_pixel,
                        info.bits_per_sample[index],
                        bits_per_pixel)) {
                    return false;
                }
            }
        }
    } else {
        if (plane >= info.samples_per_pixel) {
            return false;
        }
        bits_per_pixel = info.bits_per_sample_count == 1U
                             ? info.bits_per_sample[0]
                             : info.bits_per_sample[plane];
    }

    std::uint64_t row_bits = 0U;
    std::uint64_t rounded_row_bits = 0U;
    if (!checked_multiply(width, bits_per_pixel, row_bits) ||
        !checked_add(row_bits, 7U, rounded_row_bits)) {
        return false;
    }
    row_bytes = rounded_row_bits / 8U;
    return true;
}

[[nodiscard]] TiffProbeStatus validate_compressed_segments(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control,
    const CapturedEntries& captured,
    TiffProbeInfo& info) noexcept {
    const bool validate_lzw =
        info.compression == 5U && control.validate_lzw_code_streams;
    const bool validate_deflate =
        info.compression == 8U && control.validate_deflate_streams;
    if (!validate_lzw && !validate_deflate) {
        return TiffProbeStatus::ok;
    }
    if (control.stop_token.stop_requested()) {
        return TiffProbeStatus::cancelled;
    }
    const std::uint64_t compressed_limit = validate_lzw
                                               ? limits.max_lzw_compressed_bytes
                                               : limits.max_deflate_compressed_bytes;
    if (info.compressed_segment_bytes > compressed_limit) {
        return TiffProbeStatus::compressed_data_limit_exceeded;
    }

    const DirectoryEntry& offsets = info.organization == TiffOrganization::stripped
                                        ? captured.strip_offsets
                                        : captured.tile_offsets;
    const DirectoryEntry& byte_counts = info.organization == TiffOrganization::stripped
                                            ? captured.strip_byte_counts
                                            : captured.tile_byte_counts;
    const std::uint64_t plane_count =
        info.planar_configuration == 2U ? info.samples_per_pixel : 1U;
    if (plane_count == 0U || offsets.count % plane_count != 0U) {
        return TiffProbeStatus::invalid_layout;
    }
    const std::uint64_t segments_per_plane = offsets.count / plane_count;

    for (std::uint64_t index = 0U; index < offsets.count; ++index) {
        if (control.stop_token.stop_requested()) {
            return TiffProbeStatus::cancelled;
        }

        std::uint64_t offset = 0U;
        std::uint64_t compressed_bytes = 0U;
        TiffProbeStatus status =
            read_unsigned_element(file, byte_order, offsets, index, offset);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        status = read_unsigned_element(
            file,
            byte_order,
            byte_counts,
            index,
            compressed_bytes);
        if (status != TiffProbeStatus::ok) {
            return status;
        }

        const std::uint16_t plane = info.planar_configuration == 2U
                                        ? static_cast<std::uint16_t>(
                                              index / segments_per_plane)
                                        : 0U;
        std::uint64_t segment_width = info.width;
        std::uint64_t segment_rows = 0U;
        if (info.organization == TiffOrganization::stripped) {
            const std::uint64_t rows_per_strip = captured.has_rows_per_strip
                                                     ? captured.rows_per_strip
                                                     : info.height;
            const std::uint64_t strip_index = index % segments_per_plane;
            std::uint64_t first_row = 0U;
            if (!checked_multiply(strip_index, rows_per_strip, first_row) ||
                first_row >= info.height) {
                return TiffProbeStatus::invalid_layout;
            }
            segment_rows = std::min(rows_per_strip, info.height - first_row);
        } else {
            segment_width = captured.tile_width;
            segment_rows = captured.tile_length;
        }

        std::uint64_t row_bytes = 0U;
        std::uint64_t expected_decoded_bytes = 0U;
        if (!compute_segment_row_bytes(info, segment_width, plane, row_bytes) ||
            !checked_multiply(row_bytes, segment_rows, expected_decoded_bytes)) {
            return TiffProbeStatus::invalid_dimensions;
        }

        if (validate_lzw) {
            const detail::TiffLzwValidationResult validation =
                detail::validate_tiff_lzw_segment(
                    file,
                    offset,
                    compressed_bytes,
                    expected_decoded_bytes,
                    control.stop_token);
            if (validation.status == detail::TiffLzwValidationStatus::cancelled) {
                return TiffProbeStatus::cancelled;
            }
            if (validation.status == detail::TiffLzwValidationStatus::io_error) {
                return TiffProbeStatus::io_error;
            }
            if (validation.status != detail::TiffLzwValidationStatus::ok) {
                return TiffProbeStatus::invalid_compressed_data;
            }
            if (!checked_add(
                    info.compressed_bytes_validated,
                    validation.compressed_bytes_read,
                    info.compressed_bytes_validated) ||
                !checked_add(
                    info.lzw_code_count,
                    validation.code_count,
                    info.lzw_code_count) ||
                !checked_add(
                    info.lzw_decoded_bytes_validated,
                    validation.decoded_bytes,
                    info.lzw_decoded_bytes_validated)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        } else {
            const detail::TiffDeflateValidationResult validation =
                detail::validate_tiff_deflate_segment(
                    file,
                    offset,
                    compressed_bytes,
                    expected_decoded_bytes,
                    control.stop_token);
            if (validation.status == detail::TiffDeflateValidationStatus::cancelled) {
                return TiffProbeStatus::cancelled;
            }
            if (validation.status == detail::TiffDeflateValidationStatus::io_error) {
                return TiffProbeStatus::io_error;
            }
            if (validation.status != detail::TiffDeflateValidationStatus::ok) {
                return TiffProbeStatus::invalid_compressed_data;
            }
            if (!checked_add(
                    info.compressed_bytes_validated,
                    validation.compressed_bytes_read,
                    info.compressed_bytes_validated) ||
                !checked_add(
                    info.deflate_decoded_bytes_validated,
                    validation.decoded_bytes,
                    info.deflate_decoded_bytes_validated)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        }
    }
    info.lzw_code_streams_validated = validate_lzw;
    info.deflate_streams_validated = validate_deflate;
    return TiffProbeStatus::ok;
}

// Bit 0 of NewSubfileType marks a reduced-resolution page and bit 2 a transparency
// mask. Both are companions to some other image, never the image itself. A directory
// without the tag is a full image, which is what a plain single-page scan looks like.
constexpr std::uint64_t subfile_reduced_resolution = 0x1ULL;
constexpr std::uint64_t subfile_transparency_mask = 0x4ULL;

[[nodiscard]] bool is_auxiliary_subfile(const std::uint64_t new_subfile_type) noexcept {
    return (new_subfile_type &
            (subfile_reduced_resolution | subfile_transparency_mask)) != 0U;
}

// Reads one directory's entry count and its NewSubfileType, and follows the chain.
// Deliberately parses nothing else: the point is to decide which directory is worth
// parsing before spending any validation on it.
[[nodiscard]] TiffProbeStatus classify_directory(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffVariant variant,
    const std::uint64_t directory_offset,
    const std::uint64_t header_bytes,
    const std::uint64_t directory_count_bytes,
    const std::uint64_t directory_entry_bytes,
    const std::uint64_t next_directory_bytes,
    const TiffProbeLimits& limits,
    bool& auxiliary,
    std::uint64_t& next_directory_offset) noexcept {
    if (directory_offset < header_bytes || (directory_offset & 1U) != 0U) {
        return TiffProbeStatus::invalid_ifd_offset;
    }

    std::array<std::uint8_t, 8> count_bytes{};
    if (!file.read(
            directory_offset,
            count_bytes.data(),
            static_cast<std::size_t>(directory_count_bytes))) {
        return TiffProbeStatus::truncated_ifd;
    }
    const std::uint64_t entry_count = variant == TiffVariant::classic
                                          ? read_u16(count_bytes.data(), byte_order)
                                          : read_u64(count_bytes.data(), byte_order);
    if (entry_count == 0U) {
        return TiffProbeStatus::invalid_header;
    }
    if (entry_count > limits.max_ifd_entries) {
        return TiffProbeStatus::ifd_entry_limit_exceeded;
    }

    std::uint64_t entries_bytes = 0;
    std::uint64_t entries_offset = 0;
    std::uint64_t next_offset_position = 0;
    std::uint64_t directory_end = 0;
    if (!checked_multiply(entry_count, directory_entry_bytes, entries_bytes) ||
        !checked_add(directory_offset, directory_count_bytes, entries_offset) ||
        !checked_add(entries_offset, entries_bytes, next_offset_position) ||
        !checked_add(next_offset_position, next_directory_bytes, directory_end) ||
        directory_end > file.size()) {
        return TiffProbeStatus::truncated_ifd;
    }

    auxiliary = false;
    for (std::uint64_t index = 0; index < entry_count; ++index) {
        std::uint64_t entry_delta = 0;
        std::uint64_t entry_offset = 0;
        if (!checked_multiply(index, directory_entry_bytes, entry_delta) ||
            !checked_add(entries_offset, entry_delta, entry_offset)) {
            return TiffProbeStatus::truncated_ifd;
        }
        DirectoryEntry entry{};
        const TiffProbeStatus status = parse_entry(
            file, byte_order, variant, entry_offset, header_bytes, limits, entry);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        if (entry.tag != tag_new_subfile_type) {
            continue;
        }
        std::uint64_t value = 0;
        const TiffProbeStatus value_status =
            read_unsigned_element(file, byte_order, entry, 0U, value);
        if (value_status != TiffProbeStatus::ok) {
            return value_status;
        }
        auxiliary = is_auxiliary_subfile(value);
        break;
    }

    std::array<std::uint8_t, 8> next_bytes{};
    if (!file.read(
            next_offset_position,
            next_bytes.data(),
            static_cast<std::size_t>(next_directory_bytes))) {
        return TiffProbeStatus::truncated_ifd;
    }
    next_directory_offset = variant == TiffVariant::classic
                                ? read_u32(next_bytes.data(), byte_order)
                                : read_u64(next_bytes.data(), byte_order);
    return TiffProbeStatus::ok;
}

// Chooses the single full-resolution image in the directory chain. Exactly one has to
// qualify: none means the file carries only companion pages, and several means the file
// is a multi-page document whose "the image" is not ours to guess. Both are refused.
[[nodiscard]] TiffProbeStatus select_primary_directory(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffVariant variant,
    const std::uint64_t first_ifd_offset,
    const std::uint64_t header_bytes,
    const std::uint64_t directory_count_bytes,
    const std::uint64_t directory_entry_bytes,
    const std::uint64_t next_directory_bytes,
    const TiffProbeLimits& limits,
    TiffProbeInfo& info) noexcept {
    std::uint64_t offset = first_ifd_offset;
    std::uint64_t index = 0;
    std::uint64_t primary_count = 0;

    while (offset != 0U) {
        if (index >= limits.max_directories) {
            return TiffProbeStatus::directory_limit_exceeded;
        }
        bool auxiliary = false;
        std::uint64_t next_offset = 0;
        const TiffProbeStatus status = classify_directory(
            file,
            byte_order,
            variant,
            offset,
            header_bytes,
            directory_count_bytes,
            directory_entry_bytes,
            next_directory_bytes,
            limits,
            auxiliary,
            next_offset);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        if (!auxiliary) {
            ++primary_count;
            if (primary_count > 1U) {
                return TiffProbeStatus::multiple_directories_unsupported;
            }
            info.primary_directory_index = index;
            info.primary_ifd_offset = offset;
        }
        offset = next_offset;
        ++index;
    }

    info.directory_count = index;
    if (primary_count != 1U) {
        return TiffProbeStatus::multiple_directories_unsupported;
    }
    return TiffProbeStatus::ok;
}

[[nodiscard]] TiffProbeStatus finalize_info(
    const TiffRandomAccessReader& file,
    const TiffByteOrder byte_order,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control,
    const CapturedEntries& captured,
    TiffProbeInfo& info) noexcept {
    if (!captured.has_width || !captured.has_height || info.width == 0U || info.height == 0U) {
        return TiffProbeStatus::invalid_dimensions;
    }
    if (info.samples_per_pixel == 0U || info.samples_per_pixel > info.bits_per_sample.size() ||
        info.orientation == 0U || info.orientation > 8U ||
        (info.planar_configuration != 1U && info.planar_configuration != 2U)) {
        return TiffProbeStatus::invalid_layout;
    }

    if (captured.has_bits_per_sample) {
        const TiffProbeStatus status = read_short_values(
            file,
            byte_order,
            captured.bits_per_sample,
            info.samples_per_pixel,
            info.bits_per_sample,
            info.bits_per_sample_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
    }
    if (captured.has_sample_format) {
        const TiffProbeStatus status = read_short_values(
            file,
            byte_order,
            captured.sample_format,
            info.samples_per_pixel,
            info.sample_format,
            info.sample_format_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
        for (std::uint8_t index = 0; index < info.sample_format_count; ++index) {
            if (info.sample_format[index] > 6U) {
                return TiffProbeStatus::invalid_layout;
            }
        }
    }
    if (captured.has_extra_samples) {
        const TiffProbeStatus status = read_extra_sample_values(
            file,
            byte_order,
            captured.extra_samples,
            info.samples_per_pixel,
            info.extra_samples,
            info.extra_samples_count);
        if (status != TiffProbeStatus::ok) {
            return status;
        }
    }

    const bool has_any_strip = captured.has_strip_offsets || captured.has_strip_byte_counts ||
                               captured.has_rows_per_strip;
    const bool has_any_tile = captured.has_tile_offsets || captured.has_tile_byte_counts ||
                              captured.has_tile_width || captured.has_tile_length;
    if (has_any_strip == has_any_tile) {
        return TiffProbeStatus::invalid_layout;
    }

    TiffProbeStatus segment_status = TiffProbeStatus::invalid_layout;
    const std::uint64_t plane_count =
        info.planar_configuration == 2U ? info.samples_per_pixel : 1U;
    std::uint64_t expected_segment_count = 0;
    const std::uint64_t minimum_data_offset =
        info.variant == TiffVariant::classic ? 8U : 16U;
    if (has_any_strip) {
        if (!captured.has_strip_offsets || !captured.has_strip_byte_counts ||
            (captured.has_rows_per_strip && captured.rows_per_strip == 0U)) {
            return TiffProbeStatus::invalid_layout;
        }
        const std::uint64_t rows_per_strip =
            captured.has_rows_per_strip ? captured.rows_per_strip : info.height;
        std::uint64_t rounded_height = 0;
        if (!checked_add(info.height, rows_per_strip - 1U, rounded_height) ||
            !checked_multiply(
                rounded_height / rows_per_strip,
                plane_count,
                expected_segment_count)) {
            return TiffProbeStatus::invalid_dimensions;
        }
        info.organization = TiffOrganization::stripped;
        segment_status = validate_segments(
            file,
            byte_order,
            captured.strip_offsets,
            captured.strip_byte_counts,
            limits,
            minimum_data_offset,
            expected_segment_count,
            info);
    } else {
        if (!captured.has_tile_offsets || !captured.has_tile_byte_counts ||
            !captured.has_tile_width || !captured.has_tile_length ||
            captured.tile_width == 0U || captured.tile_length == 0U) {
            return TiffProbeStatus::invalid_layout;
        }
        std::uint64_t rounded_width = 0;
        std::uint64_t rounded_height = 0;
        std::uint64_t tiles_across = 0;
        std::uint64_t tiles_down = 0;
        std::uint64_t tiles_per_plane = 0;
        if (!checked_add(info.width, captured.tile_width - 1U, rounded_width) ||
            !checked_add(info.height, captured.tile_length - 1U, rounded_height)) {
            return TiffProbeStatus::invalid_dimensions;
        }
        tiles_across = rounded_width / captured.tile_width;
        tiles_down = rounded_height / captured.tile_length;
        if (!checked_multiply(tiles_across, tiles_down, tiles_per_plane) ||
            !checked_multiply(tiles_per_plane, plane_count, expected_segment_count)) {
            return TiffProbeStatus::invalid_dimensions;
        }
        info.organization = TiffOrganization::tiled;
        segment_status = validate_segments(
            file,
            byte_order,
            captured.tile_offsets,
            captured.tile_byte_counts,
            limits,
            minimum_data_offset,
            expected_segment_count,
            info);
    }
    if (segment_status != TiffProbeStatus::ok) {
        return segment_status;
    }

    if (info.planar_configuration == 1U) {
        std::uint64_t row_bytes = 0U;
        if (!compute_segment_row_bytes(info, info.width, 0U, row_bytes) ||
            !checked_multiply(row_bytes, info.height, info.packed_raster_bytes)) {
            return TiffProbeStatus::invalid_dimensions;
        }
    } else {
        for (std::uint16_t channel = 0; channel < info.samples_per_pixel; ++channel) {
            std::uint64_t row_bytes = 0U;
            std::uint64_t plane_bytes = 0;
            if (!compute_segment_row_bytes(info, info.width, channel, row_bytes) ||
                !checked_multiply(row_bytes, info.height, plane_bytes) ||
                !checked_add(info.packed_raster_bytes, plane_bytes, info.packed_raster_bytes)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        }
    }

    std::uint64_t pixels = 0;
    if (!checked_multiply(info.width, info.height, pixels) ||
        !checked_multiply(pixels, 16U, info.working_rgba32f_bytes)) {
        return TiffProbeStatus::invalid_dimensions;
    }
    if (info.working_rgba32f_bytes > limits.max_working_rgba32f_bytes) {
        return TiffProbeStatus::working_memory_limit_exceeded;
    }
    return validate_compressed_segments(file, byte_order, limits, control, captured, info);
}

}  // namespace

TiffProbeResult probe_tiff(
    const TiffRandomAccessReader& file,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control) noexcept {
    TiffProbeResult result{};
    try {
        result.info.file_bytes = file.size();
        if (file.size() > limits.max_file_bytes) {
            result.status = TiffProbeStatus::file_limit_exceeded;
            return result;
        }
        if (file.size() < 8U) {
            result.status = TiffProbeStatus::truncated_header;
            return result;
        }

        std::array<std::uint8_t, 16> header{};
        if (!file.read(0U, header.data(), 8U)) {
            result.status = TiffProbeStatus::truncated_header;
            return result;
        }
        if (header[0] == 'I' && header[1] == 'I') {
            result.info.byte_order = TiffByteOrder::little_endian;
        } else if (header[0] == 'M' && header[1] == 'M') {
            result.info.byte_order = TiffByteOrder::big_endian;
        } else {
            result.status = TiffProbeStatus::invalid_header;
            return result;
        }

        const std::uint16_t version = read_u16(header.data() + 2U, result.info.byte_order);
        std::uint64_t header_bytes = 0;
        std::uint64_t directory_count_bytes = 0;
        std::uint64_t directory_entry_bytes = 0;
        std::uint64_t next_directory_bytes = 0;
        if (version == 42U) {
            result.info.variant = TiffVariant::classic;
            header_bytes = 8U;
            directory_count_bytes = 2U;
            directory_entry_bytes = 12U;
            next_directory_bytes = 4U;
            result.info.first_ifd_offset = read_u32(header.data() + 4U, result.info.byte_order);
        } else if (version == 43U) {
            if (file.size() < 16U || !file.read(0U, header.data(), header.size())) {
                result.status = TiffProbeStatus::truncated_header;
                return result;
            }
            if (read_u16(header.data() + 4U, result.info.byte_order) != 8U ||
                read_u16(header.data() + 6U, result.info.byte_order) != 0U) {
                result.status = TiffProbeStatus::invalid_bigtiff_header;
                return result;
            }
            result.info.variant = TiffVariant::big;
            header_bytes = 16U;
            directory_count_bytes = 8U;
            directory_entry_bytes = 20U;
            next_directory_bytes = 8U;
            result.info.first_ifd_offset = read_u64(header.data() + 8U, result.info.byte_order);
        } else {
            result.status = TiffProbeStatus::invalid_header;
            return result;
        }

        if (result.info.first_ifd_offset < header_bytes ||
            (result.info.first_ifd_offset & 1U) != 0U) {
            result.status = TiffProbeStatus::invalid_ifd_offset;
            return result;
        }

        // Walk the directory chain and pick the one full-resolution image before parsing
        // anything. A reduced-resolution preview page has the same tags as the real
        // image, so classifying first is what keeps the probe from validating a 1500px
        // thumbnail and reporting it as the scan.
        const TiffProbeStatus selection_status = select_primary_directory(
            file,
            result.info.byte_order,
            result.info.variant,
            result.info.first_ifd_offset,
            header_bytes,
            directory_count_bytes,
            directory_entry_bytes,
            next_directory_bytes,
            limits,
            result.info);
        if (selection_status != TiffProbeStatus::ok) {
            result.status = selection_status;
            return result;
        }

        std::array<std::uint8_t, 8> count_bytes{};
        if (!file.read(
                result.info.primary_ifd_offset,
                count_bytes.data(),
                static_cast<std::size_t>(directory_count_bytes))) {
            result.status = TiffProbeStatus::truncated_ifd;
            return result;
        }
        result.info.ifd_entry_count = result.info.variant == TiffVariant::classic
                                          ? read_u16(count_bytes.data(), result.info.byte_order)
                                          : read_u64(count_bytes.data(), result.info.byte_order);
        if (result.info.ifd_entry_count == 0U) {
            result.status = TiffProbeStatus::invalid_header;
            return result;
        }
        if (result.info.ifd_entry_count > limits.max_ifd_entries) {
            result.status = TiffProbeStatus::ifd_entry_limit_exceeded;
            return result;
        }

        std::uint64_t entries_bytes = 0;
        std::uint64_t entries_offset = 0;
        std::uint64_t next_ifd_offset_position = 0;
        std::uint64_t directory_end = 0;
        if (!checked_multiply(
                result.info.ifd_entry_count, directory_entry_bytes, entries_bytes) ||
            !checked_add(
                result.info.primary_ifd_offset, directory_count_bytes, entries_offset) ||
            !checked_add(entries_offset, entries_bytes, next_ifd_offset_position) ||
            !checked_add(next_ifd_offset_position, next_directory_bytes, directory_end) ||
            directory_end > file.size()) {
            result.status = TiffProbeStatus::truncated_ifd;
            return result;
        }

        CapturedEntries captured{};
        for (std::uint64_t index = 0; index < result.info.ifd_entry_count; ++index) {
            std::uint64_t entry_delta = 0;
            std::uint64_t entry_offset = 0;
            if (!checked_multiply(index, directory_entry_bytes, entry_delta) ||
                !checked_add(entries_offset, entry_delta, entry_offset)) {
                result.status = TiffProbeStatus::truncated_ifd;
                return result;
            }

            DirectoryEntry entry{};
            TiffProbeStatus status = parse_entry(
                file,
                result.info.byte_order,
                result.info.variant,
                entry_offset,
                header_bytes,
                limits,
                entry);
            if (status != TiffProbeStatus::ok) {
                result.status = status;
                return result;
            }
            status = capture_entry(file, result.info.byte_order, entry, captured, result.info);
            if (status != TiffProbeStatus::ok) {
                result.status = status;
                return result;
            }
        }

        result.status = finalize_info(
            file,
            result.info.byte_order,
            limits,
            control,
            captured,
            result.info);
        return result;
    } catch (...) {
        result.status = TiffProbeStatus::io_error;
        return result;
    }
}

TiffProbeResult probe_tiff_file(
    const std::filesystem::path& path,
    const TiffProbeLimits& limits,
    const TiffProbeControl& control) noexcept {
    TiffProbeResult result{};
    try {
        ReadOnlyFile file{};
        if (!file.open(path)) {
            result.status = TiffProbeStatus::io_error;
            return result;
        }
        return probe_tiff(file, limits, control);
    } catch (...) {
        result.status = TiffProbeStatus::io_error;
        return result;
    }
}

const char* tiff_probe_status_name(const TiffProbeStatus status) noexcept {
    switch (status) {
        case TiffProbeStatus::ok:
            return "ok";
        case TiffProbeStatus::io_error:
            return "io_error";
        case TiffProbeStatus::file_limit_exceeded:
            return "file_limit_exceeded";
        case TiffProbeStatus::truncated_header:
            return "truncated_header";
        case TiffProbeStatus::invalid_header:
            return "invalid_tiff_header";
        case TiffProbeStatus::invalid_bigtiff_header:
            return "invalid_bigtiff_header";
        case TiffProbeStatus::invalid_ifd_offset:
            return "invalid_ifd_offset";
        case TiffProbeStatus::ifd_entry_limit_exceeded:
            return "ifd_entry_limit_exceeded";
        case TiffProbeStatus::truncated_ifd:
            return "truncated_ifd";
        case TiffProbeStatus::invalid_tag:
            return "invalid_tiff_tag";
        case TiffProbeStatus::duplicate_tag:
            return "duplicate_tiff_tag";
        case TiffProbeStatus::tag_data_out_of_bounds:
            return "tag_data_out_of_bounds";
        case TiffProbeStatus::tag_limit_exceeded:
            return "tag_limit_exceeded";
        case TiffProbeStatus::invalid_dimensions:
            return "invalid_tiff_dimensions";
        case TiffProbeStatus::invalid_layout:
            return "invalid_tiff_layout";
        case TiffProbeStatus::segment_limit_exceeded:
            return "segment_limit_exceeded";
        case TiffProbeStatus::compressed_data_limit_exceeded:
            return "compressed_data_limit_exceeded";
        case TiffProbeStatus::invalid_compressed_data:
            return "invalid_compressed_data";
        case TiffProbeStatus::working_memory_limit_exceeded:
            return "working_memory_limit_exceeded";
        case TiffProbeStatus::multiple_directories_unsupported:
            return "multiple_directories_unsupported";
        case TiffProbeStatus::directory_limit_exceeded:
            return "directory_limit_exceeded";
        case TiffProbeStatus::cancelled:
            return "cancelled";
    }
    return "unknown_tiff_probe_status";
}

const char* tiff_variant_name(const TiffVariant variant) noexcept {
    return variant == TiffVariant::classic ? "classic" : "big";
}

const char* tiff_byte_order_name(const TiffByteOrder byte_order) noexcept {
    return byte_order == TiffByteOrder::little_endian ? "little" : "big";
}

const char* tiff_organization_name(const TiffOrganization organization) noexcept {
    return organization == TiffOrganization::stripped ? "stripped" : "tiled";
}

}  // namespace negaflow::core
