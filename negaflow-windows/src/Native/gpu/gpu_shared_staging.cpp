#include "gpu_shared_staging.h"

#include "negaflow/gpu/gpu_device.h"
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
std::vector<Slot> g_slots{};
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

ID3D11Texture2D* shared_staging(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const UINT cpu_access) noexcept {
    ID3D11Device* const owner = device.device();
    if (owner == nullptr || width == 0U || height == 0U) {
        return nullptr;
    }
    try {
        const std::lock_guard<std::mutex> guard{g_lock};
        ++g_clock;
        const std::uint64_t wanted = area(width, height);
        Slot* best = nullptr;
        Slot* oversized = nullptr;
        Slot* oldest = nullptr;
        std::size_t same_direction = 0U;
        for (Slot& slot : g_slots) {
            if (slot.device != owner || slot.cpu_access != cpu_access) {
                continue;
            }
            ++same_direction;
            const std::uint64_t held = area(slot.width, slot.height);
            if (held > wanted * maximum_area_ratio) {
                oversized = &slot;
            } else if (slot.width >= width && slot.height >= height &&
                (best == nullptr || held < area(best->width, best->height))) {
                best = &slot;
            }
            if (oldest == nullptr || slot.last_use < oldest->last_use) {
                oldest = &slot;
            }
        }
        if (best != nullptr) {
            best->last_use = g_clock;
            return best->texture.Get();
        }
        const std::uint32_t slot_width = rounded_edge(device, width);
        const std::uint32_t slot_height = rounded_edge(device, height);
        Slot* const replaced = oversized != nullptr ? oversized
            : same_direction >= slots_per_direction ? oldest
                                                    : nullptr;
        if (replaced != nullptr) {
            // 먼저 놓아야 새 것과 옛 것이 한순간이라도 같이 잡히지 않습니다. 놓은 스테이징은
            // 제출해야 드라이버가 실제로 돌려줍니다(`gpu_image_pool.cpp`).
            g_bytes.fetch_sub(area(replaced->width, replaced->height) * 16ULL, std::memory_order_relaxed);
            replaced->texture.Reset();
            (void)device.flush_released_resources();
        }
        ID3D11Texture2D* const created = make_staging(device, slot_width, slot_height, cpu_access);
        if (created == nullptr) {
            if (replaced != nullptr) {
                g_slots.erase(g_slots.begin() + (replaced - g_slots.data()));
            }
            return nullptr;
        }
        Slot* target = replaced;
        if (target == nullptr) {
            g_slots.emplace_back();
            target = &g_slots.back();
        }
        target->device = owner;
        target->cpu_access = cpu_access;
        target->width = slot_width;
        target->height = slot_height;
        target->last_use = g_clock;
        target->texture.Attach(created);
        g_bytes.fetch_add(area(slot_width, slot_height) * 16ULL, std::memory_order_relaxed);
        return created;
    } catch (...) {
        return nullptr;
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
