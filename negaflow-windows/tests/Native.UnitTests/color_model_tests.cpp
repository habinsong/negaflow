#include "negaflow/imaging/bounded_chroma_scale.h"
#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/white_balance.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <string>
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

[[nodiscard]] bool exact_pixel(
    const negaflow::core::Rgba32F left,
    const negaflow::core::Rgba32F right) noexcept {
    return left.red == right.red && left.green == right.green &&
           left.blue == right.blue && left.alpha == right.alpha;
}

void test_identity_and_fixed_matrix_controls() {
    std::array<negaflow::core::Rgba32F, 3> pixels{{
        {-0.2F, 0.4F, 1.2F, 0.25F},
        {0.6F, 0.3F, 0.1F, 1.0F},
        {91.0F, 92.0F, 93.0F, 0.0F},
    }};
    const auto original = pixels;
    expect(
        negaflow::imaging::apply_color_model(
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            {}) == negaflow::core::KernelStatus::ok &&
            exact_pixel(pixels[0], original[0]) &&
            exact_pixel(pixels[1], original[1]) &&
            exact_pixel(pixels[2], original[2]),
        "identity ColorModel preserves extended pixels and padding");

    negaflow::imaging::ColorModelParameters controls{};
    controls.warmth = 1.0F;
    controls.tint = 1.0F;
    controls.red_primary = 0.5F;
    pixels = original;
    // ±1 끝값의 채널 게인은 예전 그대로(온도 1.18/1.03/0.82 × 틴트 0.88/1.24/0.88)이고,
    // 휘도(Rec.709)를 1 로 정규화합니다 — 화이트밸런스는 색만 바꿉니다.
    const double red_gain = 1.18 * 0.88;
    const double green_gain = 1.03 * 1.24;
    const double blue_gain = 0.82 * 0.88;
    const double luminance = (0.2126 * red_gain) + (0.7152 * green_gain) + (0.0722 * blue_gain);
    expect(
        negaflow::imaging::apply_color_model(
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            {pixels.data(), pixels.size(), 2U, 1U, 3U},
            controls) == negaflow::core::KernelStatus::ok &&
            std::abs(pixels[1].red - static_cast<float>(0.6 * red_gain / luminance * 1.16)) < 2.0e-6F &&
            std::abs(pixels[1].green - static_cast<float>(0.3 * green_gain / luminance)) < 2.0e-6F &&
            std::abs(pixels[1].blue - static_cast<float>(0.1 * blue_gain / luminance)) < 2.0e-6F &&
            pixels[1].alpha == 1.0F && exact_pixel(pixels[2], original[2]),
        "ColorModel applies macOS matrix controls in fixed order");
}

void test_chroma_controls_and_validation() {
    negaflow::core::Rgba32F low_chroma{0.52F, 0.50F, 0.48F, 0.75F};
    const auto original = low_chroma;
    negaflow::imaging::ColorModelParameters controls{};
    controls.color_depth = 0.5F;
    controls.vibrance = 0.5F;
    controls.saturation = 0.5F;
    expect(
        negaflow::imaging::apply_color_model(
            {&low_chroma, 1U, 1U, 1U, 1U},
            {&low_chroma, 1U, 1U, 1U, 1U},
            controls) == negaflow::core::KernelStatus::ok &&
            (low_chroma.red - low_chroma.blue) >
                (original.red - original.blue) &&
            low_chroma.alpha == original.alpha,
        "ColorModel chroma controls increase low-chroma separation");

    controls = {};
    controls.tint = 1.01F;
    expect(negaflow::imaging::valid_color_model_parameters(controls),
           "white balance accepts the extended range beyond one");
    controls.tint = 4.01F;
    expect(!negaflow::imaging::valid_color_model_parameters(controls),
           "ColorModel rejects white balance outside the slider range");
    controls = {};
    controls.color_depth = 1.01F;
    expect(!negaflow::imaging::valid_color_model_parameters(controls),
           "ColorModel rejects chroma controls outside the slider range");
    controls.tint = std::numeric_limits<float>::quiet_NaN();
    expect(
        negaflow::imaging::apply_color_model(
            {&low_chroma, 1U, 1U, 1U, 1U},
            {&low_chroma, 1U, 1U, 1U, 1U},
            controls) == negaflow::core::KernelStatus::non_finite_parameter,
        "ColorModel rejects non-finite controls");
}

