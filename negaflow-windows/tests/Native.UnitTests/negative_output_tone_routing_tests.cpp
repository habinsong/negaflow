// 출력 톤(macOS `NegativeLinearResponse.output`)이 선형 기준 반전을 쓴 타깃에만 붙는지 고정합니다.
//
// MAIN·PRINT·커스텀은 v4 인화 응답이 이미 어깨와 토우를 가집니다. 2026-10-27 롤백으로 반전은
// v4 로 돌아갔는데 톤 단계의 출력 톤 조건만 남아 어깨가 두 번 걸렸습니다. 짙은 명부가 선형 0.84
// 에서 막히고 검정이 떴습니다(macOS 흑백 골든 대비 중앙값 −2110/65535). EXPIRED 는 거꾸로
// 선형 반전을 하면서 출력 톤이 빠져 명부가 1 을 넘었습니다. 골든은 CI 에 없어서 이 시험이
// 합성 네거티브로 같은 경계를 지킵니다.

#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/pipeline/develop_export.h"
#include "synthetic_wic_tiff.h"

#include <Windows.h>

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <system_error>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint32_t band_width = 32U;
constexpr std::uint32_t width = band_width * 4U;
constexpr std::uint32_t height = 64U;
constexpr double base_transmission = 0.5;
// 베이스 위 밀도: 베이스, 아주 짙은 명부, 선형 반전이 정확히 1.0 이 되는 밀도, 미드.
constexpr double band_density[4] = {0.0, 3.5, 1.062, 0.5};

[[nodiscard]] std::vector<std::uint16_t> make_samples() {
    std::vector<std::uint16_t> samples{};
    samples.reserve(static_cast<std::size_t>(width) * height * 3U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const double transmission =
                base_transmission * std::pow(10.0, -band_density[x / band_width]);
            const auto value = static_cast<std::uint16_t>(std::lround(transmission * 65535.0));
            samples.insert(samples.end(), {value, value, value});
        }
    }
    return samples;
}

// 띠 가운데 열들의 G 평균(0..1, 출력 sRGB 인코딩).
[[nodiscard]] double band_mean(const std::vector<std::uint16_t>& samples, const std::uint32_t band) {
    double sum = 0.0;
    std::size_t count = 0U;
    for (std::uint32_t y = height / 4U; y < (height * 3U) / 4U; ++y) {
        for (std::uint32_t x = band * band_width + 8U; x < band * band_width + band_width - 8U; ++x) {
            sum += samples[(static_cast<std::size_t>(y) * width + x) * 3U + 1U];
            ++count;
        }
    }
    return sum / static_cast<double>(count) / 65535.0;
}

[[nodiscard]] std::vector<std::uint16_t> develop(
    const std::filesystem::path& source,
    const std::filesystem::path& destination,
    const negaflow::pipeline::DevelopTarget target) {
    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.destination = destination;
    request.format = negaflow::pipeline::DevelopExportFormat::tiff16;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {
        static_cast<float>(base_transmission),
        static_cast<float>(base_transmission),
        static_cast<float>(base_transmission)};
    request.develop_target = target;
    const auto outcome = negaflow::pipeline::develop_and_export(request);
    expect(outcome.succeeded, "the synthetic negative develops and exports");
    if (!outcome.succeeded) {
        return {};
    }
    const auto decoded = negaflow::imageio::decode_tiff_with_wic(destination);
    const bool decoded_ok =
        decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok &&
        decoded.image.layout == negaflow::imageio::DecodedPixelLayout::rgb16 &&
        decoded.image.width == width && decoded.image.height == height;
    expect(decoded_ok, "the exported TIFF decodes as RGB16 at the source size");
    return decoded_ok ? decoded.image.samples : std::vector<std::uint16_t>{};
}

}  // namespace

int main() {
    const std::filesystem::path directory =
        std::filesystem::temp_directory_path() /
        (L"negaflow-output-tone-routing-" + std::to_wstring(GetCurrentProcessId()));
    std::error_code ignored{};
    std::filesystem::create_directories(directory, ignored);
    const std::filesystem::path source = directory / L"source.tiff";
    {
        const std::vector<std::uint8_t> tiff =
            negaflow::test_fixtures::make_uncompressed_rgb16_tiff(width, height, make_samples());
        std::ofstream out(source, std::ios::binary | std::ios::trunc);
        out.write(reinterpret_cast<const char*>(tiff.data()), static_cast<std::streamsize>(tiff.size()));
        expect(!tiff.empty() && out.good(), "wrote the synthetic negative");
    }

    // MAIN: v4 응답만. 짙은 명부는 천장(선형 0.90) 쪽 0.89 → sRGB 0.951 까지 올라가고, 어깨가 두 번
    // 걸리면 0.82 → 0.915 에서 멈춥니다. 베이스는 v4 토우 0.001 → sRGB 0.013 이고, 출력 톤이
    // 겹치면 0.002 → 0.025 로 뜹니다.
    const auto main = develop(source, directory / L"main.tif", negaflow::pipeline::DevelopTarget::main);
    if (!main.empty()) {
        const double base = band_mean(main, 0U);
        const double dense = band_mean(main, 1U);
        std::cout << "main base=" << base << " dense=" << dense << '\n';
        expect(dense > 0.935, "MAIN highlights reach the v4 shoulder without a second output-tone shoulder");
        expect(base < 0.019, "MAIN film base stays on the v4 toe without the output-tone black lift");
    }

    // EXPIRED: 선형 기준 반전 + 출력 톤. 선형 1.0 이 되는 띠는 어깨에서 0.85 → sRGB 0.925 이고,
    // 출력 톤이 빠지면 1.0 그대로 나옵니다.
    const auto rescue =
        develop(source, directory / L"rescue.tif", negaflow::pipeline::DevelopTarget::rescue);
    if (!rescue.empty()) {
        const double unit = band_mean(rescue, 2U);
        std::cout << "rescue unit=" << unit << '\n';
        expect(unit < 0.95, "EXPIRED folds its linear inversion through the output-tone shoulder");
    }

    std::filesystem::remove_all(directory, ignored);
    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"negative_output_tone_routing\",\"failures\":" << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
