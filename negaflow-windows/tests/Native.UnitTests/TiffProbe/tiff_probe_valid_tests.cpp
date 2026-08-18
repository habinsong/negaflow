#include "tiff_probe_test_support.h"

#include <fstream>
#include <iostream>

namespace tiff_probe_tests {

void test_random_access_reader_contract() {
    const auto bytes = make_classic_tiff(TiffByteOrder::little_endian);
    const MemoryTiffReader reader{bytes};
    const auto result = negaflow::core::probe_tiff(reader);

    expect(result.status == TiffProbeStatus::ok, "random-access reader probes");
    expect(result.info.file_bytes == bytes.size(), "reader size is preserved");
    expect(result.info.width == 2U && result.info.height == 1U, "reader dimensions match");
}

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

}  // namespace tiff_probe_tests