[[nodiscard]] std::vector<negaflow::core::Rgba32F> read_rgba_f32(
    const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    std::vector<negaflow::core::Rgba32F> pixels(256U * 141U);
    input.read(
        reinterpret_cast<char*>(pixels.data()),
        static_cast<std::streamsize>(pixels.size() * sizeof(negaflow::core::Rgba32F)));
    expect(
        (input.good() || input.eof()) &&
            input.gcount() == static_cast<std::streamsize>(pixels.size() * sizeof(negaflow::core::Rgba32F)),
        "vibrance f32 golden is readable");
    pixels.resize(33U * 33U * 33U);
    return pixels;
}

[[nodiscard]] float max_rgb_difference(
    const std::vector<negaflow::core::Rgba32F>& actual,
    const std::vector<negaflow::core::Rgba32F>& expected) noexcept {
    if (actual.size() != expected.size()) return std::numeric_limits<float>::infinity();
    float maximum = 0.0F;
    for (std::size_t index = 0U; index < actual.size(); ++index) {
        maximum = std::max(maximum, std::abs(actual[index].red - expected[index].red));
        maximum = std::max(maximum, std::abs(actual[index].green - expected[index].green));
        maximum = std::max(maximum, std::abs(actual[index].blue - expected[index].blue));
        maximum = std::max(maximum, std::abs(actual[index].alpha - expected[index].alpha));
    }
    return maximum;
}

void test_civibrance_goldens(const std::filesystem::path& golden_root) {
    const auto input = read_rgba_f32(golden_root / L"civibrance33-input-256x141.f32");
    struct Case final {
        float amount;
        const wchar_t* file;
    };
    constexpr Case cases[]{
        {-0.80F, L"civibrance33-am0.800-256x141.f32"},
        {-0.60F, L"civibrance33-am0.600-256x141.f32"},
        {-0.40F, L"civibrance33-am0.400-256x141.f32"},
        {-0.20F, L"civibrance33-am0.200-256x141.f32"},
        {-0.05F, L"civibrance33-am0.050-256x141.f32"},
        { 0.05F, L"civibrance33-a0.050-256x141.f32"},
        { 0.10F, L"civibrance33-a0.100-256x141.f32"},
        { 0.15F, L"civibrance33-a0.150-256x141.f32"},
        { 0.20F, L"civibrance33-a0.200-256x141.f32"},
        { 0.25F, L"civibrance33-a0.250-256x141.f32"},
        { 0.30F, L"civibrance33-a0.300-256x141.f32"},
        { 0.35F, L"civibrance33-a0.350-256x141.f32"},
        { 0.40F, L"civibrance33-a0.400-256x141.f32"},
        { 0.45F, L"civibrance33-a0.450-256x141.f32"},
        { 0.50F, L"civibrance33-a0.500-256x141.f32"},
        { 0.60F, L"civibrance33-a0.600-256x141.f32"},
        { 0.80F, L"civibrance33-a0.800-256x141.f32"},
    };
    for (const Case& entry : cases) {
        auto actual = input;
        negaflow::imaging::ColorModelParameters parameters{};
        parameters.vibrance = entry.amount / 0.8F;
        const auto status = negaflow::imaging::apply_color_model(
            {actual.data(), actual.size(), static_cast<std::uint32_t>(actual.size()), 1U,
             static_cast<std::uint32_t>(actual.size())},
            {actual.data(), actual.size(), static_cast<std::uint32_t>(actual.size()), 1U,
             static_cast<std::uint32_t>(actual.size())},
            parameters);
        const auto expected = read_rgba_f32(golden_root / entry.file);
        const float difference = max_rgb_difference(actual, expected);
        if (difference >= 0.0020F) {
            std::cerr << "  vibrance amount=" << entry.amount
                      << " max_abs_difference=" << difference << '\n';
        }
        expect(
            status == negaflow::core::KernelStatus::ok && difference < 0.0020F,
            "ColorModel vibrance follows the full cross-platform golden range");
    }
}

