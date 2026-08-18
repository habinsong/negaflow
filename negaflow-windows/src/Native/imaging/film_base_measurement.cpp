#include "negaflow/imaging/film_base_measurement.h"

#include "film_base_sampling.h"

#include <algorithm>
#include <cmath>
#include <unordered_set>

namespace negaflow::imaging {
namespace {

using film_base_detail::median;

struct Cluster final {
    std::array<double, 3> rgb{};
    std::vector<FilmBaseSample> retained{};
};

[[nodiscard]] std::optional<Cluster> coherent_cluster(
    const std::vector<FilmBaseSample>& samples) {
    if (samples.empty()) {
        return std::nullopt;
    }
    std::vector<double> lumas;
    lumas.reserve(samples.size());
    for (const FilmBaseSample& sample : samples) {
        lumas.push_back(sample.luma());
    }
    const double middle = median(lumas);
    std::vector<double> deviations;
    deviations.reserve(lumas.size());
    for (const double value : lumas) {
        deviations.push_back(std::abs(value - middle));
    }
    const double tolerance = std::max(median(std::move(deviations)) * 1.4826 * 3.0, 1.0e-4);
    std::vector<FilmBaseSample> filtered;
    filtered.reserve(samples.size());
    for (std::size_t index = 0U; index < samples.size(); ++index) {
        if (std::abs(lumas[index] - middle) <= tolerance) {
            filtered.push_back(samples[index]);
        }
    }
    const std::vector<FilmBaseSample>& retained =
        filtered.size() >= std::max<std::size_t>(4U, samples.size() / 4U) ? filtered : samples;
    std::vector<double> red;
    std::vector<double> green;
    std::vector<double> blue;
    red.reserve(retained.size());
    green.reserve(retained.size());
    blue.reserve(retained.size());
    for (const FilmBaseSample& sample : retained) {
        red.push_back(sample.color[0]);
        green.push_back(sample.color[1]);
        blue.push_back(sample.color[2]);
    }
    return Cluster{
        {median(std::move(red)), median(std::move(green)), median(std::move(blue))},
        retained,
    };
}

}  // namespace

double FilmBaseEvidenceComponents::minimum() const noexcept {
    return std::min({
        sample_support,
        sample_coverage,
        spatial_coverage,
        luma_uniformity,
        channel_consistency,
        unclipped_samples,
        inlier_retention,
    });
}

std::optional<FilmBaseMeasurement> build_film_base_measurement(
    const FilmBaseMeasurementMethod method,
    const int sampled_pixel_count,
    const int candidate_count,
    const std::vector<FilmBaseSample>& selected,
    const int grid_width,
    const int grid_height) {
    const std::optional<Cluster> cluster = coherent_cluster(selected);
    if (!cluster.has_value()) {
        return std::nullopt;
    }

    const int selected_count = static_cast<int>(selected.size());
    const int retained_count = static_cast<int>(cluster->retained.size());
    std::vector<double> lumas;
    lumas.reserve(selected.size());
    std::vector<double> red;
    std::vector<double> green;
    std::vector<double> blue;
    red.reserve(selected.size());
    green.reserve(selected.size());
    blue.reserve(selected.size());
    for (const FilmBaseSample& sample : selected) {
        lumas.push_back(sample.luma());
        red.push_back(sample.color[0]);
        green.push_back(sample.color[1]);
        blue.push_back(sample.color[2]);
    }
    const double median_luma = median(lumas);
    std::vector<double> luma_deviations;
    luma_deviations.reserve(lumas.size());
    for (const double value : lumas) {
        luma_deviations.push_back(std::abs(value - median_luma));
    }
    const double luma_mad = median(std::move(luma_deviations));
    const std::array<double, 3> channel_medians{
        median(red), median(green), median(blue)};
    std::vector<double> red_dev;
    std::vector<double> green_dev;
    std::vector<double> blue_dev;
    red_dev.reserve(selected.size());
    green_dev.reserve(selected.size());
    blue_dev.reserve(selected.size());
    for (const FilmBaseSample& sample : selected) {
        red_dev.push_back(std::abs(sample.color[0] - channel_medians[0]));
        green_dev.push_back(std::abs(sample.color[1] - channel_medians[1]));
        blue_dev.push_back(std::abs(sample.color[2] - channel_medians[2]));
    }
    const std::array<double, 3> channel_mad{
        median(std::move(red_dev)),
        median(std::move(green_dev)),
        median(std::move(blue_dev)),
    };

    std::vector<std::array<double, 3>> chromaticities;
    chromaticities.reserve(selected.size());
    std::vector<double> chroma_x;
    std::vector<double> chroma_y;
    std::vector<double> chroma_z;
    chroma_x.reserve(selected.size());
    chroma_y.reserve(selected.size());
    chroma_z.reserve(selected.size());
    for (const FilmBaseSample& sample : selected) {
        const double sum = std::max(sample.color[0] + sample.color[1] + sample.color[2], 1.0e-9);
        const std::array<double, 3> chroma{
            sample.color[0] / sum, sample.color[1] / sum, sample.color[2] / sum};
        chromaticities.push_back(chroma);
        chroma_x.push_back(chroma[0]);
        chroma_y.push_back(chroma[1]);
        chroma_z.push_back(chroma[2]);
    }
    const std::array<double, 3> median_chroma{
        median(std::move(chroma_x)),
        median(std::move(chroma_y)),
        median(std::move(chroma_z)),
    };
    std::vector<double> chroma_dev;
    chroma_dev.reserve(chromaticities.size());
    for (const std::array<double, 3>& chroma : chromaticities) {
        chroma_dev.push_back(std::max({
            std::abs(chroma[0] - median_chroma[0]),
            std::abs(chroma[1] - median_chroma[1]),
            std::abs(chroma[2] - median_chroma[2]),
        }));
    }
    const double chromaticity_mad = median(std::move(chroma_dev));

    int clipped_count = 0;
    for (const FilmBaseSample& sample : selected) {
        const double lo = std::min({sample.color[0], sample.color[1], sample.color[2]});
        const double hi = std::max({sample.color[0], sample.color[1], sample.color[2]});
        if (lo <= 1.0e-4 || hi >= 0.9999) {
            ++clipped_count;
        }
    }

    const double sample_coverage =
        static_cast<double>(selected_count) / static_cast<double>(std::max(1, sampled_pixel_count));
    std::unordered_set<int> xs;
    std::unordered_set<int> ys;
    xs.reserve(static_cast<std::size_t>(selected_count));
    ys.reserve(static_cast<std::size_t>(selected_count));
    for (const FilmBaseSample& sample : selected) {
        xs.insert(sample.x);
        ys.insert(sample.y);
    }
    const double x_coverage =
        static_cast<double>(xs.size()) / static_cast<double>(std::max(1, grid_width));
    const double y_coverage =
        static_cast<double>(ys.size()) / static_cast<double>(std::max(1, grid_height));
    const double spatial_coverage = std::max(x_coverage, y_coverage);
    const double clipped_fraction =
        static_cast<double>(clipped_count) / static_cast<double>(std::max(1, selected_count));
    const double outlier_fraction =
        1.0 - static_cast<double>(retained_count) / static_cast<double>(std::max(1, selected_count));
    const double relative_luma_mad = luma_mad / std::max(std::abs(median_luma), 1.0e-6);
    const FilmBaseEvidenceComponents components{
        std::min(1.0, static_cast<double>(selected_count) / 64.0),
        std::min(1.0, sample_coverage / 0.02),
        std::min(1.0, spatial_coverage),
        std::max(0.0, 1.0 - relative_luma_mad / 0.08),
        std::max(0.0, 1.0 - chromaticity_mad / 0.03),
        std::max(0.0, 1.0 - clipped_fraction / 0.05),
        std::max(0.0, 1.0 - outlier_fraction),
    };

    std::vector<FilmBaseMeasurementAnomaly> anomalies;
    if (method == FilmBaseMeasurementMethod::strip_fallback) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::fallback_estimate);
    }
    if (selected_count < 32) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::low_sample_support);
    }
    if (sample_coverage < 0.02) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::sparse_sample_coverage);
    }
    if (spatial_coverage < 0.65) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::limited_spatial_coverage);
    }
    if (relative_luma_mad > 0.04) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::unstable_luma);
    }
    if (chromaticity_mad > 0.015) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::inconsistent_channels);
    }
    if (clipped_fraction > 0.01) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::clipped_samples);
    }
    if (outlier_fraction > 0.10) {
        anomalies.push_back(FilmBaseMeasurementAnomaly::heavy_outlier_rejection);
    }

    FilmBaseMeasurementDiagnostics diagnostics{};
    diagnostics.schema_version = 1;
    diagnostics.method = method;
    diagnostics.sampled_pixel_count = sampled_pixel_count;
    diagnostics.candidate_count = candidate_count;
    diagnostics.selected_sample_count = selected_count;
    diagnostics.retained_sample_count = retained_count;
    diagnostics.sample_coverage = sample_coverage;
    diagnostics.spatial_coverage = spatial_coverage;
    diagnostics.median_luma = median_luma;
    diagnostics.luma_mad = luma_mad;
    diagnostics.channel_mad = channel_mad;
    diagnostics.chromaticity_mad = chromaticity_mad;
    diagnostics.clipped_fraction = clipped_fraction;
    diagnostics.outlier_fraction = outlier_fraction;
    diagnostics.evidence_components = components;
    diagnostics.evidence_score = components.minimum();
    diagnostics.is_calibrated_probability = false;
    diagnostics.anomalies = std::move(anomalies);

    return FilmBaseMeasurement{cluster->rgb, std::move(diagnostics)};
}

