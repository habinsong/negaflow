#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/basic_tone_model.h"
#include "negaflow/imaging/tone_curve_measurement.h"
#include "negaflow/imaging/tone_mapping.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "tone_mapping_fixture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool nearly_equal(
    const float actual,
    const float expected,
    const float absolute_tolerance =
        negaflow::fixtures::tone_mapping_absolute_tolerance,
    const float relative_tolerance =
        negaflow::fixtures::tone_mapping_relative_tolerance) noexcept {
    const float difference = std::abs(actual - expected);
    const float scale = std::max(std::abs(actual), std::abs(expected));
    return difference <= absolute_tolerance + (relative_tolerance * scale);
}

void expect_pixel_near(
    const negaflow::core::Rgba32F actual,
    const negaflow::core::Rgba32F expected,
    const char* const message) {
    expect(
        nearly_equal(actual.red, expected.red) &&
            nearly_equal(actual.green, expected.green) &&
            nearly_equal(actual.blue, expected.blue) && actual.alpha == expected.alpha,
        message);
}

[[nodiscard]] negaflow::imaging::WorkingImage make_fixture_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 3U;
    image.height = 2U;
    image.stride_pixels = 3U;
    image.pixels.assign(
        negaflow::fixtures::tone_mapping_input.begin(),
        negaflow::fixtures::tone_mapping_input.end());
    return image;
}

void test_fixed_scalar_pipeline_fixture() {
    const auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        make_fixture_image(),
        negaflow::fixtures::tone_mapping_parameters);
    expect(
        adjusted.status == negaflow::imaging::WorkingToneAdjustStatus::ok,
        "combined tone pipeline succeeds");
    expect(adjusted.info.exposure_applied, "combined fixture applies exposure");
    expect(adjusted.info.basic_tone_applied, "combined fixture applies basic tone");
    expect(adjusted.info.parametric_curve_applied, "combined fixture applies curve");
    expect(
        adjusted.info.measurement.info.sampling_mode ==
            negaflow::imaging::ToneCurveSamplingMode::fixed_fallback,
        "small fixture selects the macOS fixed curve bands");
    expect(
        adjusted.image.pixels.size() == negaflow::fixtures::tone_mapping_expected.size(),
        "combined fixture preserves pixel count");
    if (adjusted.image.pixels.size() == negaflow::fixtures::tone_mapping_expected.size()) {
        for (std::size_t index = 0U; index < adjusted.image.pixels.size(); ++index) {
            expect_pixel_near(
                adjusted.image.pixels[index],
                negaflow::fixtures::tone_mapping_expected[index],
                "combined Float32 fixture matches the macOS formula transcription");
        }
    }
}