// 온도·틴트 법칙(macOS `WhiteBalanceGainsTests` 와 같은 계약).
// 채도·색 깊이 끝 보호 계약입니다 — macOS `ColorModelGamutBehaviorTests` 와 같은 격자·같은 검사입니다.
// 입력은 채널 값 6단계의 모든 조합(216색)이라 한 채널이 0 이거나 0.95 인 원색·2차색을 모두 지납니다.
[[nodiscard]] float rec709_luma(const negaflow::core::Rgba32F pixel) noexcept {
    return (0.2126F * pixel.red) + (0.7152F * pixel.green) + (0.0722F * pixel.blue);
}

[[nodiscard]] float chroma_norm(const negaflow::core::Rgba32F pixel) noexcept {
    const float y = rec709_luma(pixel);
    return std::sqrt(
        ((pixel.red - y) * (pixel.red - y)) + ((pixel.green - y) * (pixel.green - y)) +
        ((pixel.blue - y) * (pixel.blue - y)));
}

[[nodiscard]] std::vector<negaflow::core::Rgba32F> make_gamut_grid() {
    constexpr std::array<float, 6> levels{0.0F, 0.05F, 0.15F, 0.4F, 0.7F, 0.95F};
    std::vector<negaflow::core::Rgba32F> pixels;
    for (const float red : levels) {
        for (const float green : levels) {
            for (const float blue : levels) {
                pixels.push_back({red, green, blue, 1.0F});
            }
        }
    }
    return pixels;
}

// 휘도를 고정한 채 chroma 를 몇 배까지 키울 수 있는지 — 구현(`chroma_scale_headroom`)을 부르지
// 않고 기대값을 만들도록 시험 안에 따로 적었습니다.
[[nodiscard]] float headroom_reference(const negaflow::core::Rgba32F pixel) noexcept {
    const float y = rec709_luma(pixel);
    if (y <= 0.0F || y >= 1.0F) {
        return 0.0F;
    }
    float limit = 1.0e9F;
    for (const float channel : {pixel.red, pixel.green, pixel.blue}) {
        const float chroma = channel - y;
        if (chroma > 1.0e-5F) {
            limit = std::min(limit, (1.0F - y) / chroma);
        } else if (chroma < -1.0e-5F) {
            limit = std::min(limit, -y / chroma);
        }
    }
    return limit;
}

[[nodiscard]] bool apply_to(
    std::vector<negaflow::core::Rgba32F>& pixels,
    const negaflow::imaging::ColorModelParameters& parameters) {
    const negaflow::core::ConstImageView input{
        pixels.data(), pixels.size(), static_cast<std::uint32_t>(pixels.size()), 1U,
        pixels.size()};
    const negaflow::core::ImageView output{
        pixels.data(), pixels.size(), static_cast<std::uint32_t>(pixels.size()), 1U,
        pixels.size()};
    return negaflow::imaging::apply_color_model(input, output, parameters) ==
           negaflow::core::KernelStatus::ok;
}

