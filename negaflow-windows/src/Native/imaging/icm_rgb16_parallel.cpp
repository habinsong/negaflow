#include "icm_rgb16_parallel.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <vector>

namespace negaflow::imaging::detail {

ScannerToWorkingStatus ParallelIcmRgb16Transform::initialize(
    const std::span<const std::uint8_t> source_profile_bytes,
    std::uint32_t& native_error_code) {
    profile_.assign(source_profile_bytes.begin(), source_profile_bytes.end());
    transforms_.clear();
    transforms_.resize(negaflow::core::physical_cores());
    transforms_[0] = std::make_unique<IcmRgb16Transform>();
    return transforms_[0]->initialize(profile_, native_error_code);
}

ScannerToWorkingStatus ParallelIcmRgb16Transform::translate(
    const std::uint16_t* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t source_stride_bytes,
    std::uint16_t* const destination,
    const std::uint32_t destination_stride_bytes,
    std::uint32_t& native_error_code,
    const PBMCALLBACKFN progress_callback,
    const LPARAM callback_data) noexcept {
    native_error_code = 0U;
    if (transforms_.empty() || !transforms_[0]) {
        return ScannerToWorkingStatus::invalid_argument;
    }
    const auto parts = static_cast<std::uint32_t>(
        std::min<std::size_t>(transforms_.size(), std::max(height, 1U)));
    const std::uint32_t rows_per_part = (height + parts - 1U) / parts;
    std::atomic<std::uint64_t> failure{negaflow::core::no_row_failure};
    std::vector<std::uint32_t> codes{};
    try {
        codes.resize(parts);
    } catch (...) {
        return ScannerToWorkingStatus::allocation_failed;
    }
    negaflow::core::for_each_row_block(
        parts,
        static_cast<std::uint64_t>(width) * height,
        [&](const std::uint32_t first_part, const std::uint32_t part_count) noexcept {
            for (std::uint32_t part = first_part; part < first_part + part_count; ++part) {
                const std::uint32_t first_row = part * rows_per_part;
                if (first_row >= height) {
                    return;
                }
                std::uint32_t code = 0U;
                ScannerToWorkingStatus status = ScannerToWorkingStatus::ok;
                try {
                    if (!transforms_[part]) {
                        auto created = std::make_unique<IcmRgb16Transform>();
                        status = created->initialize(profile_, code);
                        transforms_[part] = std::move(created);
                    }
                } catch (...) {
                    status = ScannerToWorkingStatus::allocation_failed;
                }
                if (status == ScannerToWorkingStatus::ok) {
                    const std::uint32_t rows = std::min(rows_per_part, height - first_row);
                    status = transforms_[part]->translate(
                        source + static_cast<std::size_t>(first_row) * (source_stride_bytes / 2U),
                        width,
                        rows,
                        source_stride_bytes,
                        destination +
                            static_cast<std::size_t>(first_row) * (destination_stride_bytes / 2U),
                        destination_stride_bytes,
                        code,
                        progress_callback,
                        callback_data);
                }
                if (status != ScannerToWorkingStatus::ok) {
                    codes[part] = code;
                    negaflow::core::record_row_failure(failure, first_row, status);
                    return;
                }
            }
        });
    const std::uint64_t packed = failure.load(std::memory_order_relaxed);
    if (negaflow::core::has_row_failure(packed)) {
        const auto row = static_cast<std::uint32_t>(packed >> 32U);
        native_error_code = codes[row / rows_per_part];
        return static_cast<ScannerToWorkingStatus>(
            negaflow::core::row_failure_status_value(packed));
    }
    return ScannerToWorkingStatus::ok;
}

}  // namespace negaflow::imaging::detail
