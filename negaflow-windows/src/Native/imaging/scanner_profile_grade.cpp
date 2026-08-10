#include "negaflow/imaging/scanner_profile_grade.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>

namespace negaflow::imaging {
namespace {

struct ProfileEntry final {
    std::wstring_view id;
    std::string_view profile_hash;
    ScannerProfileGradeParameters grade;
};

// Source identity: ScannerProfiles/manifest.json schema v2, 15 entries,
// sha256:cf75acb61b8c0999f67bbe3267b3184fa3321dd576b7a63851ab6070ba00efa4.
// Only the bounded grade parameters consumed by ScannerProfileGrade are shipped
// here; no runtime JSON dependency or mutable profile search path is required.
constexpr std::array<ProfileEntry, 15U> profiles{{
    {L"noritsu__color-nega__fuji-c200", "sha256:2d6d46739eea9c4db3b08febafaf8b7a250bedb66edae8bb9c7e24ee63eefb8e", {0.987853286F, 1.057188788F, 1.023620576F, 0.036411574F, 0.990865272F, 1.007617900F, 0.985899712F, 0.222475859F, 0.499468612F, 0.827626259F, 0.057441006F}},
    {L"noritsu__color-nega__kodak-ektar-100", "sha256:7adf6fa75bf6ad94f2692cb2bbf6c8f9ed5fda6fb7c8687a655e69a813945b48", {0.988515184F, 1.078676059F, 1.038113268F, 0.044563713F, 0.972238177F, 1.019610050F, 0.968215531F, 0.214418234F, 0.498901271F, 0.830829271F, 0.111029102F}},
    {L"noritsu__color-nega__kodak-portra-160", "sha256:84d5da481d53e00363d193481f12a4733846528e96401717adc0af11c291d774", {0.968524392F, 1.047398745F, 1.006130374F, 0.026573335F, 0.998868876F, 1.001556677F, 0.996337203F, 0.233920345F, 0.516036235F, 0.832713788F, 0.086024805F}},
    {L"noritsu__color-nega__kodak-portra-400", "sha256:2fc82e71b771137f91e952513fed1248a837b18db4ee2a2ba5bd3388fa81da17", {0.977304314F, 1.114388745F, 1.017503580F, 0.032970764F, 0.997056258F, 1.001032509F, 0.999901136F, 0.209550540F, 0.508510588F, 0.832537129F, 0.087104213F}},
    {L"noritsu__color-nega__kodak-portra-800", "sha256:145d7ccf1a357f30aa5a1b559929e1fd37c09878c3809ca5d1039d5f9e695f2e", {1.039190792F, 1.000000000F, 1.064818654F, 0.059585493F, 0.995216424F, 1.021411345F, 0.940000000F, 0.211743655F, 0.455465035F, 0.795000000F, 0.082881831F}},
    {L"noritsu__color-nega__kodak-pro-image-100", "sha256:053469b4b04b99477e11e338030923a845f43a54488dcfd1b1366dc42e32c942", {0.953268565F, 1.053669608F, 1.012621720F, 0.030224718F, 1.021378614F, 0.987677037F, 1.015794483F, 0.217639310F, 0.529112659F, 0.828532706F, 0.000000000F}},
    {L"noritsu__color-nega__kodak-ultramax-400", "sha256:732c440568ab0c40e00cf1ad5f4931190e52c6b16f724daf9067b1065d135310", {0.982067196F, 1.108277447F, 1.016266727F, 0.032275034F, 0.983805411F, 1.002172998F, 1.010416132F, 0.215509710F, 0.504428118F, 0.835814541F, 0.084001369F}},
    {L"noritsu__color-nega__kodak-vision3-250d", "sha256:e44f5b00354d28103a35a2d4f391eaa4415421cea6613c74a7b14c1b62594892", {1.010798902F, 1.146056667F, 1.029024509F, 0.039451286F, 1.007482902F, 1.010297952F, 0.959868318F, 0.197182243F, 0.479800941F, 0.836033788F, 0.150392646F}},
    {L"noritsu__color-nega__kodak-vision3-50d", "sha256:823dc984b5eb5468de6be39a69a1103d006c46d716bd8d53b04b99d9d48347c8", {0.997331149F, 1.135650537F, 1.030890208F, 0.040500742F, 1.005659873F, 1.005436700F, 0.976996697F, 0.199418306F, 0.491344729F, 0.832551671F, 0.138421565F}},
    {L"noritsu__color-slide__kodak-ektachrome-100", "sha256:388280e1a4d8faea6f2932aa313ddd2aeb82b8fe8ccb631f0f8799c0179fbc84", {0.971376988F, 1.004195620F, 1.098192876F, 0.055858493F, 0.947464530F, 1.009625470F, 1.025739342F, 0.221391129F, 0.513591153F, 0.817392518F, 0.000000000F}},
    {L"noritsu__color-slide__kodak-ektachrome-100d", "sha256:9e0bf700a8b9969298ab249c6274892e46ff860d7539f7450b84b7c57bc9b3e6", {0.997884424F, 1.052327608F, 1.125255735F, 0.071081351F, 0.940000000F, 1.009257236F, 1.048243165F, 0.208062839F, 0.490870494F, 0.821069647F, 0.030013349F}},
    {L"sp-3000__color-nega__kodak-ektar-100", "sha256:c6f151487a607f0c60e46deee5fa03f95ef2a33afa52067cb30d6e8455fdb128", {0.975038125F, 1.065869190F, 1.100000000F, 0.087909555F, 0.975017518F, 1.006849558F, 1.005139017F, 0.220062027F, 0.510453035F, 0.826623012F, 0.116213371F}},
    {L"sp-3000__color-nega__kodak-portra-160", "sha256:80f3e0a41fdfee06a05322c7160315fbc12e9beffaf4aa7d0f63d5e0a4a56723", {0.957870118F, 1.000000000F, 1.042493185F, 0.047027417F, 0.991937917F, 1.009192529F, 0.979839311F, 0.235514612F, 0.525168471F, 0.833700376F, 0.000000000F}},
    {L"sp-3000__color-nega__kodak-vision3-250d", "sha256:b7728cc74c6d452efa113e1e1aa36006f16228016138b490ba88fb745281c111", {0.971980580F, 1.060691318F, 1.045382810F, 0.048652831F, 1.024846753F, 1.001368049F, 0.969325171F, 0.213315059F, 0.513073788F, 0.832500706F, 0.031303387F}},
    {L"sp-3000__color-slide__kodak-ektachrome-100d", "sha256:96c6351c870d2f2520a52bf443951cbc041b8e44d2d75600c35a50b042b554cb", {0.985768110F, 1.060665176F, 1.067131697F, 0.038386580F, 1.013619787F, 0.994803160F, 1.001769100F, 0.208401380F, 0.501255906F, 0.823648282F, 0.000000000F}},
}};

struct Rgb final {
    float red;
    float green;
    float blue;
};

[[nodiscard]] float luminance(const Rgb value) noexcept {
    return (0.2126F * value.red) + (0.7152F * value.green) +
           (0.0722F * value.blue);
}

[[nodiscard]] Rgb saturation(const Rgb value, const float amount) noexcept {
    const float y = luminance(value);
    return {
        y + ((value.red - y) * amount),
        y + ((value.green - y) * amount),
        y + ((value.blue - y) * amount),
    };
}

[[nodiscard]] float tone_curve(
    const float value,
    const ScannerProfileGradeParameters& grade) noexcept {
    constexpr std::array<float, 5U> x{{0.0F, 0.23F, 0.50F, 0.82F, 1.0F}};
    const std::array<float, 5U> y{{
        0.0F,
        grade.shadow_point,
        grade.mid_point,
        grade.highlight_point,
        1.0F,
    }};
    if (value <= 0.0F) return 0.0F;
    if (value >= 1.0F) return 1.0F;

    std::array<float, 4U> slope{};
    for (std::size_t i = 0U; i < slope.size(); ++i) {
        slope[i] = (y[i + 1U] - y[i]) / (x[i + 1U] - x[i]);
    }
    std::array<float, 5U> tangent{};
    tangent.front() = slope.front();
    tangent.back() = slope.back();
    for (std::size_t i = 1U; i + 1U < tangent.size(); ++i) {
        tangent[i] = slope[i - 1U] * slope[i] <= 0.0F
            ? 0.0F
            : 2.0F / ((1.0F / slope[i - 1U]) + (1.0F / slope[i]));
    }

    std::size_t segment = 0U;
    while (segment + 1U < x.size() && value > x[segment + 1U]) ++segment;
    const float width = x[segment + 1U] - x[segment];
    const float t = (value - x[segment]) / width;
    const float t2 = t * t;
    const float t3 = t2 * t;
    return ((2.0F * t3 - 3.0F * t2 + 1.0F) * y[segment]) +
           ((t3 - 2.0F * t2 + t) * width * tangent[segment]) +
           ((-2.0F * t3 + 3.0F * t2) * y[segment + 1U]) +
           ((t3 - t2) * width * tangent[segment + 1U]);
}

[[nodiscard]] Rgb point_grade(
    Rgb value,
    const ScannerProfileGradeParameters& grade) noexcept {
    value.red = std::pow(std::max(value.red, 0.0F), grade.gamma);
    value.green = std::pow(std::max(value.green, 0.0F), grade.gamma);
    value.blue = std::pow(std::max(value.blue, 0.0F), grade.gamma);

    value = saturation(value, grade.saturation);
    value.red = ((value.red - 0.5F) * grade.contrast) + 0.5F;
    value.green = ((value.green - 0.5F) * grade.contrast) + 0.5F;
    value.blue = ((value.blue - 0.5F) * grade.contrast) + 0.5F;

    const float maximum = std::max({value.red, value.green, value.blue});
    const float minimum = std::min({value.red, value.green, value.blue});
    const float chroma = std::clamp(maximum - minimum, 0.0F, 1.0F);
    value = saturation(value, 1.0F + (grade.vibrance * (1.0F - chroma)));

    const float highlight = std::clamp((luminance(value) - 0.50F) / 0.22F, 0.0F, 1.0F);
    const float tint = 1.0F - highlight;
    value.red *= 1.0F + ((grade.red_gain - 1.0F) * tint);
    value.green *= 1.0F + ((grade.green_gain - 1.0F) * tint);
    value.blue *= 1.0F + ((grade.blue_gain - 1.0F) * tint);

    return {
        tone_curve(value.red, grade),
        tone_curve(value.green, grade),
        tone_curve(value.blue, grade),
    };
}

void apply_unsharp(
    const negaflow::core::ImageView image,
    const float amount,
    std::vector<Rgb>& scratch) {
    constexpr std::array<float, 5U> weights{{
        0.124122F, 0.233881F, 0.283994F, 0.233881F, 0.124122F,
    }};
    const auto coordinate = [](const std::int64_t value, const std::uint32_t limit) {
        return static_cast<std::uint32_t>(std::clamp<std::int64_t>(
            value, 0, static_cast<std::int64_t>(limit) - 1));
    };
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            Rgb sum{};
            for (std::int64_t k = -2; k <= 2; ++k) {
                const auto sample = image.pixels[
                    static_cast<std::size_t>(y) * image.stride_pixels +
                    coordinate(static_cast<std::int64_t>(x) + k, image.width)];
                const float weight = weights[static_cast<std::size_t>(k + 2)];
                sum.red += sample.red * weight;
                sum.green += sample.green * weight;
                sum.blue += sample.blue * weight;
            }
            scratch[static_cast<std::size_t>(y) * image.width + x] = sum;
        }
    }
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            Rgb blur{};
            for (std::int64_t k = -2; k <= 2; ++k) {
                const Rgb sample = scratch[
                    static_cast<std::size_t>(coordinate(
                        static_cast<std::int64_t>(y) + k, image.height)) *
                        image.width + x];
                const float weight = weights[static_cast<std::size_t>(k + 2)];
                blur.red += sample.red * weight;
                blur.green += sample.green * weight;
                blur.blue += sample.blue * weight;
            }
            auto& pixel = image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x];
            pixel.red += (pixel.red - blur.red) * amount;
            pixel.green += (pixel.green - blur.green) * amount;
            pixel.blue += (pixel.blue - blur.blue) * amount;
        }
    }
}

}  // namespace