void test_bounded_chroma_scale_contract() {
    constexpr float tolerance = 2.0e-5F;
    const std::vector<negaflow::core::Rgba32F> grid = make_gamut_grid();

    // 키우는 슬라이더가 [0,1] 안의 색을 범위 밖으로 밀지 않고 휘도는 그대로입니다.
    for (const auto& [saturation, color_depth] :
         {std::pair{0.3F, 0.0F}, std::pair{1.0F, 0.0F}, std::pair{0.0F, 1.0F},
          std::pair{1.0F, 1.0F}}) {
        std::vector<negaflow::core::Rgba32F> pixels = grid;
        negaflow::imaging::ColorModelParameters parameters{};
        parameters.saturation = saturation;
        parameters.color_depth = color_depth;
        expect(apply_to(pixels, parameters), "boosting chroma controls succeed");
        std::size_t outside = 0U;
        std::size_t luma_changed = 0U;
        for (std::size_t index = 0U; index < grid.size(); ++index) {
            const auto& out = pixels[index];
            if (out.red < -tolerance || out.red > 1.0F + tolerance || out.green < -tolerance ||
                out.green > 1.0F + tolerance || out.blue < -tolerance ||
                out.blue > 1.0F + tolerance) {
                ++outside;
            }
            if (std::abs(rec709_luma(out) - rec709_luma(grid[index])) > tolerance) {
                ++luma_changed;
            }
        }
        expect(outside == 0U, "boosting chroma never leaves [0,1] for in-gamut colours");
        expect(luma_changed == 0U, "boosting chroma keeps luminance");
    }

    // knee 안쪽에서는 이전 선형 법칙 그대로입니다.
    for (const float saturation : {0.1F, 0.3F, 1.0F}) {
        const float factor = 1.0F + (saturation * 0.6F);
        std::vector<negaflow::core::Rgba32F> pixels = grid;
        negaflow::imaging::ColorModelParameters parameters{};
        parameters.saturation = saturation;
        expect(apply_to(pixels, parameters), "saturation succeeds");
        std::size_t checked = 0U;
        std::size_t wrong = 0U;
        for (std::size_t index = 0U; index < grid.size(); ++index) {
            const float limit = std::max(headroom_reference(grid[index]), 1.0F);
            const float knee =
                1.0F + (negaflow::imaging::bounded_chroma_knee_fraction * (limit - 1.0F));
            if (factor > knee) {
                continue;
            }
            const float y = rec709_luma(grid[index]);
            ++checked;
            if (std::abs(pixels[index].red - (y + ((grid[index].red - y) * factor))) > tolerance ||
                std::abs(pixels[index].green - (y + ((grid[index].green - y) * factor))) > tolerance ||
                std::abs(pixels[index].blue - (y + ((grid[index].blue - y) * factor))) > tolerance) {
                ++wrong;
            }
        }
        expect(checked > 20U, "enough colours fall inside the linear range");
        expect(wrong == 0U, "saturation inside the knee follows the linear law");
    }

    // 줄이는 쪽은 선형 법칙입니다.
    for (const float saturation : {-0.5F, -1.0F}) {
        const float factor = 1.0F + (saturation * 0.6F);
        std::vector<negaflow::core::Rgba32F> pixels = grid;
        negaflow::imaging::ColorModelParameters parameters{};
        parameters.saturation = saturation;
        expect(apply_to(pixels, parameters), "desaturation succeeds");
        std::size_t wrong = 0U;
        for (std::size_t index = 0U; index < grid.size(); ++index) {
            const float y = rec709_luma(grid[index]);
            if (std::abs(pixels[index].red - (y + ((grid[index].red - y) * factor))) > tolerance ||
                std::abs(pixels[index].green - (y + ((grid[index].green - y) * factor))) > tolerance ||
                std::abs(pixels[index].blue - (y + ((grid[index].blue - y) * factor))) > tolerance) {
                ++wrong;
            }
        }
        expect(wrong == 0U, "desaturation follows the linear law");
    }

    // 슬라이더를 올릴수록 chroma 는 줄지 않습니다(접힌 뒤에는 평평해질 뿐 뒤집히지 않습니다).
    std::vector<float> previous(grid.size());
    for (std::size_t index = 0U; index < grid.size(); ++index) {
        previous[index] = chroma_norm(grid[index]);
    }
    std::size_t decreased = 0U;
    for (int step = 1; step <= 10; ++step) {
        std::vector<negaflow::core::Rgba32F> pixels = grid;
        negaflow::imaging::ColorModelParameters parameters{};
        parameters.saturation = static_cast<float>(step) * 0.1F;
        expect(apply_to(pixels, parameters), "monotonic sweep succeeds");
        for (std::size_t index = 0U; index < grid.size(); ++index) {
            const float current = chroma_norm(pixels[index]);
            if (current < previous[index] - tolerance) {
                ++decreased;
            }
            previous[index] = current;
        }
    }
    expect(decreased == 0U, "chroma never decreases while raising saturation");

    // 이미 범위 밖인 화소는 더 키우지 않습니다.
    std::vector<negaflow::core::Rgba32F> outside_range{
        {1.2F, 0.3F, 0.1F, 1.0F}, {-0.1F, 0.5F, 0.4F, 1.0F}, {1.5F, 1.4F, 0.2F, 1.0F}};
    const std::vector<negaflow::core::Rgba32F> outside_source = outside_range;
    negaflow::imaging::ColorModelParameters boost{};
    boost.saturation = 1.0F;
    expect(apply_to(outside_range, boost), "out-of-range input succeeds");
    for (std::size_t index = 0U; index < outside_range.size(); ++index) {
        expect(std::abs(chroma_norm(outside_range[index]) - chroma_norm(outside_source[index])) < 1.0e-4F,
               "colours already outside [0,1] are not amplified");
        expect(std::abs(rec709_luma(outside_range[index]) - rec709_luma(outside_source[index])) < 1.0e-4F,
               "out-of-range colours keep their luminance");
    }
}

