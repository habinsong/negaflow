#include "preview_raw_store.h"

#include "export/support/frame_cache_budget.h"

#include <mutex>
#include <utility>
#include <vector>

namespace negaflow::pipeline::develop_export_detail {
namespace {

struct PreviewRawSlot final {
    PreviewRawImage image{};
    PreviewProxyHint hint{};
    // macOS `cachedInteractivePreviewRawDimension` — 요청 치수가 키의 일부입니다.
    std::uint32_t box_width{0};
    std::uint32_t box_height{0};
};

// macOS 한 프레임의 두 슬롯입니다.
struct PreviewRawEntry final {
    PreviewRawKey key{};
    PreviewRawSlot settled{};
    PreviewRawSlot interactive{};
};

[[nodiscard]] std::uint64_t image_bytes(const PreviewRawImage& image) noexcept {
    return image == nullptr
        ? 0ULL
        : static_cast<std::uint64_t>(image->pixels.size()) *
              sizeof(negaflow::core::Rgba32F);
}

[[nodiscard]] std::uint64_t entry_bytes(const PreviewRawEntry& entry) noexcept {
    return image_bytes(entry.settled.image) + image_bytes(entry.interactive.image);
}

// 상주 목록입니다. **앞이 오래된 것** — macOS `residentDevelopedIDs` 와 같은 차례입니다.
std::vector<PreviewRawEntry> g_entries{};
std::mutex g_mutex{};

[[nodiscard]] std::uint64_t budget_bytes() noexcept {
    // 설치 메모리는 고정이지만 Windows 저메모리 상태는 실행 중 바뀝니다.
    return preview_proxy_budget_bytes();
}

// macOS `trimDeveloped` — 한도를 넘으면 **오래된 것부터** 내려놓습니다.
// macOS 는 선택 중인 프레임을 건너뛰고 뒤로 돌립니다. 여기서는 `promote` 가 쓰일 때마다
// 뒤로 다시 등록하므로(=`markDevelopedResident` 의 FIFO 재등록), 현상 중인 프레임은
// 항상 가장 최근 자리에 있어 마지막으로 밀려납니다. **마지막 하나는 남깁니다** —
// 방금 넣은 것을 곧바로 버리면 캐시가 아무 일도 하지 않습니다.
void trim_locked() noexcept {
    std::uint64_t resident = 0ULL;
    for (const PreviewRawEntry& entry : g_entries) {
        resident += entry_bytes(entry);
    }
    const std::uint64_t budget = budget_bytes();
    while (g_entries.size() > 1U && resident > budget) {
        resident -= entry_bytes(g_entries.front());
        g_entries.erase(g_entries.begin());
    }
}

// macOS `markDevelopedResident` 의 앞 두 줄 — 지우고 뒤에 다시 붙입니다.
[[nodiscard]] PreviewRawEntry& promote_locked(const PreviewRawKey& key) {
    for (std::size_t index = 0U; index < g_entries.size(); ++index) {
        if (!same_preview_raw_key(g_entries[index].key, key)) {
            continue;
        }
        PreviewRawEntry moved = std::move(g_entries[index]);
        g_entries.erase(g_entries.begin() + static_cast<std::ptrdiff_t>(index));
        g_entries.push_back(std::move(moved));
        return g_entries.back();
    }
    PreviewRawEntry fresh{};
    fresh.key = key;
    g_entries.push_back(std::move(fresh));
    return g_entries.back();
}

[[nodiscard]] PreviewRawEntry* find_locked(const PreviewRawKey& key) noexcept {
    for (PreviewRawEntry& entry : g_entries) {
        if (same_preview_raw_key(entry.key, key)) {
            return &entry;
        }
    }
    return nullptr;
}

}  // namespace

bool same_preview_raw_key(
    const PreviewRawKey& left,
    const PreviewRawKey& right) noexcept {
    if (left.path != right.path ||
        !negaflow::imageio::same_image_file_observation(
            left.observation, right.observation) ||
        left.base_mode != right.base_mode ||
        left.film_type != right.film_type ||
        left.polarity != right.polarity ||
        left.has_preset != right.has_preset ||
        left.defect_recipe_sha256 != right.defect_recipe_sha256) {
        return false;
    }
    if (!left.has_preset) {
        return true;
    }
    return left.preset_dmin == right.preset_dmin &&
        left.preset_dmax == right.preset_dmax &&
        left.preset_light_gain == right.preset_light_gain;
}

bool preview_raw_take_settled(
    const PreviewRawKey& key,
    PreviewRawImage& image,
    PreviewProxyHint& hint) noexcept {
    const std::lock_guard<std::mutex> guard{g_mutex};
    trim_locked();
    PreviewRawEntry* const entry = find_locked(key);
    if (entry == nullptr || entry->settled.image == nullptr) {
        return false;
    }
    image = entry->settled.image;
    hint = entry->settled.hint;
    return true;
}

bool preview_raw_take_interactive(
    const PreviewRawKey& key,
    const std::uint32_t box_width,
    const std::uint32_t box_height,
    PreviewRawImage& image,
    PreviewProxyHint& hint) noexcept {
    const std::lock_guard<std::mutex> guard{g_mutex};
    trim_locked();
    PreviewRawEntry* const entry = find_locked(key);
    if (entry == nullptr || entry->interactive.image == nullptr ||
        entry->interactive.box_width != box_width ||
        entry->interactive.box_height != box_height) {
        return false;
    }
    image = entry->interactive.image;
    hint = entry->interactive.hint;
    return true;
}

void preview_raw_put_settled(
    const PreviewRawKey& key,
    PreviewRawImage image,
    const PreviewProxyHint& hint) noexcept {
    if (image == nullptr) {
        return;
    }
    try {
        const std::lock_guard<std::mutex> guard{g_mutex};
        PreviewRawEntry& entry = promote_locked(key);
        entry.settled.image = std::move(image);
        entry.settled.hint = hint;
        entry.settled.box_width = 0U;
        entry.settled.box_height = 0U;
        trim_locked();
    } catch (...) {
        // 캐시를 못 채워도 렌더는 이미 끝났습니다. 다음 요청이 다시 만듭니다.
    }
}

void preview_raw_put_interactive(
    const PreviewRawKey& key,
    const std::uint32_t box_width,
    const std::uint32_t box_height,
    PreviewRawImage image,
    const PreviewProxyHint& hint) noexcept {
    if (image == nullptr) {
        return;
    }
    try {
        const std::lock_guard<std::mutex> guard{g_mutex};
        PreviewRawEntry& entry = promote_locked(key);
        entry.interactive.image = std::move(image);
        entry.interactive.hint = hint;
        entry.interactive.box_width = box_width;
        entry.interactive.box_height = box_height;
        trim_locked();
    } catch (...) {
    }
}

void preview_raw_store_reset() noexcept {
    const std::lock_guard<std::mutex> guard{g_mutex};
    g_entries.clear();
}

std::uint64_t preview_raw_store_resident_bytes() noexcept {
    const std::lock_guard<std::mutex> guard{g_mutex};
    std::uint64_t resident = 0ULL;
    for (const PreviewRawEntry& entry : g_entries) {
        resident += entry_bytes(entry);
    }
    return resident;
}

}  // namespace negaflow::pipeline::develop_export_detail
