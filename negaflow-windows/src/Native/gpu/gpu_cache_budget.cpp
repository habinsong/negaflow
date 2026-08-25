#include "negaflow/gpu/gpu_cache_budget.h"

#include "negaflow/gpu/gpu_device.h"

#include <windows.h>

#include <algorithm>
#include <atomic>

namespace negaflow::gpu {
namespace {

// 설정 창이 건 상한입니다. 0 은 자동입니다. 풀은 여러 스레드에서 들어오므로 원자로 둡니다 —
// 값 하나뿐이라 잠금까지는 필요 없고, 조금 늦게 반영돼도 다음 `ensure` 에서 맞습니다.
std::atomic<std::uint64_t> g_manual_limit_bytes{0ULL};

// 지금 풀이 들고 있는 텍스처 바이트입니다.
std::atomic<std::uint64_t> g_pool_resident_bytes{0ULL};

// 그중 시스템 RAM 에 있는 몫입니다. 외장 그래픽에서는 0 입니다.
std::atomic<std::uint64_t> g_pool_system_memory_bytes{0ULL};

[[nodiscard]] std::uint64_t installed_memory_bytes() noexcept {
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status) == 0) {
        return 0ULL;
    }
    return status.ullTotalPhys;
}

}  // namespace

std::uint64_t GpuCacheBudget::automatic_bytes(const GpuDevice& device) noexcept {
    if (!device.is_usable()) {
        return 0ULL;
    }

    if (device.capability().adapter.is_integrated) {
        // 내장은 VRAM 이 시스템 RAM 입니다. DXGI 예산(공유 메모리 전체)을 믿으면 RAM 캐시와
        // 같은 물리 메모리를 두 번 세게 되므로 설치 RAM 에서 뗍니다.
        const std::uint64_t installed = installed_memory_bytes();
        return installed == 0ULL
            ? 0ULL
            : static_cast<std::uint64_t>(
                  static_cast<double>(installed) * integrated_system_fraction);
    }

    GpuVideoMemoryInfo memory{};
    if (device.query_local_video_memory_info(memory) && memory.budget > 0ULL) {
        return static_cast<std::uint64_t>(
            static_cast<double>(memory.budget) * discrete_budget_fraction);
    }

    // DXGI 가 예산을 안 주면 어댑터가 보고한 전용 VRAM 에서 뗍니다. 그것도 없으면 이 기계의
    // GPU 용량을 모르는 것이므로 막지 않습니다.
    const std::uint64_t dedicated = device.capability().adapter.dedicated_video_memory;
    return dedicated == 0ULL
        ? 0ULL
        : static_cast<std::uint64_t>(
              static_cast<double>(dedicated) * discrete_budget_fraction);
}

std::uint64_t GpuCacheBudget::effective_bytes(const GpuDevice& device) noexcept {
    if (!device.is_usable()) {
        return 0ULL;
    }
    const std::uint64_t manual = g_manual_limit_bytes.load(std::memory_order_relaxed);
    return manual > 0ULL ? manual : automatic_bytes(device);
}

void set_gpu_cache_limit_bytes(const std::uint64_t bytes) noexcept {
    g_manual_limit_bytes.store(bytes, std::memory_order_relaxed);
}

std::uint64_t gpu_cache_limit_bytes() noexcept {
    return g_manual_limit_bytes.load(std::memory_order_relaxed);
}

std::uint64_t gpu_pool_resident_bytes() noexcept {
    return g_pool_resident_bytes.load(std::memory_order_relaxed);
}

void add_gpu_pool_resident_bytes(const std::uint64_t bytes) noexcept {
    g_pool_resident_bytes.fetch_add(bytes, std::memory_order_relaxed);
}

void remove_gpu_pool_resident_bytes(const std::uint64_t bytes) noexcept {
    // 뺄셈이 0 아래로 내려가면 감싸 돌아 거대한 수가 됩니다. 그러면 그 뒤 모든 `ensure` 가
    // 예산 초과로 거부되어 GPU 가 통째로 꺼집니다 — 잘못 세는 것보다 훨씬 큰 사고입니다.
    std::uint64_t current = g_pool_resident_bytes.load(std::memory_order_relaxed);
    while (true) {
        const std::uint64_t next = current > bytes ? current - bytes : 0ULL;
        if (g_pool_resident_bytes.compare_exchange_weak(
                current, next, std::memory_order_relaxed)) {
            return;
        }
    }
}

std::uint64_t gpu_pool_system_memory_bytes() noexcept {
    return g_pool_system_memory_bytes.load(std::memory_order_relaxed);
}

void set_gpu_pool_system_memory_bytes(const std::uint64_t bytes) noexcept {
    g_pool_system_memory_bytes.store(bytes, std::memory_order_relaxed);
}

}  // namespace negaflow::gpu
