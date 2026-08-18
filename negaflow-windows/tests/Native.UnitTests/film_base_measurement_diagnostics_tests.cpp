#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_base_measurement.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string_view>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool has_anomaly(
    const negaflow::imaging::FilmBaseMeasurementDiagnostics& diagnostics,
    const negaflow::imaging::FilmBaseMeasurementAnomaly anomaly) {
    for (const auto item : diagnostics.anomalies) {
        if (item == anomaly) {
            return true;
        }
    }
    return false;
}

[[nodiscard]] std::vector<negaflow::imaging::FilmBaseSample> samples(
    const std::size_t count,
    const auto& color) {
    std::vector<negaflow::imaging::FilmBaseSample> selected;
    selected.reserve(count);
    for (std::size_t index = 0U; index < count; ++index) {
        const std::array<double, 3> rgb = color(static_cast<int>(index));
        selected.push_back(negaflow::imaging::FilmBaseSample{
            static_cast<int>(index % 16U),
            static_cast<int>(index / 16U),
            rgb,
        });
    }
    return selected;
}

[[nodiscard]] negaflow::imaging::WorkingImage make_border_image(
    const negaflow::core::Rgba32F& border) {
    negaflow::imaging::WorkingImage image{};
    image.width = 160U;
    image.height = 100U;
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            image.pixels[static_cast<std::size_t>(row) * image.width + column] =
                row < 10U ? border : negaflow::core::Rgba32F{0.12F, 0.07F, 0.04F, 1.0F};
        }
    }
    return image;
}

void test_builder_distinguishes_clean_and_inconsistent_channels() {
    const auto clean = negaflow::imaging::build_film_base_measurement(
        negaflow::imaging::FilmBaseMeasurementMethod::continuous_border,
        1600,
        64,
        samples(64U, [](int) { return std::array<double, 3>{0.72, 0.52, 0.34}; }),
        16,
        4);
    const auto mixed = negaflow::imaging::build_film_base_measurement(
        negaflow::imaging::FilmBaseMeasurementMethod::continuous_border,
        1600,
        64,
        samples(64U, [](const int index) {
            return index % 2 == 0
                ? std::array<double, 3>{0.80, 0.45, 0.33}
                : std::array<double, 3>{0.66, 0.58, 0.34};
        }),
        16,
        4);
    expect(clean.has_value() && mixed.has_value(), "builder returns measurements");
    if (!clean.has_value() || !mixed.has_value()) {
        return;
    }
    expect(
        clean->diagnostics.evidence_score > mixed->diagnostics.evidence_score,
        "clean border scores higher than channel-inconsistent samples");
    expect(
        clean->diagnostics.chromaticity_mad < mixed->diagnostics.chromaticity_mad,
        "inconsistent samples raise chromaticity MAD");
    expect(
        !has_anomaly(
            clean->diagnostics,
            negaflow::imaging::FilmBaseMeasurementAnomaly::inconsistent_channels),
        "clean samples do not record inconsistentChannels");
    expect(
        has_anomaly(
            mixed->diagnostics,
            negaflow::imaging::FilmBaseMeasurementAnomaly::inconsistent_channels),
        "mixed samples record inconsistentChannels");
    expect(
        !clean->diagnostics.is_calibrated_probability,
        "evidence is not a calibrated probability");
}

void test_clipped_samples_zero_evidence() {
    const auto clipped = negaflow::imaging::build_film_base_measurement(
        negaflow::imaging::FilmBaseMeasurementMethod::connected_component,
        1600,
        64,
        samples(64U, [](int) { return std::array<double, 3>{1.0, 0.55, 0.20}; }),
        16,
        4);
    expect(clipped.has_value(), "clipped builder returns a measurement");
    if (!clipped.has_value()) {
        return;
    }
    expect(std::abs(clipped->diagnostics.clipped_fraction - 1.0) < 1.0e-4, "clippedFraction is 1");
    expect(
        std::abs(clipped->diagnostics.evidence_components.unclipped_samples) < 1.0e-4,
        "unclippedSamples evidence is 0");
    expect(std::abs(clipped->diagnostics.evidence_score) < 1.0e-4, "evidenceScore is 0");
    expect(
        has_anomaly(
            clipped->diagnostics,
            negaflow::imaging::FilmBaseMeasurementAnomaly::clipped_samples),
        "clipped samples record clippedSamples");
}

