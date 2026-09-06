#include "negaflow/color/input_gamma_profile.h"
#include "negaflow/color/icc_profile.h"
#include "negaflow/imaging/film_base_scale.h"
#include "../fixtures/v1/synthetic_parity_icc_profile.h"

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>

namespace {
int failures = 0;
void expect(bool value, const char* message) {
    if (!value) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}
std::uint32_t read32(const std::vector<std::uint8_t>& data, std::size_t at) {
    std::uint32_t value = 0;
    for (std::size_t i = 0; i < 4; ++i) { value = (value << 8U) | data[at + i]; }
    return value;
}
}  // namespace

int main() {
    using namespace negaflow::color;
    const auto original = negaflow::fixtures::build_synthetic_parity_profile();
    expect(InputGammaInterpretation{}.valid(), "automatic gamma");
    for (double value : {0.0, -1.0, 4.001, std::numeric_limits<double>::infinity(),
                         std::numeric_limits<double>::quiet_NaN()}) {
        expect(!InputGammaInterpretation{1U, value}.valid(), "invalid gamma must fail");
    }
    expect(!InputGammaInterpretation{0U, 1.0}.valid(), "automatic value must be zero");
    for (double gamma : {0.1, 1.0, 1.2345, 1.8, 2.2, 2.4, 4.0}) {
        const auto result = make_input_gamma_profile(original, {1U, gamma});
        expect(result.status == InputGammaProfileStatus::ok, "matrix ICC accepts power");
        if (result.status != InputGammaProfileStatus::ok) { continue; }
        expect(validate_icc_profile(result.bytes).status == IccProfileStatus::ok, "rebuilt ICC validates");
        for (std::size_t i = 0; i < read32(original, 128U); ++i) {
            const auto record = 132U + i * 12U;
            const auto name = read32(original, record);
            const auto old_offset = read32(original, record + 4U);
            const auto new_offset = read32(result.bytes, record + 4U);
            const auto old_size = read32(original, record + 8U);
            if (name == 0x72545243U || name == 0x67545243U || name == 0x62545243U) {
                if (gamma == 1.0) {
                    expect(read32(result.bytes, new_offset + 8U) == 0U, "identity gamma uses exact ICC identity curve");
                    continue;
                }
                expect(read32(result.bytes, new_offset + 8U) == 65536U, "every source code has a TRC sample");
                for (std::size_t code = 0; code < 65536U; ++code) {
                    const auto at = new_offset + 12U + code * 2U;
                    const auto sample = (static_cast<std::uint32_t>(result.bytes[at]) << 8U) | result.bytes[at + 1U];
                    expect(std::abs(static_cast<double>(sample) / 65535.0 -
                        std::pow(static_cast<double>(code) / 65535.0, gamma)) <= 0.50001 / 65535.0,
                        "TRC matches CPU power within 16-bit quantization");
                }
            } else {
                expect(read32(result.bytes, record + 8U) == old_size, "non-TRC tag length preserved");
                expect(std::equal(original.begin() + old_offset, original.begin() + old_offset + old_size,
                                  result.bytes.begin() + new_offset), "primaries and adaptation preserved");
            }
        }
    }
    const auto recorded = recorded_input_gamma(original);
    expect(recorded && std::abs(*recorded - 563.0 / 256.0) < 1e-12, "recorded ICC power retains precision");
    const auto linear = make_input_gamma_profile(original, {1U, 1.0});
    expect(recorded_input_gamma(linear.bytes) == 1.0, "identity curve is gamma one");
    const auto sampled = make_input_gamma_profile(original, {1U, 1.8});
    expect(!recorded_input_gamma(sampled.bytes), "sampled curve is not mislabeled as scalar gamma");
    auto lut = original;
    lut[132] = 'A'; lut[133] = '2'; lut[134] = 'B'; lut[135] = '0';
    expect(make_input_gamma_profile(lut, {1U, 1.8}).status == InputGammaProfileStatus::unsupported_profile,
           "mixed LUT profile must fail");
    for (std::size_t size = 0; size < original.size(); ++size) {
        expect(make_input_gamma_profile(std::span(original).first(size), {1U, 1.8}).status != InputGammaProfileStatus::ok,
               "truncated profile must fail");
    }
    const std::array<float, 3> reference{0.77F, 0.25F, 0.16F};
    const auto half = negaflow::imaging::scale_auto_film_base(reference, 0.5);
    const auto more = negaflow::imaging::scale_auto_film_base(reference, 1.5);
    expect(half[0] == reference[0] * 0.5F && half[1] == 0.125F, "half base once");
    expect(more[0] == 1.0F && more[1] == 0.375F, "per-channel clamp");
    expect(negaflow::imaging::scale_auto_film_base(reference, 1.0) == reference, "identity base unchanged");
    for (double value : {0.49, 1.51, std::numeric_limits<double>::quiet_NaN()}) {
        expect(!negaflow::imaging::valid_film_base_scale(value), "invalid scale must fail");
    }
    std::cout << "input gamma and base scale failures=" << failures << '\n';
    return failures == 0 ? 0 : 1;
}