void test_thresholds_noop_and_user_bounds() {
    negaflow::imaging::WorkingImage source{};
    source.width = 1U;
    source.height = 1U;
    source.stride_pixels = 1U;
    source.pixels = {{0.125F, 0.25F, 0.5F, 0.75F}};

    negaflow::imaging::WorkingToneAdjustParameters threshold{};
    threshold.exposure_stops = 1.0e-3F;
    threshold.basic.contrast = -1.0e-3F;
    threshold.curve.highlights = 1.0e-3F;
    const auto unchanged = negaflow::imaging::apply_working_tone_adjustments(
        source,
        threshold);
    expect(unchanged.status == negaflow::imaging::WorkingToneAdjustStatus::ok, "threshold no-op succeeds");
    expect(!unchanged.info.exposure_applied, "exposure threshold is a no-op");
    expect(!unchanged.info.basic_tone_applied, "basic threshold is a no-op");
    expect(!unchanged.info.parametric_curve_applied, "curve threshold is a no-op");
    expect(!unchanged.info.point_curve_applied, "empty point curves are a no-op");
    expect(!unchanged.info.color_mixer_applied, "empty color mixer is a no-op");
    expect(!unchanged.info.color_grading_applied, "empty color grading is a no-op");
    expect(!unchanged.info.primary_calibration_applied,
           "empty primary calibration is a no-op");
    expect_pixel_near(unchanged.image.pixels[0], source.pixels[0], "threshold no-op is bit exact");

    negaflow::imaging::WorkingToneAdjustParameters exposure{};
    exposure.exposure_stops = 2.0F;
    const auto exposed = negaflow::imaging::apply_working_tone_adjustments(source, exposure);
    expect(exposed.status == negaflow::imaging::WorkingToneAdjustStatus::ok, "bounded exposure succeeds");
    expect(exposed.info.exposure_applied, "bounded exposure is reported");
    // 휘도 0.2415×4 = 0.966 이 무릎(0.70) 위라 숄더로 접히되, 채널비와 1 초과 값은 유지됩니다.
    // 기대값은 macOS Metal 경로(ToneMapper.applyExposure, +2EV)의 결과입니다.
    expect_pixel_near(
        exposed.image.pixels[0],
        {0.453644663F, 0.907289326F, 1.81457865F, 0.75F},
        "positive exposure folds into the shoulder and keeps channel ratios and extended range");

    exposure.exposure_stops = 5.01F;
    const auto excessive = negaflow::imaging::apply_working_tone_adjustments(source, exposure);
    expect(
        excessive.status == negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
            excessive.image.pixels.empty(),
        "exposure outside the UI contract publishes no pixels");

    negaflow::imaging::WorkingToneAdjustParameters invalid_tone{};
    invalid_tone.curve.shadows = -1.01F;
    const auto invalid = negaflow::imaging::apply_working_tone_adjustments(source, invalid_tone);
    expect(
        invalid.status == negaflow::imaging::WorkingToneAdjustStatus::invalid_parameter &&
            invalid.image.pixels.empty(),
        "curve outside the UI contract publishes no pixels");
}

void test_basic_tone_black_anchor_and_stride() {
    const negaflow::core::Rgba32F padding{91.0F, 92.0F, 93.0F, 0.0F};
    std::array<negaflow::core::Rgba32F, 4> input{{
        {0.0F, 0.0F, 0.0F, 1.0F},
        {0.0001F, 0.0001F, 0.0001F, 0.5F},
        padding,
        padding,
    }};
    std::array<negaflow::core::Rgba32F, 4> output{};
    output[2] = padding;
    output[3] = padding;
    negaflow::imaging::BasicToneParameters parameters{};
    parameters.contrast = -1.0F;
    const auto status = negaflow::imaging::apply_basic_tone(
        {input.data(), input.size(), 2U, 1U, 4U},
        {output.data(), output.size(), 2U, 1U, 4U},
        parameters);
    expect(status == negaflow::core::KernelStatus::ok, "negative contrast succeeds");
    expect(output[0].red == 0.0F && output[0].green == 0.0F && output[0].blue == 0.0F,
           "negative contrast anchors absolute black");
    expect(output[1].red < 0.001F, "negative contrast does not wash out near-black");
    expect(output[1].alpha == 0.5F, "basic tone preserves alpha");
    expect(output[2].red == padding.red && output[3].blue == padding.blue,
           "basic tone does not write stride padding");

    parameters.contrast = std::numeric_limits<float>::quiet_NaN();
    expect(
        negaflow::imaging::apply_basic_tone(
            {input.data(), input.size(), 2U, 1U, 4U},
            {output.data(), output.size(), 2U, 1U, 4U},
            parameters) == negaflow::core::KernelStatus::non_finite_parameter,
        "basic tone rejects non-finite parameters");
}

