#pragma once

#include <cmath>
#include <cstdint>
#include <span>
#include <optional>
#include <vector>

namespace negaflow::color {

struct InputGammaInterpretation final {
    std::uint32_t mode{0U};
    double value{0.0};
    [[nodiscard]] bool valid() const noexcept {
        return (mode == 0U && value == 0.0) ||
               (mode == 1U && std::isfinite(value) && value >= 0.1 && value <= 4.0);
    }
    bool operator==(const InputGammaInterpretation&) const noexcept = default;
};

enum class InputGammaProfileStatus : std::uint8_t {
    ok, invalid_gamma, invalid_profile, unsupported_profile, allocation_failed
};

struct InputGammaProfileResult final {
    InputGammaProfileStatus status{InputGammaProfileStatus::invalid_profile};
    std::vector<std::uint8_t> bytes{};
};

// RGB 행렬 ICC의 원색·백색점은 유지하고 입력 곡선만 교체합니다.
[[nodiscard]] InputGammaProfileResult make_input_gamma_profile(
    std::span<const std::uint8_t> source,
    InputGammaInterpretation gamma) noexcept;

[[nodiscard]] std::optional<double> recorded_input_gamma(std::span<const std::uint8_t> source) noexcept;

}  // namespace negaflow::color
