#pragma once

#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::pipeline::develop_export_detail {

// macOS `DevelopSceneMeasurements`(`inversionStats`, `mutedVibranceAmount`)의 Windows 판.
//
// 장면 밀도 범위와 장면 평균 채도는 **같은 프리뷰 프록시 화소**에서 다시 재도 같은 값입니다.
// 그런데 자동 밸런스를 켜 둔 프레임은 슬라이더를 한 번 밀 때마다 둘을 다시 쟀고(1600 만 화소 대신
// 3600 × 2400 프록시에서 약 30 ms), 자동 밸런스를 껐다 켜도 마찬가지였습니다. 프록시를 쥔
// 캐시 항목이 이 메모를 함께 들고 있으면 같은 프록시에 대한 두 번째 요청부터 측정을 건너뜁니다.
//
// 키에는 측정에 들어가는 입력을 모두 넣습니다. 화상은 메모를 가진 캐시 항목이 정하고(같은
// 파일·관측·결함 기록·입력 감마), 그 항목 안에서 크기가 다른 프록시(드래그용 작은 것과 정착본)가
// 섞일 수 있으므로 폭·높이도 키에 있습니다. 베이스(dmin)·크롭·필름 종류가 바뀌면 키가 달라져
// 낡은 값을 쓰지 않습니다.
struct SceneMeasurementInputs final {
    std::array<float, 3> dmin{};
    negaflow::imaging::NegativeFilmType film_type{negaflow::imaging::NegativeFilmType::color};
    std::optional<negaflow::imaging::AnalysisRegion> region{};
    bool legacy_scene_response{false};
    std::uint32_t width{0U};
    std::uint32_t height{0U};

    [[nodiscard]] bool same_range_inputs(const SceneMeasurementInputs& other) const noexcept {
        if (dmin != other.dmin || film_type != other.film_type ||
            legacy_scene_response != other.legacy_scene_response || width != other.width ||
            height != other.height || region.has_value() != other.region.has_value()) {
            return false;
        }
        return !region.has_value() ||
            (region->left == other.region->left && region->top == other.region->top &&
             region->width == other.region->width && region->height == other.region->height);
    }
};

// 채도는 **반전한 화상**에서 재므로 반전에 들어가는 입력이 더 있습니다.
struct SaturationInputs final {
    SceneMeasurementInputs scene{};
    bool use_preset_response{false};
    std::array<float, 3> preset_range_factor{};
    std::optional<std::array<float, 3>> input_gamma_reference_range{};
    std::optional<std::array<float, 3>> channel_range{};
    bool linear_output{false};

    [[nodiscard]] bool same_inputs(const SaturationInputs& other) const noexcept {
        return scene.same_range_inputs(other.scene) &&
            use_preset_response == other.use_preset_response &&
            preset_range_factor == other.preset_range_factor &&
            input_gamma_reference_range == other.input_gamma_reference_range &&
            channel_range == other.channel_range && linear_output == other.linear_output;
    }
};

// 메모를 실제로 쓰는지 시험이 볼 수 있게 하는 계수입니다(relaxed 덧셈 한 번이라 비용은 없습니다).
struct SceneMeasurementMemoCounters final {
    std::atomic<std::uint64_t> range_hits{0U};
    std::atomic<std::uint64_t> range_misses{0U};
    std::atomic<std::uint64_t> saturation_hits{0U};
    std::atomic<std::uint64_t> saturation_misses{0U};
};

inline SceneMeasurementMemoCounters& scene_measurement_memo_counters() noexcept {
    static SceneMeasurementMemoCounters counters;
    return counters;
}

class SceneMeasurementMemo final {
public:
    [[nodiscard]] std::optional<negaflow::imaging::SceneRangeMeasurement> find_range(
        const SceneMeasurementInputs& inputs) const {
        const std::lock_guard lock{mutex_};
        for (const auto& [key, value] : ranges_) {
            if (key.same_range_inputs(inputs)) {
                scene_measurement_memo_counters().range_hits.fetch_add(1U, std::memory_order_relaxed);
                return value;
            }
        }
        scene_measurement_memo_counters().range_misses.fetch_add(1U, std::memory_order_relaxed);
        return std::nullopt;
    }

    void store_range(
        const SceneMeasurementInputs& inputs,
        const negaflow::imaging::SceneRangeMeasurement& value) {
        const std::lock_guard lock{mutex_};
        remember(ranges_, inputs, value, [](const auto& a, const auto& b) {
            return a.same_range_inputs(b);
        });
    }

    [[nodiscard]] std::optional<double> find_saturation(const SaturationInputs& inputs) const {
        const std::lock_guard lock{mutex_};
        for (const auto& [key, value] : saturations_) {
            if (key.same_inputs(inputs)) {
                scene_measurement_memo_counters().saturation_hits.fetch_add(1U, std::memory_order_relaxed);
                return value;
            }
        }
        scene_measurement_memo_counters().saturation_misses.fetch_add(1U, std::memory_order_relaxed);
        return std::nullopt;
    }

    void store_saturation(const SaturationInputs& inputs, const double value) {
        const std::lock_guard lock{mutex_};
        remember(saturations_, inputs, value, [](const auto& a, const auto& b) {
            return a.same_inputs(b);
        });
    }

private:
    // 항목은 소수만 필요하다(같은 프록시에서 베이스·크롭·자동 밸런스를 바꿔 보는 정도).
    static constexpr std::size_t capacity = 8U;

    template <typename Key, typename Value, typename Same>
    static void remember(
        std::vector<std::pair<Key, Value>>& entries, const Key& key, const Value& value,
        const Same& same) {
        for (auto& entry : entries) {
            if (same(entry.first, key)) {
                entry.second = value;
                return;
            }
        }
        if (entries.size() >= capacity) {
            entries.erase(entries.begin());
        }
        entries.emplace_back(key, value);
    }

    mutable std::mutex mutex_;
    std::vector<std::pair<SceneMeasurementInputs, negaflow::imaging::SceneRangeMeasurement>> ranges_;
    std::vector<std::pair<SaturationInputs, double>> saturations_;
};

}  // namespace negaflow::pipeline::develop_export_detail