// 밝혀서 한 채널이 1 을 넘을 화소는 그 채널만 잘리지 않고, 목표 휘도를 지킨 채 chroma 만 줄어듭니다.
// 목표 휘도는 같은 휘도의 무채색이 정합니다(무채색은 잘리지 않습니다). macOS
// `ColorModelGamutBehaviorTests.testBrightenedPixelsReachTheTargetLumaInsideTheRange` 와 같은 계약입니다.
void test_basic_tone_lift_folds_chroma_instead_of_clipping() {
    const auto luma = [](const negaflow::core::Rgba32F pixel) noexcept {
        return (0.2126F * pixel.red) + (0.7152F * pixel.green) + (0.0722F * pixel.blue);
    };
    const std::array<negaflow::core::Rgba32F, 3> colours{{
        {0.95F, 0.45F, 0.10F, 1.0F},  // 밝은 주황 — R 이 먼저 1 을 넘는다
        {0.30F, 0.70F, 0.80F, 1.0F},  // 밝은 청록
        {0.70F, 0.45F, 0.35F, 1.0F},  // 연한 피부
    }};
    negaflow::imaging::BasicToneParameters parameters{};
    parameters.highlights = 1.0F;
    parameters.whites = 1.0F;

    for (const negaflow::core::Rgba32F colour : colours) {
        const float y = luma(colour);
        std::array<negaflow::core::Rgba32F, 2> input{{colour, {y, y, y, 1.0F}}};
        std::array<negaflow::core::Rgba32F, 2> output{};
        expect(negaflow::imaging::apply_basic_tone(
                   {input.data(), input.size(), 2U, 1U, 2U},
                   {output.data(), output.size(), 2U, 1U, 2U}, parameters) ==
                   negaflow::core::KernelStatus::ok,
               "lift fixture succeeds");
        const negaflow::core::Rgba32F lifted = output[0];
        const float target = luma(output[1]);
        expect(lifted.red >= 0.0F && lifted.red <= 1.0F && lifted.green >= 0.0F &&
                   lifted.green <= 1.0F && lifted.blue >= 0.0F && lifted.blue <= 1.0F,
               "lifted colour stays inside [0,1]");
        expect(std::abs(luma(lifted) - target) < 1.0e-4F,
               "lifted colour reaches the target luminance instead of clipping short");
        // chroma 는 입력과 같은 방향이고 줄어들 뿐입니다(선형광 색조 보존).
        const float before_red = colour.red - y;
        const float before_green = colour.green - y;
        const float before_blue = colour.blue - y;
        const float after_red = lifted.red - luma(lifted);
        const float after_green = lifted.green - luma(lifted);
        const float after_blue = lifted.blue - luma(lifted);
        const float before_norm_squared = (before_red * before_red) +
            (before_green * before_green) + (before_blue * before_blue);
        const float scale = ((after_red * before_red) + (after_green * before_green) +
                             (after_blue * before_blue)) / before_norm_squared;
        const float residual = std::sqrt(
            std::pow(after_red - (before_red * scale), 2.0F) +
            std::pow(after_green - (before_green * scale), 2.0F) +
            std::pow(after_blue - (before_blue * scale), 2.0F));
        expect(scale >= -1.0e-4F && scale <= 1.0F + 1.0e-3F,
               "lift only shrinks chroma along its own direction");
        expect(residual < 2.0e-4F, "lift keeps the linear hue");
    }

    // 더해도 범위 안에 머무는 리프트는 이전처럼 같은 값을 더한 결과입니다.
    const negaflow::core::Rgba32F mild{0.55F, 0.50F, 0.40F, 1.0F};
    const float mild_luma = luma(mild);
    std::array<negaflow::core::Rgba32F, 2> mild_input{{mild, {mild_luma, mild_luma, mild_luma, 1.0F}}};
    std::array<negaflow::core::Rgba32F, 2> mild_output{};
    negaflow::imaging::BasicToneParameters whites_only{};
    whites_only.whites = 0.5F;
    expect(negaflow::imaging::apply_basic_tone(
               {mild_input.data(), mild_input.size(), 2U, 1U, 2U},
               {mild_output.data(), mild_output.size(), 2U, 1U, 2U}, whites_only) ==
               negaflow::core::KernelStatus::ok,
           "mild lift fixture succeeds");
    const float delta = luma(mild_output[1]) - mild_luma;
    expect(delta > 0.01F, "mild lift fixture reaches the whites mask");
    expect(std::abs(mild_output[0].red - (mild.red + delta)) < 1.0e-5F &&
               std::abs(mild_output[0].green - (mild.green + delta)) < 1.0e-5F &&
               std::abs(mild_output[0].blue - (mild.blue + delta)) < 1.0e-5F,
           "a lift that stays inside the range is still additive");
}