const char* film_base_measurement_method_name(
    const FilmBaseMeasurementMethod method) noexcept {
    switch (method) {
        case FilmBaseMeasurementMethod::connected_component:
            return "connectedComponent";
        case FilmBaseMeasurementMethod::continuous_border:
            return "continuousBorder";
        case FilmBaseMeasurementMethod::distributed_mask:
            return "distributedMask";
        case FilmBaseMeasurementMethod::strip_fallback:
            return "stripFallback";
    }
    return "unknown";
}

const char* film_base_measurement_anomaly_name(
    const FilmBaseMeasurementAnomaly anomaly) noexcept {
    switch (anomaly) {
        case FilmBaseMeasurementAnomaly::fallback_estimate:
            return "fallbackEstimate";
        case FilmBaseMeasurementAnomaly::low_sample_support:
            return "lowSampleSupport";
        case FilmBaseMeasurementAnomaly::sparse_sample_coverage:
            return "sparseSampleCoverage";
        case FilmBaseMeasurementAnomaly::limited_spatial_coverage:
            return "limitedSpatialCoverage";
        case FilmBaseMeasurementAnomaly::unstable_luma:
            return "unstableLuma";
        case FilmBaseMeasurementAnomaly::inconsistent_channels:
            return "inconsistentChannels";
        case FilmBaseMeasurementAnomaly::clipped_samples:
            return "clippedSamples";
        case FilmBaseMeasurementAnomaly::heavy_outlier_rejection:
            return "heavyOutlierRejection";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
