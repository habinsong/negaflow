#pragma once

#include <cstdint>

namespace negaflow::core::tiff_probe_detail {

inline constexpr std::uint16_t tag_new_subfile_type = 254U;
inline constexpr std::uint16_t tag_image_width = 256U;
inline constexpr std::uint16_t tag_image_length = 257U;
inline constexpr std::uint16_t tag_bits_per_sample = 258U;
inline constexpr std::uint16_t tag_compression = 259U;
inline constexpr std::uint16_t tag_photometric = 262U;
inline constexpr std::uint16_t tag_strip_offsets = 273U;
inline constexpr std::uint16_t tag_orientation = 274U;
inline constexpr std::uint16_t tag_samples_per_pixel = 277U;
inline constexpr std::uint16_t tag_rows_per_strip = 278U;
inline constexpr std::uint16_t tag_strip_byte_counts = 279U;
inline constexpr std::uint16_t tag_planar_configuration = 284U;
inline constexpr std::uint16_t tag_tile_width = 322U;
inline constexpr std::uint16_t tag_tile_length = 323U;
inline constexpr std::uint16_t tag_tile_offsets = 324U;
inline constexpr std::uint16_t tag_tile_byte_counts = 325U;
inline constexpr std::uint16_t tag_extra_samples = 338U;
inline constexpr std::uint16_t tag_sample_format = 339U;
inline constexpr std::uint16_t tag_icc_profile = 34675U;

inline constexpr std::uint16_t type_byte = 1U;
inline constexpr std::uint16_t type_short = 3U;
inline constexpr std::uint16_t type_long = 4U;
inline constexpr std::uint16_t type_undefined = 7U;
inline constexpr std::uint16_t type_long8 = 16U;

}  // namespace negaflow::core::tiff_probe_detail