void test_curve_measurement_contract() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    std::vector<negaflow::core::Rgba32F> pixels(
        static_cast<std::size_t>(width) * height,
        {0.25F, 0.25F, 0.25F, 1.0F});
    for (std::uint32_t row = 0U; row < height; ++row) {
        for (std::uint32_t column = 0U; column < width; ++column) {
            if (row < 2U || row >= 62U || column < 2U || column >= 62U) {
                pixels[static_cast<std::size_t>(row) * width + column] =
                    {1.0F, 1.0F, 1.0F, 1.0F};
            }
        }
    }
    const negaflow::core::ConstImageView view{
        pixels.data(), pixels.size(), width, height, width};
    const auto measured = negaflow::imaging::measure_parametric_tone_curve_bands(view);
    expect(measured.status == negaflow::imaging::ToneCurveMeasurementStatus::ok,
           "portable curve measurement succeeds");
    expect(
        measured.info.sampling_mode ==
            negaflow::imaging::ToneCurveSamplingMode::portable_area_v1,
        "portable curve measurement reports its raster algorithm");
    expect(measured.info.target_width == width && measured.info.target_height == height,
           "measurement preserves a 64-pixel source raster");
    expect(measured.info.sampled_luma_count == 3'600U,
           "measurement excludes the four-percent border");
    expect(measured.info.peak_temporary_bytes == 3'600U * sizeof(double),
           "measurement reports bounded temporary storage");
    // 안쪽은 전부 0.25(인코딩 0.5371)라 네 백분위가 같고, 매듭은 그 위로 0.10 씩 벌어집니다
    // (macOS `ParametricToneCurve.knots`).
    const auto bands = measured.info.bands;
    expect(std::abs(bands.knots[0] - 0.53710) < 1.0e-4, "p10 knot is the encoded percentile");
    expect(std::abs(bands.knots[1] - 0.63710) < 1.0e-4 && std::abs(bands.knots[2] - 0.73710) < 1.0e-4 &&
               std::abs(bands.knots[3] - 0.83710) < 1.0e-4,
           "coincident percentiles spread to the minimum knot gap");

    std::array<negaflow::core::Rgba32F, 64> small{};
    const auto fallback = negaflow::imaging::measure_parametric_tone_curve_bands(
        {small.data(), small.size(), 8U, 8U, 8U});
    expect(fallback.status == negaflow::imaging::ToneCurveMeasurementStatus::ok &&
               fallback.info.sampling_mode ==
                   negaflow::imaging::ToneCurveSamplingMode::fixed_fallback,
           "eight-pixel extent uses fixed macOS bands");

    const auto limited = negaflow::imaging::measure_parametric_tone_curve_bands(
        view,
        {100U});
    expect(limited.status == negaflow::imaging::ToneCurveMeasurementStatus::sample_limit_exceeded,
           "measurement honors the memory-work limit");

    const auto malformed = negaflow::imaging::measure_parametric_tone_curve_bands(
        {pixels.data(), pixels.size(), width, height, width - 1U});
    expect(malformed.status == negaflow::imaging::ToneCurveMeasurementStatus::invalid_input &&
               malformed.kernel_status == negaflow::core::KernelStatus::invalid_stride,
           "measurement reports malformed image layout");
}

void test_curve_black_anchor_and_measurement_failure() {
    std::array<negaflow::core::Rgba32F, 2> input{{
        {0.0F, 0.0F, 0.0F, 1.0F},
        {0.02F, 0.02F, 0.02F, 0.25F},
    }};
    std::array<negaflow::core::Rgba32F, 2> output{};
    negaflow::imaging::ParametricToneCurveParameters curve{};
    curve.shadows = 1.0F;
    const auto status = negaflow::imaging::apply_parametric_tone_curve(
        {input.data(), input.size(), 2U, 1U, 2U},
        {output.data(), output.size(), 2U, 1U, 2U},
        curve,
        negaflow::imaging::fallback_parametric_tone_curve_bands());
    expect(status == negaflow::core::KernelStatus::ok, "shadow curve succeeds");
    expect(output[0].red == 0.0F, "shadow curve anchors absolute black");
    expect(output[1].red > input[1].red, "shadow curve lifts visible shadows");
    expect(output[1].alpha == input[1].alpha, "parametric curve preserves alpha");

    negaflow::imaging::WorkingImage large{};
    large.width = 64U;
    large.height = 64U;
    large.stride_pixels = 64U;
    large.pixels.assign(64U * 64U, {0.25F, 0.25F, 0.25F, 1.0F});
    negaflow::imaging::WorkingToneAdjustParameters parameters{};
    parameters.curve.lights = 0.5F;
    const auto failed = negaflow::imaging::apply_working_tone_adjustments(
        std::move(large),
        parameters,
        {100U});
    expect(failed.status == negaflow::imaging::WorkingToneAdjustStatus::measurement_failed &&
               failed.info.measurement.status ==
                   negaflow::imaging::ToneCurveMeasurementStatus::sample_limit_exceeded &&
               failed.image.pixels.empty(),
           "failed curve measurement publishes no adjusted pixels");
}

}  // namespace

