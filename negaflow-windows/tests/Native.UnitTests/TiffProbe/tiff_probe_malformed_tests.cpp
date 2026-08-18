#include "tiff_probe_test_support.h"

#include <fstream>
#include <iostream>

namespace tiff_probe_tests {

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

void test_multi_directory_selection(const std::filesystem::path& root) {
    // The ordinary scanner file: full image first, reduced-resolution preview appended.
    const auto trailing_preview = make_classic_multi_directory_tiff(
        TiffByteOrder::little_endian,
        {{4U, 2U, 0U}, {2U, 1U, 1U}});
    const std::filesystem::path trailing_path = root / L"preview-after.tiff";
    write_fixture(trailing_path, trailing_preview);
    const auto trailing = negaflow::core::probe_tiff_file(trailing_path);
    expect(trailing.status == TiffProbeStatus::ok, "a trailing preview page is accepted");
    expect(
        trailing.info.width == 4U && trailing.info.height == 2U,
        "the full image, not the preview, is the one described");
    expect(trailing.info.directory_count == 2U, "both directories are counted");
    expect(
        trailing.info.primary_directory_index == 0U,
        "the leading full image is selected");

    // The case a frame-zero assumption gets wrong: preview first, full image second.
    const auto leading_preview = make_classic_multi_directory_tiff(
        TiffByteOrder::little_endian,
        {{2U, 1U, 1U}, {4U, 2U, 0U}});
    const std::filesystem::path leading_path = root / L"preview-before.tiff";
    write_fixture(leading_path, leading_preview);
    const auto leading = negaflow::core::probe_tiff_file(leading_path);
    expect(leading.status == TiffProbeStatus::ok, "a leading preview page is accepted");
    expect(
        leading.info.width == 4U && leading.info.height == 2U,
        "the full image is found behind a preview page");
    expect(
        leading.info.primary_directory_index == 1U,
        "selection follows the subfile type, not the directory order");

    // A transparency mask is a companion page too, and must not be mistaken for a
    // second image.
    const auto masked = make_classic_multi_directory_tiff(
        TiffByteOrder::little_endian,
        {{4U, 2U, 0U}, {4U, 2U, 4U}});
    const std::filesystem::path masked_path = root / L"with-mask.tiff";
    write_fixture(masked_path, masked);
    const auto mask_result = negaflow::core::probe_tiff_file(masked_path);
    expect(
        mask_result.status == TiffProbeStatus::ok &&
            mask_result.info.primary_directory_index == 0U,
        "a transparency mask page is not treated as a second image");

    // Two full images is a multi-page document. Which one is "the photograph" is not
    // ours to guess, so it stays refused.
    const auto two_primaries = make_classic_multi_directory_tiff(
        TiffByteOrder::little_endian,
        {{4U, 2U, 0U}, {4U, 2U, 0U}});
    const std::filesystem::path two_path = root / L"two-pages.tiff";
    write_fixture(two_path, two_primaries);
    expect(
        negaflow::core::probe_tiff_file(two_path).status ==
            TiffProbeStatus::multiple_directories_unsupported,
        "a genuine multi-page document is still refused");

    // Every page a companion means no image at all.
    const auto no_primary = make_classic_multi_directory_tiff(
        TiffByteOrder::little_endian,
        {{4U, 2U, 1U}, {2U, 1U, 1U}});
    const std::filesystem::path none_path = root / L"previews-only.tiff";
    write_fixture(none_path, no_primary);
    expect(
        negaflow::core::probe_tiff_file(none_path).status ==
            TiffProbeStatus::multiple_directories_unsupported,
        "a file of preview pages only is refused");

    // The chain bound also stops a directory list that never terminates.
    negaflow::core::TiffProbeLimits short_chain{};
    short_chain.max_directories = 2U;
    const auto long_chain = make_classic_multi_directory_tiff(
        TiffByteOrder::little_endian,
        {{4U, 2U, 0U}, {2U, 1U, 1U}, {2U, 1U, 1U}});
    const std::filesystem::path chain_path = root / L"long-chain.tiff";
    write_fixture(chain_path, long_chain);
    expect(
        negaflow::core::probe_tiff_file(chain_path, short_chain).status ==
            TiffProbeStatus::directory_limit_exceeded,
        "the directory chain is bounded");
}

}  // namespace tiff_probe_tests
