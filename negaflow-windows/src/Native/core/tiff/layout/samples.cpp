#include "samples.h"

#include "tiff/parse/tags.h"

namespace negaflow::core::tiff_probe_detail {

TiffProbeStatus read_extra_sample_values(
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

TiffProbeStatus read_short_values(
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

}  // namespace negaflow::core::tiff_probe_detail