// 기본 톤과 파라메트릭 커브는 전역 톤 곡선이라 어떤 슬라이더 조합에서도 단조여야 합니다(macOS
// `ToneMonotonicityTests`). 두 곡선 모두 예전 마스크 × 고정 덧셈 구조에서 ±1 에 뒤집혔습니다.
struct Lcg final {
    std::uint64_t state;
    double next() noexcept {
        state = (state * 6364136223846793005ULL) + 1442695040888963407ULL;
        return static_cast<double>(state >> 11U) / static_cast<double>(1ULL << 53U);
    }
    double uniform(const double low, const double high) noexcept { return low + (next() * (high - low)); }
};

void test_parametric_curve_is_monotone_for_every_combination() {
    Lcg rng{7U};
    std::vector<negaflow::imaging::ParametricToneCurveBands> scenes{
        negaflow::imaging::fallback_parametric_tone_curve_bands(),
        negaflow::imaging::parametric_tone_curve_bands_from_percentiles(0.5, 0.5, 0.5, 0.5),
        negaflow::imaging::parametric_tone_curve_bands_from_percentiles(0.0, 0.0, 0.0001, 0.0002),
        negaflow::imaging::parametric_tone_curve_bands_from_percentiles(0.97, 0.98, 0.99, 1.0),
    };
    for (int i = 0; i < 40; ++i) {
        std::array<double, 4> p{};
        for (double& value : p) { value = std::pow(rng.next(), 2.2); }
        std::sort(p.begin(), p.end());
        scenes.push_back(negaflow::imaging::parametric_tone_curve_bands_from_percentiles(p[0], p[1], p[2], p[3]));
    }
    bool monotone = true;
    bool anchored = true;
    for (const auto& scene : scenes) {
        for (int combo = 0; combo < 30; ++combo) {
            const negaflow::imaging::ParametricToneCurveParameters parameters{
                static_cast<float>(rng.uniform(-1.0, 1.0)), static_cast<float>(rng.uniform(-1.0, 1.0)),
                static_cast<float>(rng.uniform(-1.0, 1.0)), static_cast<float>(rng.uniform(-1.0, 1.0))};
            const auto shape = negaflow::imaging::parametric_tone_curve_shape(parameters, scene);
            double previous = -1.0;
            for (int step = 0; step <= 2048; ++step) {
                const double value = negaflow::imaging::evaluate_parametric_tone_curve(shape, step / 2048.0);
                monotone = monotone && value >= previous - 1.0e-12;
                previous = std::max(previous, value);
            }
            anchored = anchored &&
                       std::abs(negaflow::imaging::evaluate_parametric_tone_curve(shape, 0.0)) < 1.0e-12 &&
                       std::abs(negaflow::imaging::evaluate_parametric_tone_curve(shape, 1.0) - 1.0) < 1.0e-12;
        }
    }
    expect(monotone, "parametric curve never reverses tone for any slider combination or scene");
    expect(anchored, "parametric curve keeps black and white fixed");

    // 매듭은 양 끝·서로 0.10 이상 떨어지므로 ±1 은 자기 매듭을 0.045 이상 움직입니다.
    bool floor_held = true;
    for (const auto& scene : scenes) {
        for (std::size_t k = 0U; k < 4U; ++k) {
            for (const float sign : {-1.0F, 1.0F}) {
                float amounts[4]{0.0F, 0.0F, 0.0F, 0.0F};  // shadows, darks, lights, highlights
                amounts[k] = sign;
                const negaflow::imaging::ParametricToneCurveParameters parameters{
                    amounts[3], amounts[2], amounts[1], amounts[0]};
                const auto shape = negaflow::imaging::parametric_tone_curve_shape(parameters, scene);
                floor_held = floor_held && (shape.y[k + 1U] - shape.x[k + 1U]) * sign >= 0.045 - 1.0e-9;
            }
        }
    }
    expect(floor_held, "every curve slider moves its knot by at least 0.045 at +/-1");
}

