#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging {

// 화면 색관리: sRGB 로 그린 미리보기를 창이 놓인 모니터의 ICC 공간으로 옮깁니다.
//
// Windows 는 Advanced Color(ACM·WCG·HDR)가 꺼져 있으면 앱 화소를 색관리하지 않고 sRGB 로
// 가정해 그대로 보냅니다. 광색역 모니터에서는 그대로 과포화로 보입니다. 정확한 색이 필요하면
// 앱이 디스플레이 ICC 로 직접 옮겨야 합니다(Microsoft Learn "ICC profile behavior with
// Advanced Color"). Advanced Color 가 켜져 있으면 OS 가 sRGB → 디스플레이 변환을 하고 기본
// 프로파일 API 는 sRGB 를 돌려주므로, 그때 만든 표는 항등이고 부르는 쪽은 적용하지 않습니다.
//
// 매 프레임 ICM 을 부르지 않습니다. 프로파일마다 한 번 ICM 으로 33³ 격자를 옮겨 두고, 화소는
// 사면체 보간으로 행 블록마다 나눠 옮깁니다. ICM 의 BEST_MODE 도 같은 크기의 격자입니다.
class DisplayColorLut final {
public:
    static constexpr std::uint32_t grid = 33U;

    // 시스템과 같은 sRGB(`color::build_icc_profile(srgb)`) → `monitor_icc`. 상대 색도 의도입니다.
    // 프로파일을 열지 못하거나 변환을 만들지 못하면 false 이고 `native_error_code` 에 그 값을
    // 남깁니다.
    //
    // `round_trip` 이면 sRGB → `monitor_icc` → sRGB 왕복 표입니다. 소프트 프루프가 화면 화소를
    // 인화지 프로파일로 갔다가 되돌리는 자리에서 씁니다 — 프레임마다 ICM 을 부르던 것을 표 한
    // 번과 사면체 보간으로 바꿉니다(판정과 같은 BEST_MODE·상대 색도 의도).
    [[nodiscard]] bool build(
        std::span<const std::uint8_t> monitor_icc,
        std::uint32_t& native_error_code,
        bool round_trip = false) noexcept;

    // 격자의 모든 점이 8비트 두 단계 안에서 제자리면 항등입니다(sRGB 모니터, Advanced Color).
    // ICM 자체가 sRGB→sRGB 에서 한 단계쯤 흔들리므로 한 단계로는 가릴 수 없습니다.
    [[nodiscard]] bool identity() const noexcept { return identity_; }
    [[nodiscard]] bool ready() const noexcept { return !table_.empty(); }

    // BGRA8 을 옮깁니다. 알파는 그대로 둡니다. 원본과 목적지는 같은 버퍼여도 됩니다.
    void apply_bgra(
        const std::uint8_t* source,
        std::size_t source_stride_bytes,
        std::uint8_t* destination,
        std::size_t destination_stride_bytes,
        std::uint32_t width,
        std::uint32_t height) const noexcept;

    // 한 색(0…1 RGB)을 표로 옮깁니다. 시험과 검사용입니다.
    void map(const float rgb[3], float out[3]) const noexcept;

private:
    std::vector<float> table_{};  // grid³ × RGB, 인덱스 = ((r · grid) + g) · grid + b
    bool identity_{false};
};

}  // namespace negaflow::imaging
