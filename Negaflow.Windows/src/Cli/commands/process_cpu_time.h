#pragma once

#include <cstdint>
#include <optional>

namespace negaflow::cli {

struct ProcessCpuTimeSnapshot final {
    bool available{false};
    std::uint64_t kernel_100ns{0};
    std::uint64_t user_100ns{0};
};

[[nodiscard]] ProcessCpuTimeSnapshot query_current_process_cpu_time() noexcept;

[[nodiscard]] std::optional<std::uint64_t> elapsed_process_cpu_microseconds(
    const ProcessCpuTimeSnapshot& started,
    const ProcessCpuTimeSnapshot& finished) noexcept;

}  // namespace negaflow::cli