// CPU 커널을 회색 램프에 걸어 출력 휘도가 단조이고 `basic_tone_model.h`(자동 톤이 역산하는 식)와
// 같은지 봅니다.
void test_basic_tone_is_monotone_and_matches_the_model() {
    namespace model = negaflow::imaging::basic_tone_model;
    constexpr std::uint32_t count = 1024U;
    std::vector<negaflow::core::Rgba32F> ramp(count);
    for (std::uint32_t i = 0U; i < count; ++i) {
        const float value = negaflow::color::srgb_encoded_to_linear(static_cast<float>(i) / (count - 1U));
        ramp[i] = {value, value, value, 1.0F};
    }
    Lcg rng{11U};
    bool monotone = true;
    float worst = 0.0F;
    for (int combo = 0; combo < 300; ++combo) {
        negaflow::imaging::BasicToneParameters parameters{
            static_cast<float>(rng.uniform(-1.0, 1.0)), static_cast<float>(rng.uniform(-1.0, 1.0)),
            static_cast<float>(rng.uniform(-1.0, 1.0)), static_cast<float>(rng.uniform(-1.0, 1.0)),
            static_cast<float>(rng.uniform(-2.0, 2.0)), static_cast<float>(rng.uniform(-2.0, 2.0))};
        if (combo == 0) { parameters = {0.0F, 0.0F, 0.0F, -1.0F, 0.0F, 0.0F}; }
        if (combo == 1) { parameters = {0.0F, 0.0F, 0.0F, 0.0F, -2.0F, 0.0F}; }
        if (combo == 2) { parameters = {0.0F, -1.0F, -1.0F, 0.0F, 0.0F, 0.0F}; }
        std::vector<negaflow::core::Rgba32F> output(count);
        const auto status = negaflow::imaging::apply_basic_tone(
            {ramp.data(), ramp.size(), count, 1U, count}, {output.data(), output.size(), count, 1U, count},
            parameters);
        expect(status == negaflow::core::KernelStatus::ok, "basic tone succeeds on the ramp");
        float previous = -1.0F;
        for (std::uint32_t i = 0U; i < count; ++i) {
            const float luma = output[i].green;
            monotone = monotone && luma >= previous - 1.0e-7F;
            previous = std::max(previous, luma);
            double t = static_cast<double>(i) / (count - 1U);
            t = model::contrast(t, parameters.contrast);
            t = model::density(t, parameters.density);
            t = model::highlight(t, parameters.highlights);
            t = model::shadow(t, parameters.shadows);
            t = model::whites(t, parameters.whites);
            t = model::blacks(t, parameters.blacks);
            const float expected = negaflow::color::srgb_encoded_to_linear(static_cast<float>(std::clamp(t, 0.0, 1.0)));
            worst = std::max(worst, std::abs(luma - expected));
        }
    }
    expect(monotone, "basic tone never reverses tone for any slider combination");
    expect(worst < 2.0e-4F, "basic tone CPU kernel matches the stepwise model auto tone inverts");
}

int main() {
    test_fixed_scalar_pipeline_fixture();
    test_thresholds_noop_and_user_bounds();
    test_basic_tone_black_anchor_and_stride();
    test_basic_tone_lift_folds_chroma_instead_of_clipping();
    test_curve_measurement_contract();
    test_curve_black_anchor_and_measurement_failure();
    test_parametric_curve_is_monotone_for_every_combination();
    test_basic_tone_is_monotone_and_matches_the_model();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"tone_pipeline\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
