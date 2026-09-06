#pragma once

#include "negaflow/imaging/scanner_to_working.h"

namespace negaflow::imaging::detail {
struct InputGammaPreparation final {
    ScannerToWorkingStatus status{ScannerToWorkingStatus::ok};
    std::vector<std::uint8_t> profile{};
    std::vector<float> linear_samples{};

    InputGammaPreparation(std::span<const std::uint8_t> source_profile,
                          negaflow::color::InputGammaInterpretation gamma) {
        if (!gamma.valid()) { status = ScannerToWorkingStatus::invalid_input_gamma; return; }
        if (gamma.mode == 0U) { return; }
        if (!source_profile.empty()) {
            auto prepared = negaflow::color::make_input_gamma_profile(source_profile, gamma);
            switch (prepared.status) {
                case negaflow::color::InputGammaProfileStatus::ok:
                    profile = std::move(prepared.bytes);
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