void test_auto_base_carries_connected_component_diagnostics() {
    const auto resolved = negaflow::imaging::resolve_auto_negative_base(
        make_border_image({0.72F, 0.52F, 0.34F, 1.0F}),
        negaflow::imaging::NegativeFilmType::color);
    expect(
        resolved.status == negaflow::imaging::AutoNegativeBaseStatus::ok &&
            resolved.source ==
                negaflow::imaging::AutoNegativeBaseSource::connected_component &&
            resolved.diagnostics.has_value(),
        "auto base from a clean border carries diagnostics");
    if (!resolved.diagnostics.has_value()) {
        return;
    }
    expect(
        resolved.diagnostics->method ==
            negaflow::imaging::FilmBaseMeasurementMethod::connected_component,
        "clean border uses connectedComponent");
    expect(resolved.diagnostics->sample_coverage > 0.0, "sampleCoverage is positive");
    expect(resolved.diagnostics->sampled_pixel_count > 0, "sampledPixelCount is positive");
    expect(
        !has_anomaly(
            *resolved.diagnostics,
            negaflow::imaging::FilmBaseMeasurementAnomaly::inconsistent_channels),
        "clean auto base does not record inconsistentChannels");
}

void test_constant_fallback_has_no_measurement() {
    auto clipped = make_border_image({0.98F, 0.98F, 0.98F, 1.0F});
    for (negaflow::core::Rgba32F& pixel : clipped.pixels) {
        pixel = {0.98F, 0.98F, 0.98F, 1.0F};
    }
    const auto resolved = negaflow::imaging::resolve_auto_negative_base(
        clipped,
        negaflow::imaging::NegativeFilmType::color);
    expect(
        resolved.source == negaflow::imaging::AutoNegativeBaseSource::fallback &&
            !resolved.diagnostics.has_value(),
        "constant fallback does not invent measurement confidence");
}

void test_strip_fallback_records_fallback_estimate() {
    const auto strip = negaflow::imaging::build_film_base_measurement(
        negaflow::imaging::FilmBaseMeasurementMethod::strip_fallback,
        400,
        2,
        {
            {0, 0, {0.70, 0.50, 0.30}},
            {1, 0, {0.68, 0.48, 0.28}},
        },
        2,
        1);
    expect(strip.has_value(), "strip builder returns a measurement");
    if (!strip.has_value()) {
        return;
    }
    expect(
        has_anomaly(
            strip->diagnostics,
            negaflow::imaging::FilmBaseMeasurementAnomaly::fallback_estimate),
        "stripFallback always records fallbackEstimate");
    expect(
        std::string_view{negaflow::imaging::film_base_measurement_method_name(
            strip->diagnostics.method)} == "stripFallback",
        "method name matches macOS Codable raw value");
}

}  // namespace

int main() {
    test_builder_distinguishes_clean_and_inconsistent_channels();
    test_clipped_samples_zero_evidence();
    test_auto_base_carries_connected_component_diagnostics();
    test_constant_fallback_has_no_measurement();
    test_strip_fallback_records_fallback_estimate();
    if (failures != 0) {
        std::cerr << "{\"status\":\"error\",\"suite\":\"film_base_measurement_diagnostics\",\"failures\":"
                  << failures << "}\n";
        return 1;
    }
    std::cout << "{\"status\":\"ok\",\"suite\":\"film_base_measurement_diagnostics\"}\n";
    return 0;
}
