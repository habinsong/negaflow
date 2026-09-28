#include "gpu_shared_staging.h"

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"

#include <wrl/client.h>

#include <atomic>
#include <mutex>
#include <vector>

namespace negaflow::gpu {
namespace {

// 크기 두 벌: 인터랙티브와 정착 프리뷰가 번갈아 청합니다. 풀의 보존 한 벌과 같은 이유입니다.
constexpr std::size_t sizes_per_direction = 2U;

struct Slot final {
    ID3D11Device* device{nullptr};
    UINT cpu_access{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint64_t last_use{0U};
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture{};
};

std::mutex g_lock{};
std::vector<Slot> g_slots{};
std::uint64_t g_clock{0U};
std::atomic<std::uint64_t> g_bytes{0U};

[[nodiscard]] std::uint64_t slot_bytes(const Slot& slot) noexcept {
    return static_cast<std::uint64_t>(slot.width) * slot.height * 16ULL;
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

ID3D11Texture2D* shared_staging(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const UINT cpu_access) noexcept {
    ID3D11Device* const owner = device.device();
    if (owner == nullptr) {
        return nullptr;
    }
    try {
        const std::lock_guard<std::mutex> guard{g_lock};
        ++g_clock;
        Slot* oldest = nullptr;
        std::size_t same_direction = 0U;
        for (Slot& slot : g_slots) {
            if (slot.device != owner || slot.cpu_access != cpu_access) {
                continue;
            }
            if (slot.width == width && slot.height == height) {
                slot.last_use = g_clock;
                return slot.texture.Get();
            }
            ++same_direction;
            if (oldest == nullptr || slot.last_use < oldest->last_use) {
                oldest = &slot;
            }
        }
        ID3D11Texture2D* const created = make_staging(device, width, height, cpu_access);
        if (created == nullptr) {
            return nullptr;
        }
        if (same_direction >= sizes_per_direction && oldest != nullptr) {
            g_bytes.fetch_sub(slot_bytes(*oldest), std::memory_order_relaxed);
            oldest->texture.Attach(created);
            oldest->width = width;
            oldest->height = height;
            oldest->last_use = g_clock;
            // 놓은 스테이징은 제출해야 드라이버가 실제로 돌려줍니다(`gpu_image_pool.cpp`).
            (void)device.flush_released_resources();
            g_bytes.fetch_add(slot_bytes(*oldest), std::memory_order_relaxed);
            return created;
        }
        Slot slot{};
        slot.device = owner;
        slot.cpu_access = cpu_access;
        slot.width = width;
        slot.height = height;
        slot.last_use = g_clock;
        slot.texture.Attach(created);
        g_slots.push_back(std::move(slot));
        g_bytes.fetch_add(slot_bytes(g_slots.back()), std::memory_order_relaxed);
        return created;
    } catch (...) {
        return nullptr;
    }
}

}  // namespace staging_detail

std::uint64_t gpu_staging_system_memory_bytes() noexcept {
    return g_bytes.load(std::memory_order_relaxed);
}

}  // namespace negaflow::gpu
