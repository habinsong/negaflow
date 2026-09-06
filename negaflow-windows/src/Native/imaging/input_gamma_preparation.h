#pragma once

#include "negaflow/imaging/scanner_to_working.h"

namespace negaflow::imaging::detail {
struct InputGammaPreparation final {
    ScannerToWorkingStatus status{ScannerToWorkingStatus::ok};
    std::vector<std::uint8_t> profile{};
    std::vector<float> linear_samples{};
    std::vector<std::uint16_t> encoded_samples{};

    InputGammaPreparation(std::span<const std::uint8_t> source_profile,
                          negaflow::color::InputGammaInterpretation gamma) {
        if (!gamma.valid()) { status = ScannerToWorkingStatus::invalid_input_gamma; return; }
        if (gamma.mode == 0U) { return; }
        if (!source_profile.empty()) {
            // 큰 sampled TRC를 CMM에 넘기지 않습니다. 원본 코드는 정확한 LUT로 바꾸고
            // ICM에는 원색/색순응을 보존한 선형 프로파일을 전달합니다.
            auto prepared = negaflow::color::make_input_gamma_profile(source_profile, {1U, 1.0});
            switch (prepared.status) {
                case negaflow::color::InputGammaProfileStatus::ok:
                    profile = std::move(prepared.bytes);
                    if (gamma.value != 1.0) {
                        encoded_samples.resize(65536U);
                        for (std::size_t i = 0U; i < encoded_samples.size(); ++i) {
                            encoded_samples[i] = static_cast<std::uint16_t>(std::lround(
                                std::pow(static_cast<double>(i) / 65535.0, gamma.value) * 65535.0));
                        }
                    }
                    return;
                case negaflow::color::InputGammaProfileStatus::invalid_gamma:
                    status = ScannerToWorkingStatus::invalid_input_gamma;
                    return;
                case negaflow::color::InputGammaProfileStatus::unsupported_profile:
                    status = ScannerToWorkingStatus::unsupported_input_gamma;
                    return;
                case negaflow::color::InputGammaProfileStatus::allocation_failed:
                    status = ScannerToWorkingStatus::allocation_failed;
                    return;
                case negaflow::color::InputGammaProfileStatus::invalid_profile:
                    status = ScannerToWorkingStatus::invalid_icc_profile;
                    return;
            }
        }
        linear_samples.resize(65536U);
        for (std::size_t i = 0U; i < linear_samples.size(); ++i) {
            linear_samples[i] = static_cast<float>(std::pow(static_cast<double>(i) / 65535.0, gamma.value));
        }
    }
};
}  // namespace negaflow::imaging::detail
