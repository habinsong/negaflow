#include "gpu_shared_staging.h"

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_cache_budget.h"
#include "negaflow/core/machine_memory.h"
#include "negaflow/gpu/gpu_working_image.h"

#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <vector>

namespace negaflow::gpu {
namespace {

// 방향마다 두 벌: 가로 사진과 세로 사진이 번갈아 옵니다. 인터랙티브 크기는 정착 크기 슬롯에
// 들어가므로 따로 두지 않습니다.
constexpr std::size_t slots_per_direction = 2U;
// 사진마다 치수가 몇 화소씩 다릅니다(스캔 22장이 3420·3422·3423·3461·3487·3493). 정확한
// 치수로 만들면 사진마다 새 스테이징을 만들고, 새 스테이징은 첫 쓰기 때 페이지를 채우느라
// 126 MB 한 장에 35 ms 를 씁니다(재사용하면 4 ms). 치수를 이 단위로 올려 잡아 재사용합니다.
constexpr std::uint32_t edge_granularity = 256U;
// 이보다 넓은 슬롯은 이 요청에 쓰지 않습니다. 내보내기의 원본 크기 스테이징이 미리보기 동안
// 계속 남지 않게 합니다.
constexpr std::uint64_t maximum_area_ratio = 4U;

struct Slot final {
    ID3D11Device* device{nullptr};
    UINT cpu_access{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint64_t last_use{0U};
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture{};
};

std::mutex g_lock{};
// 텍스처를 쥐고 있으므로 프로세스 종료 때 소멸자를 돌리지 않습니다(`GpuAccelerator::shared` 주석).
std::vector<Slot>& g_slots = *new std::vector<Slot>{};
std::uint64_t g_clock{0U};
std::atomic<std::uint64_t> g_bytes{0U};

[[nodiscard]] std::uint64_t area(const std::uint32_t width, const std::uint32_t height) noexcept {
    return static_cast<std::uint64_t>(width) * height;
}

[[nodiscard]] std::uint32_t rounded_edge(const GpuDevice& device, const std::uint32_t edge) noexcept {
    const std::uint64_t rounded =
        (static_cast<std::uint64_t>(edge) + edge_granularity - 1U) / edge_granularity * edge_granularity;
    const std::uint32_t limit = device.capability().max_texture_dimension;
    return limit != 0U && rounded > limit ? std::max(edge, limit) : static_cast<std::uint32_t>(rounded);
}

}  // namespace

namespace staging_detail {

ID3D11Texture2D* make_staging(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const UINT cpu_access) noexcept {
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1U;
    description.ArraySize = 1U;
    description.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    description.SampleDesc.Count = 1U;
    description.Usage = D3D11_USAGE_STAGING;
    description.BindFlags = 0U;
    description.CPUAccessFlags = cpu_access;

    ID3D11Texture2D* texture = nullptr;
    if (FAILED(device.device()->CreateTexture2D(&description, nullptr, &texture))) {
        return nullptr;
    }
    return texture;
}

namespace {

void erase_slot(const std::vector<Slot>::iterator slot) noexcept {
    g_bytes.fetch_sub(area(slot->width, slot->height) * 16ULL, std::memory_order_relaxed);
    g_slots.erase(slot);
}

std::uint64_t device_bytes(ID3D11Device* const owner) noexcept {
    std::uint64_t bytes = 0;
    for (const auto& slot : g_slots) {
        if (slot.device == owner) { bytes += area(slot.width, slot.height) * 16ULL; }
    }
    return bytes;
}

void trim_locked(ID3D11Device* const owner, const std::uint64_t budget) noexcept {
    std::uint64_t bytes = device_bytes(owner);
    while (bytes > budget) {
        auto oldest = g_slots.end();
        for (auto slot = g_slots.begin(); slot != g_slots.end(); ++slot) {
            if (slot->device == owner &&
                (oldest == g_slots.end() || slot->last_use < oldest->last_use)) { oldest = slot; }
        }
        if (oldest == g_slots.end()) { break; }
        bytes -= area(oldest->width, oldest->height) * 16ULL;
        erase_slot(oldest);
    }
}

std::uint64_t cache_limit(const GpuDevice& device) noexcept {
    // 전송 버퍼는 외장 GPU에서도 시스템 RAM입니다. GPU 설정과 설치 RAM 몫 중 작은 쪽입니다.
    struct LowMemorySignal final {
        HANDLE handle{::CreateMemoryResourceNotification(LowMemoryResourceNotification)};
        ~LowMemorySignal() { if (handle != nullptr) { ::CloseHandle(handle); } }
    };
    static const LowMemorySignal low_memory{};
    BOOL low = FALSE;
    if (low_memory.handle != nullptr && ::QueryMemoryResourceNotification(low_memory.handle, &low) != FALSE && low != FALSE) { return 0; }
    const auto ram_limit = static_cast<std::uint64_t>(
        static_cast<double>(core::installed_memory_bytes()) * GpuCacheBudget::integrated_system_fraction);
    const auto gpu_limit = GpuCacheBudget::effective_bytes(device);
    return gpu_limit == 0 ? ram_limit : std::min(ram_limit, gpu_limit);
}

} // namespace

void trim_shared_staging(const GpuDevice& device, const std::uint64_t budget) noexcept {
    const std::lock_guard<std::mutex> guard{g_lock};
    const auto before = device_bytes(device.device());
    trim_locked(device.device(), budget);
    if (device_bytes(device.device()) != before) { (void)device.flush_released_resources(); }
}

void trim_shared_staging_to_budget(const GpuDevice& device) noexcept {
    trim_shared_staging(device, cache_limit(device));
}

Microsoft::WRL::ComPtr<ID3D11Texture2D> shared_staging(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const UINT cpu_access) noexcept {
    ID3D11Device* const owner = device.device();
    if (owner == nullptr || width == 0U || height == 0U) { return {}; }
    try {
        const std::lock_guard<std::mutex> guard{g_lock};
        ++g_clock;
        const auto wanted = area(width, height);
        const auto budget = cache_limit(device);
        const auto before = device_bytes(owner);
        // 작은 슬롯이 적중해도 과대한 과거 전송 버퍼부터 회수합니다.
        for (auto slot = g_slots.begin(); slot != g_slots.end();) {
            if (slot->device == owner && slot->cpu_access == cpu_access &&
                area(slot->width, slot->height) > wanted * maximum_area_ratio) {
                g_bytes.fetch_sub(area(slot->width, slot->height) * 16ULL, std::memory_order_relaxed);
                slot = g_slots.erase(slot);
            } else { ++slot; }
        }
        trim_locked(owner, budget);
        if (before != device_bytes(owner)) { (void)device.flush_released_resources(); }
        auto best = g_slots.end();
        auto oldest = g_slots.end();
        std::size_t same_direction = 0;
        for (auto slot = g_slots.begin(); slot != g_slots.end(); ++slot) {
            if (slot->device != owner || slot->cpu_access != cpu_access) { continue; }
            ++same_direction;
            if (slot->width >= width && slot->height >= height &&
                (best == g_slots.end() || area(slot->width, slot->height) < area(best->width, best->height))) { best = slot; }
            if (oldest == g_slots.end() || slot->last_use < oldest->last_use) { oldest = slot; }
        }
        if (best != g_slots.end()) { best->last_use = g_clock; return best->texture; }
        if (same_direction >= slots_per_direction) {
            erase_slot(oldest);
            (void)device.flush_released_resources();
        }
        const auto slot_width = rounded_edge(device, width);
        const auto slot_height = rounded_edge(device, height);
        const auto bytes = area(slot_width, slot_height) * 16ULL;
        const auto before_reserve = device_bytes(owner);
        trim_locked(owner, budget > bytes ? budget - bytes : 0);
        if (device_bytes(owner) != before_reserve) { (void)device.flush_released_resources(); }
        Microsoft::WRL::ComPtr<ID3D11Texture2D> created;
        created.Attach(make_staging(device, slot_width, slot_height, cpu_access));
        if (!created) { return {}; }
        // 예산보다 큰 전송도 작업 중에는 허용하되 캐시에 남기지 않습니다.
        if (bytes <= budget) {
            try {
                g_slots.push_back(Slot{owner, cpu_access, slot_width, slot_height, g_clock, created});
                g_bytes.fetch_add(bytes, std::memory_order_relaxed);
            } catch (...) {
                // 캐시 기록용 할당 실패는 현재 전송의 소유권을 잃게 하지 않습니다.
            }
        }
        return created;
    } catch (...) {
        return {};
    }
}

void copy_to_texture(
    ID3D11DeviceContext* const context,
    ID3D11Texture2D* const texture,
    ID3D11Texture2D* const staging,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    const D3D11_BOX box{0U, 0U, 0U, width, height, 1U};
    context->CopySubresourceRegion(texture, 0U, 0U, 0U, 0U, staging, 0U, &box);
}

void copy_to_staging(
    ID3D11DeviceContext* const context,
    ID3D11Texture2D* const staging,
    ID3D11Texture2D* const texture,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    const D3D11_BOX box{0U, 0U, 0U, width, height, 1U};
    context->CopySubresourceRegion(staging, 0U, 0U, 0U, 0U, texture, 0U, &box);
}

}  // namespace staging_detail

std::uint64_t gpu_staging_system_memory_bytes() noexcept {
    return g_bytes.load(std::memory_order_relaxed);
}

}  // namespace negaflow::gpu
