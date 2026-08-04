#include "process_cpu_time.h"

#include <Windows.h>

#include <limits>

namespace negaflow::cli {
namespace {

[[nodiscard]] std::uint64_t file_time_100ns(const FILETIME value) noexcept {
    ULARGE_INTEGER combined{};
    combined.LowPart = value.dwLowDateTime;
    combined.HighPart = value.dwHighDateTime;
    return combined.QuadPart;
}

}  // namespace

ProcessCpuTimeSnapshot query_current_process_cpu_time() noexcept {
    FILETIME creation{};
    FILETIME exit{};
    FILETIME kernel{};
    FILETIME user{};
    if (GetProcessTimes(
            GetCurrentProcess(),
            &creation,
            &exit,
            &kernel,
            &user) == FALSE) {
        return {};
    }
    return {
        true,
        file_time_100ns(kernel),
        file_time_100ns(user),
    };
}

std::optional<std::uint64_t> elapsed_process_cpu_microseconds(
    const ProcessCpuTimeSnapshot& started,
    const ProcessCpuTimeSnapshot& finished) noexcept {
    if (!started.available || !finished.available ||
        finished.kernel_100ns < started.kernel_100ns ||
        finished.user_100ns < started.user_100ns) {
        return std::nullopt;
    }
    const std::uint64_t kernel_delta =
        finished.kernel_100ns - started.kernel_100ns;
    const std::uint64_t user_delta = finished.user_100ns - started.user_100ns;
    if (kernel_delta > std::numeric_limits<std::uint64_t>::max() - user_delta) {
        return std::nullopt;
    }
    return (kernel_delta + user_delta) / 10U;
}

}  // namespace negaflow::cli
