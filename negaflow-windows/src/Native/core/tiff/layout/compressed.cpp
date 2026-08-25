#include "compressed.h"

#include "tiff/io/math.h"
#include "tiff/layout/segments.h"
#include "tiff_deflate_validator.h"
#include "tiff_lzw_validator.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <limits>
#include <memory>
#include <new>
#include <vector>

namespace negaflow::core::tiff_probe_detail {

TiffProbeStatus validate_compressed_segments(
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

    // 세그먼트 기하를 먼저 전부 모읍니다. 여기는 IFD 항목 읽기뿐이라 값싸고, 실패는 이
    // 단계에서 순서대로 판정하므로 어느 세그먼트가 먼저 걸리든 결과가 같습니다.
    struct PlannedSegment final {
        std::uint64_t offset;
        std::uint64_t compressed_bytes;
        std::uint64_t expected_decoded_bytes;
    };
    std::vector<PlannedSegment> planned{};
    try {
        planned.reserve(static_cast<std::size_t>(offsets.count));
    } catch (const std::bad_alloc&) {
        return TiffProbeStatus::invalid_dimensions;
    }

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

        try {
            planned.push_back(
                PlannedSegment{offset, compressed_bytes, expected_decoded_bytes});
        } catch (const std::bad_alloc&) {
            return TiffProbeStatus::invalid_dimensions;
        }
    }

    // TIFF 는 세그먼트마다 ClearCode 로 시작해 EOI 로 끝나는 **독립** 스트림이라 순서를
    // 지킬 필요가 없습니다. 실제 `GT-X900_frame_17`(LZW·492스트립)에서 이 검증만 약 371ms
    // 였습니다. 결과는 세그먼트별로 따로 담고 **아래에서 순서대로** 판정하므로, 병렬로 돌든
    // 순차로 돌든 내는 상태와 누적 합계가 같습니다.
    //
    // reader 는 위치를 공유하므로 그냥 나눠 쓸 수 없습니다. `clone()` 이 독립 reader 를 낼 때만
    // 병렬로 가고, 못 내면 원본 하나로 순차로 갑니다.
    struct SegmentOutcome final {
        detail::TiffLzwValidationStatus lzw_status{detail::TiffLzwValidationStatus::ok};
        detail::TiffDeflateValidationStatus deflate_status{
            detail::TiffDeflateValidationStatus::ok};
        std::uint64_t compressed_bytes_read{0U};
        std::uint64_t code_count{0U};
        std::uint64_t decoded_bytes{0U};
        bool evaluated{false};
    };
    std::vector<SegmentOutcome> outcomes{};
    try {
        outcomes.resize(planned.size());
    } catch (const std::bad_alloc&) {
        return TiffProbeStatus::invalid_dimensions;
    }

    const auto evaluate = [&](const TiffRandomAccessReader& source,
                              const std::size_t index) noexcept {
        const PlannedSegment& segment = planned[index];
        SegmentOutcome& outcome = outcomes[index];
        if (validate_lzw) {
            const detail::TiffLzwValidationResult validation =
                detail::validate_tiff_lzw_segment(
                    source,
                    segment.offset,
                    segment.compressed_bytes,
                    segment.expected_decoded_bytes,
                    control.stop_token);
            outcome.lzw_status = validation.status;
            outcome.compressed_bytes_read = validation.compressed_bytes_read;
            outcome.code_count = validation.code_count;
            outcome.decoded_bytes = validation.decoded_bytes;
        } else {
            const detail::TiffDeflateValidationResult validation =
                detail::validate_tiff_deflate_segment(
                    source,
                    segment.offset,
                    segment.compressed_bytes,
                    segment.expected_decoded_bytes,
                    control.stop_token);
            outcome.deflate_status = validation.status;
            outcome.compressed_bytes_read = validation.compressed_bytes_read;
            outcome.decoded_bytes = validation.decoded_bytes;
        }
        outcome.evaluated = true;
    };

    bool parallel = false;
    if (planned.size() > 1U && planned.size() <= std::numeric_limits<std::uint32_t>::max()) {
        std::uint64_t total_compressed = 0U;
        for (const PlannedSegment& segment : planned) {
            total_compressed += segment.compressed_bytes;
        }
        std::atomic<bool> clone_failed{false};
        negaflow::core::for_each_row_block(
            static_cast<std::uint32_t>(planned.size()),
            total_compressed,
            [&](const std::uint32_t first, const std::uint32_t count) noexcept {
                // 블록마다 독립 reader 를 하나 냅니다. 못 내면 그 블록은 비워 두고, 아래에서
                // 원본 하나로 순차 재시도합니다 - 절반만 검증하고 넘어가지 않습니다.
                std::unique_ptr<TiffRandomAccessReader> local = file.clone();
                if (local == nullptr) {
                    clone_failed.store(true, std::memory_order_relaxed);
                    return;
                }
                for (std::uint32_t index = first; index < first + count; ++index) {
                    if (control.stop_token.stop_requested()) {
                        return;
                    }
                    evaluate(*local, index);
                }
            });
        parallel = !clone_failed.load(std::memory_order_relaxed);
    }
    if (!parallel) {
        for (std::size_t index = 0U; index < planned.size(); ++index) {
            if (control.stop_token.stop_requested()) {
                return TiffProbeStatus::cancelled;
            }
            evaluate(file, index);
        }
    }

    for (const SegmentOutcome& outcome : outcomes) {
        if (!outcome.evaluated) {
            return TiffProbeStatus::cancelled;
        }
        if (validate_lzw) {
            if (outcome.lzw_status == detail::TiffLzwValidationStatus::cancelled) {
                return TiffProbeStatus::cancelled;
            }
            if (outcome.lzw_status == detail::TiffLzwValidationStatus::io_error) {
                return TiffProbeStatus::io_error;
            }
            if (outcome.lzw_status != detail::TiffLzwValidationStatus::ok) {
                return TiffProbeStatus::invalid_compressed_data;
            }
            if (!checked_add(
                    info.compressed_bytes_validated,
                    outcome.compressed_bytes_read,
                    info.compressed_bytes_validated) ||
                !checked_add(
                    info.lzw_code_count,
                    outcome.code_count,
                    info.lzw_code_count) ||
                !checked_add(
                    info.lzw_decoded_bytes_validated,
                    outcome.decoded_bytes,
                    info.lzw_decoded_bytes_validated)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        } else {
            if (outcome.deflate_status == detail::TiffDeflateValidationStatus::cancelled) {
                return TiffProbeStatus::cancelled;
            }
            if (outcome.deflate_status == detail::TiffDeflateValidationStatus::io_error) {
                return TiffProbeStatus::io_error;
            }
            if (outcome.deflate_status != detail::TiffDeflateValidationStatus::ok) {
                return TiffProbeStatus::invalid_compressed_data;
            }
            if (!checked_add(
                    info.compressed_bytes_validated,
                    outcome.compressed_bytes_read,
                    info.compressed_bytes_validated) ||
                !checked_add(
                    info.deflate_decoded_bytes_validated,
                    outcome.decoded_bytes,
                    info.deflate_decoded_bytes_validated)) {
                return TiffProbeStatus::invalid_dimensions;
            }
        }
    }
    info.lzw_code_streams_validated = validate_lzw;
    info.deflate_streams_validated = validate_deflate;
    return TiffProbeStatus::ok;
}

}  // namespace negaflow::core::tiff_probe_detail