void test_white_balance_law() {
    using negaflow::imaging::white_balance_gains;
    for (const float warmth : {-1.0F, -0.5F, 0.3F, 1.0F}) {
        const auto gains = white_balance_gains(warmth, 0.0F);
        const double expected = (1.0 + (0.18 * warmth)) / (1.0 - (0.18 * warmth));
        expect(std::abs((gains.red / gains.blue) - expected) < 1.0e-5,
               "white balance keeps the old R/B ratio inside +-1");
    }
    const auto at_edge = white_balance_gains(1.0F, 0.0F);
    const auto just_beyond = white_balance_gains(1.001F, 0.0F);
    expect(std::abs(std::log2(just_beyond.red / just_beyond.blue) -
                    std::log2(at_edge.red / at_edge.blue)) < 1.0e-3,
           "the log extension is continuous at the edge");
    const auto widest = white_balance_gains(4.0F, 0.0F);
    expect(std::abs(std::log2(widest.red / widest.blue) - 2.136) < 0.01,
           "warmth 4 spans about 2.14 stops of red/blue");
    for (const auto& gains : {white_balance_gains(4.0F, -4.0F), white_balance_gains(-2.5F, 1.5F)}) {
        const double luminance = (0.2126 * gains.red) + (0.7152 * gains.green) + (0.0722 * gains.blue);
        expect(std::abs(luminance - 1.0) < 1.0e-6, "white balance leaves neutral luminance unchanged");
    }
    expect(!white_balance_gains(0.0005F, -0.0005F).active,
           "white balance below the threshold is a no-op");
}

}  // namespace

int main(const int argc, char** argv) {
    test_identity_and_fixed_matrix_controls();
    test_chroma_controls_and_validation();
    test_bounded_chroma_scale_contract();
    test_white_balance_law();
    expect(argc == 1 || argc == 2, "an optional external golden directory is accepted");
    if (argc == 2) {
        test_civibrance_goldens(argv[1]);
    }
    if (failures == 0) {
        std::cout << "ColorModel tests passed\n";
    }
    return failures == 0 ? 0 : 1;
}
