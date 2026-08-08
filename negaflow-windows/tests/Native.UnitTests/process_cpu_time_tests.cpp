#include "process_cpu_time.h"

#include <cstdint>
#include <iostream>
#include <limits>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void test_elapsed_conversion() {
    const negaflow::cli::ProcessCpuTimeSnapshot started{true, 100U, 200U};
    const negaflow::cli::ProcessCpuTimeSnapshot finished{true, 135U, 276U};
    const auto elapsed =
        negaflow::cli::elapsed_process_cpu_microseconds(started, finished);
    expect(elapsed.has_value() && *elapsed == 11U,
           "combined FILETIME deltas convert from 100ns units to microseconds");
}

void test_unavailable_and_invalid_intervals() {
    const negaflow::cli::ProcessCpuTimeSnapshot unavailable{};
    const negaflow::cli::ProcessCpuTimeSnapshot valid{true, 10U, 20U};
    expect(
        !negaflow::cli::elapsed_process_cpu_microseconds(unavailable, valid).has_value(),
        "an unavailable snapshot produces no CPU interval");

    const negaflow::cli::ProcessCpuTimeSnapshot backwards{true, 9U, 20U};
    expect(
        !negaflow::cli::elapsed_process_cpu_microseconds(valid, backwards).has_value(),
        "a decreasing process time produces no CPU interval");

    const negaflow::cli::ProcessCpuTimeSnapshot near_limit{true, 0U, 0U};
    const negaflow::cli::ProcessCpuTimeSnapshot overflow{
        true,
        std::numeric_limits<std::uint64_t>::max(),
        std::numeric_limits<std::uint64_t>::max(),
    };
    expect(
        !negaflow::cli::elapsed_process_cpu_microseconds(near_limit, overflow).has_value(),
        "an overflowing combined interval produces no CPU value");
}

void test_live_process_snapshot() {
    const auto started = negaflow::cli::query_current_process_cpu_time();
    const auto finished = negaflow::cli::query_current_process_cpu_time();
    expect(started.available && finished.available,
           "GetProcessTimes is available for the current process");
    expect(
        negaflow::cli::elapsed_process_cpu_microseconds(started, finished).has_value(),
        "live process snapshots form a nondecreasing interval");
}

}  // namespace

int main() {
    test_elapsed_conversion();
    test_unavailable_and_invalid_intervals();
    test_live_process_snapshot();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"process_cpu_time\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
