#pragma once

// macOS `FilmBaseMeasurementDiagnostics` + `FilmBaseMeasurementBuilder` +
// `FilmBaseStatistics.coherentCluster`. 자동 베이스 네 실측 경로가 같은 빌더를 거쳐야
// sidecar 신뢰도와 이상 징후가 추정과 갈라지지 않습니다.

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging {

enum class FilmBaseMeasurementMethod : std::uint8_t {
    connected_component = 0,
    continuous_border,
    distributed_mask,
    strip_fallback,
};

enum class FilmBaseMeasurementAnomaly : std::uint8_t {
    fallback_estimate = 0,
    low_sample_support,
    sparse_sample_coverage,
    limited_spatial_coverage,
    unstable_luma,
    inconsistent_channels,
    clipped_samples,
    heavy_outlier_rejection,
};

struct FilmBaseSample final {
    int x{};
    int y{};
    std::array<double, 3> color{};

    [[nodiscard]] double luma() const noexcept {
        return (color[0] + color[1] + color[2]) / 3.0;
    }
};

struct FilmBaseEvidenceComponents final {
    double sample_support{};
    double sample_coverage{};
    double spatial_coverage{};
    double luma_uniformity{};
    double channel_consistency{};
    double unclipped_samples{};
    double inlier_retention{};

    [[nodiscard]] double minimum() const noexcept;
};

struct FilmBaseMeasurementDiagnostics final {
    int schema_version{1};
    FilmBaseMeasurementMethod method{FilmBaseMeasurementMethod::connected_component};
    int sampled_pixel_count{};
    int candidate_count{};
    int selected_sample_count{};
    int retained_sample_count{};
    double sample_coverage{};
    double spatial_coverage{};
    double median_luma{};
    double luma_mad{};
    std::array<double, 3> channel_mad{};
    double chromaticity_mad{};
    double clipped_fraction{};
    double outlier_fraction{};
    FilmBaseEvidenceComponents evidence_components{};
    double evidence_score{};
    bool is_calibrated_probability{false};
    std::vector<FilmBaseMeasurementAnomaly> anomalies{};
};

struct FilmBaseMeasurement final {
    std::array<double, 3> rgb{};
    FilmBaseMeasurementDiagnostics diagnostics{};
};

// macOS `FilmBaseMeasurementBuilder.build`.
[[nodiscard]] std::optional<FilmBaseMeasurement> build_film_base_measurement(
    FilmBaseMeasurementMethod method,
    int sampled_pixel_count,
    int candidate_count,
    const std::vector<FilmBaseSample>& selected,
    int grid_width,
    int grid_height);

[[nodiscard]] const char* film_base_measurement_method_name(
    FilmBaseMeasurementMethod method) noexcept;

[[nodiscard]] const char* film_base_measurement_anomaly_name(
    FilmBaseMeasurementAnomaly anomaly) noexcept;

}  // namespace negaflow::imaging
