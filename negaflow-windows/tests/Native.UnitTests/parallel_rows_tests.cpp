#include "negaflow/core/parallel_rows.h"
#include "negaflow/core/pointwise.h"

#include <atomic>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// The split must cover every row exactly once whatever the block count works out to.
// A gap silently drops part of a photo and an overlap doubles a stage on those rows;
// neither shows up as a crash.
void test_row_coverage() {
    for (const std::uint32_t height : {1U, 2U, 7U, 63U, 64U, 65U, 4944U}) {
        std::vector<std::uint32_t> visits(height, 0U);
        negaflow::core::for_each_row_block(
            height,
            static_cast<std::uint64_t>(height) * 4096ULL,
            [&visits](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                    ++visits[row];
                }
            });
        bool covered = true;
        for (const std::uint32_t count : visits) {
            covered = covered && count == 1U;
        }
        expect(covered, "every row is visited exactly once");
    }
}

void test_small_work_stays_inline() {
    std::atomic<std::uint32_t> peak_extra{0U};
    negaflow::core::for_each_row_block(
        512U,
        1024ULL,
        [&peak_extra](const std::uint32_t, const std::uint32_t) noexcept {
            peak_extra.store(
                negaflow::core::active_row_block_threads(), std::memory_order_relaxed);
        });
    expect(
        peak_extra.load(std::memory_order_relaxed) == 0U,
        "work below the threshold does not create threads");
}

void test_threads_are_released() {
    negaflow::core::for_each_row_block(
        4096U,
        1ULL << 24U,
        [](const std::uint32_t, const std::uint32_t) noexcept {});
    expect(
        negaflow::core::active_row_block_threads() == 0U,
        "the process-wide thread budget returns to zero after a call");
}

// A single-threaded raster scan reports the first failure it meets. Blocks finish in an
// unspecified order, so the smallest failing row has to win even when a later row fails
// first in wall-clock time.
void test_smallest_row_failure_wins() {
    std::atomic<std::uint64_t> slot{negaflow::core::no_row_failure};
    negaflow::core::record_row_failure_value(slot, 900U, 7U);
    negaflow::core::record_row_failure_value(slot, 12U, 3U);
    negaflow::core::record_row_failure_value(slot, 4000U, 9U);
    const std::uint64_t packed = slot.load(std::memory_order_relaxed);
    expect(negaflow::core::has_row_failure(packed), "a recorded failure is observable");
    expect(
        negaflow::core::row_failure_status_value(packed) == 3U,
        "the status of the smallest failing row is the one reported");
}

std::vector<negaflow::core::Rgba32F> ramp_image(
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<negaflow::core::Rgba32F> pixels(
        static_cast<std::size_t>(width) * height);
    for (std::size_t index = 0U; index < pixels.size(); ++index) {
        const float value = static_cast<float>(index % 977U) / 977.0F;
        pixels[index] = {value, 1.0F - value, value * 0.5F, 1.0F};
    }
    return pixels;
}

// The whole point of the row split is that it changes nothing. This runs one transform
// large enough to be split and the same transform forced inline, and compares bits.
void test_parallel_matches_inline_bits() {
    constexpr std::uint32_t width = 733U;
    constexpr std::uint32_t height = 1801U;
    const std::vector<negaflow::core::Rgba32F> source = ramp_image(width, height);
    std::vector<negaflow::core::Rgba32F> parallel(source.size());
    std::vector<negaflow::core::Rgba32F> inline_result(source.size());

    const auto transform = [](const negaflow::core::Rgba32F pixel) noexcept {
        return negaflow::core::Rgba32F{
            std::pow(pixel.red, 0.4545F),
            std::log10(pixel.green + 1.0F),
            std::exp(-pixel.blue),
            pixel.alpha,
        };
    };

    const negaflow::core::ConstImageView input{
        source.data(), source.size(), width, height, width};
    const negaflow::core::ImageView parallel_view{
        parallel.data(), parallel.size(), width, height, width};
    expect(
        negaflow::core::apply_pointwise(input, parallel_view, transform) ==
            negaflow::core::KernelStatus::ok,
        "the split transform succeeds");

    for (std::uint32_t row = 0U; row < height; ++row) {
        for (std::uint32_t column = 0U; column < width; ++column) {
            const std::size_t index = (static_cast<std::size_t>(row) * width) + column;
            inline_result[index] = transform(source[index]);
        }
    }

    bool identical = true;
    for (std::size_t index = 0U; index < source.size(); ++index) {
        identical = identical &&
                    parallel[index].red == inline_result[index].red &&
                    parallel[index].green == inline_result[index].green &&
                    parallel[index].blue == inline_result[index].blue &&
                    parallel[index].alpha == inline_result[index].alpha;
    }
    expect(identical, "the split result is bit-identical to the ordered result");
}

// A non-finite result anywhere must still fail the whole call, and the earliest row is
// the one whose status is reported.
void test_non_finite_output_is_refused() {
    constexpr std::uint32_t width = 512U;
    constexpr std::uint32_t height = 2048U;
    const std::vector<negaflow::core::Rgba32F> source = ramp_image(width, height);
    std::vector<negaflow::core::Rgba32F> destination(source.size());
    const negaflow::core::ConstImageView input{
        source.data(), source.size(), width, height, width};
    const negaflow::core::ImageView output{
        destination.data(), destination.size(), width, height, width};

    const negaflow::core::KernelStatus status = negaflow::core::apply_pointwise(
        input,
        output,
        [](const negaflow::core::Rgba32F pixel) noexcept {
            return negaflow::core::Rgba32F{
                pixel.red + std::numeric_limits<float>::infinity(),
                pixel.green,
                pixel.blue,
                pixel.alpha,
            };
        });
    expect(
        status == negaflow::core::KernelStatus::non_finite_output,
        "a non-finite result refuses the whole pass");
}

}  // namespace

int main() {
    test_row_coverage();
    test_small_work_stays_inline();
    test_threads_are_released();
    test_smallest_row_failure_wins();
    test_parallel_matches_inline_bits();
    test_non_finite_output_is_refused();

    if (failures != 0) {
        std::cerr << failures << " assertion(s) failed\n";
        return 1;
    }
    std::cout << "parallel row block tests passed\n";
    return 0;
}
