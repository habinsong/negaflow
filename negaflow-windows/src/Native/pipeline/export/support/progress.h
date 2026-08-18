#pragma once

#include "negaflow/pipeline/develop_export.h"
#include "negaflow/pipeline/stage_timing.h"

#include "negaflow/imageio/image_content_hash.h"
#include "negaflow/imageio/wic_tiff_decoder.h"

#include <cstdint>
#include <stop_token>

namespace negaflow::pipeline::develop_export_detail {

// 진행률 막대에만 쓰는 상대 비용. 결과 화소는 이 숫자에 의존하지 않는다.
struct StageCost final {
    std::uint32_t idle;
    std::uint32_t active;
};

inline constexpr StageCost decode_cost{170U, 170U};
inline constexpr StageCost defect_cost{1U, 60U};
inline constexpr StageCost auto_base_cost{1U, 30U};
inline constexpr StageCost invert_cost{1U, 250U};
inline constexpr StageCost scene_correction_cost{2U, 40U};
inline constexpr StageCost target_grade_cost{1U, 60U};
inline constexpr StageCost color_model_cost{5U, 60U};
inline constexpr StageCost tone_cost{5U, 290U};
inline constexpr StageCost film_look_cost{5U, 300U};
inline constexpr StageCost grain_mend_cost{2U, 900U};
inline constexpr StageCost denoise_cost{2U, 200U};
inline constexpr StageCost dodge_burn_cost{1U, 80U};
inline constexpr StageCost texture_cost{2U, 120U};
inline constexpr StageCost black_and_white_cost{1U, 20U};
inline constexpr StageCost transform_cost{1U, 40U};
inline constexpr StageCost output_sharpening_cost{1U, 80U};
inline constexpr StageCost preview_output_cost{60U, 60U};
inline constexpr StageCost export_output_cost{2600U, 2600U};

[[nodiscard]] constexpr std::uint32_t cost_of(
    const StageCost cost,
    const bool active) noexcept {
    return active ? cost.active : cost.idle;
}

// 이번 요청이 실제로 돌릴 단계의 비용 합. 고정 단계 목록이 아니라 켜진 단계만 더한다.
[[nodiscard]] std::uint32_t plan_total_cost(
    const DevelopExportRequest& request,
    bool preview) noexcept;

// 호출자 소유의 취소·진행 단어를 폴링한다. 관리 코드로 콜백하지 않는다.
class RunTracker final {
public:
    RunTracker(const DevelopRunControl& control, std::uint32_t total_cost) noexcept;

    [[nodiscard]] bool cancelled() const noexcept;
    void begin(DevelopExportStage stage, std::uint32_t cost) noexcept;
    void within(double fraction) noexcept;
    void finish() noexcept;
    void complete() noexcept;

private:
    void publish(std::uint64_t reached) noexcept;

    // 지금 재고 있는 단계와 그 시작 눈금(`QueryPerformanceCounter`).
    // 계측이 꺼져 있으면 둘 다 손대지 않습니다 — 켜지 않은 실행에는 비용이 없습니다.
    DevelopExportStage timed_stage_{DevelopExportStage::none};
    std::int64_t stage_started_{0};

    DevelopRunControl control_{};
    std::uint32_t total_cost_{1U};
    std::uint64_t completed_cost_{0U};
    std::uint32_t stage_cost_{0U};
};

// 디코더 행 진행을 RunTracker 로 넘기고, 취소 래치를 stop_token 으로 옮긴다.
class DecodeProgressBridge final
    : public negaflow::imageio::WicTiffDecodeProgressObserver {
public:
    DecodeProgressBridge(RunTracker& tracker, std::stop_source& source) noexcept;
    void report(negaflow::imageio::WicTiffDecodeProgress progress) noexcept override;

private:
    RunTracker& tracker_;
    std::stop_source& source_;
};

// 내용 해시 바이트 진행을 RunTracker 로 넘긴다.
class HashProgressBridge final
    : public negaflow::imageio::ImageContentHashProgressObserver {
public:
    HashProgressBridge(RunTracker& tracker, std::stop_source& source) noexcept;
    void report(negaflow::imageio::ImageContentHashProgress progress) noexcept override;

private:
    RunTracker& tracker_;
    std::stop_source& source_;
};

}  // namespace negaflow::pipeline::develop_export_detail