bool try_get_scanner_profile_grade_parameters(
    const std::wstring_view profile_id,
    ScannerProfileGradeParameters& parameters,
    std::string_view& profile_hash) noexcept {
    const auto entry = std::find_if(
        profiles.begin(), profiles.end(), [profile_id](const ProfileEntry& value) {
            return value.id == profile_id;
        });
    if (entry == profiles.end()) return false;
    parameters = entry->grade;
    profile_hash = entry->profile_hash;
    return true;
}

negaflow::core::KernelStatus apply_scanner_profile_grade(
    const negaflow::core::ImageView image,
    const std::wstring_view profile_id,
    ScannerProfileGradeInfo& info) noexcept {
    info = {};
    const auto view = negaflow::core::ConstImageView{
        image.pixels,
        image.pixel_capacity,
        image.width,
        image.height,
        image.stride_pixels,
    };
    const auto view_status = negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) return view_status;
    const auto input_status = negaflow::core::validate_finite_pixels(view);
    if (input_status != negaflow::core::KernelStatus::ok) return input_status;

    ScannerProfileGradeParameters grade{};
    if (!try_get_scanner_profile_grade_parameters(
            profile_id, grade, info.profile_hash)) {
        return negaflow::core::KernelStatus::ok;
    }
    info.profile_found = true;

    try {
        std::vector<Rgb> scratch;
        if (grade.unsharp > 0.0F) {
            scratch.resize(static_cast<std::size_t>(image.width) * image.height);
        }
        for (std::uint32_t y = 0U; y < image.height; ++y) {
            for (std::uint32_t x = 0U; x < image.width; ++x) {
                auto& pixel = image.pixels[
                    static_cast<std::size_t>(y) * image.stride_pixels + x];
                const Rgb result = point_grade(
                    {pixel.red, pixel.green, pixel.blue}, grade);
                pixel.red = result.red;
                pixel.green = result.green;
                pixel.blue = result.blue;
            }
        }
        if (grade.unsharp > 0.0F) {
            apply_unsharp(image, grade.unsharp, scratch);
        }
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    }

    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            auto& pixel = image.pixels[
                static_cast<std::size_t>(y) * image.stride_pixels + x];
            if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                !std::isfinite(pixel.blue)) {
                return negaflow::core::KernelStatus::non_finite_output;
            }
            pixel.red = std::clamp(pixel.red, 0.0F, 1.0F);
            pixel.green = std::clamp(pixel.green, 0.0F, 1.0F);
            pixel.blue = std::clamp(pixel.blue, 0.0F, 1.0F);
        }
    }
    info.applied = true;
    return negaflow::core::KernelStatus::ok;
}

}  // namespace negaflow::imaging
