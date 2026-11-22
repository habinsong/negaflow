// 내보내기가 인화소 ICC 로 나갈 때 지나는 ICM 변환입니다.
//
// 1. 행 간격이 4바이트 배수가 아닌(너비 홀수) 16비트 화소도 행이 밀리지 않아야 합니다.
//    `gamut_check_abi.cpp` 는 8비트 BGR 에서 정렬되지 않은 행이 밀리는 것을 실제로 겪었습니다.
// 2. P3 로 인코딩한 화소는 P3 프로파일을 원본으로 옮겨야 합니다. sRGB 로 읽으면 채도가
//    틀어집니다. ICM 의 `BM_16b_RGB` 는 메모리를 B,G,R 로 읽으므로 이 검사와 3 은 채널 순서도
//    가려냅니다(R/B 가 바뀌면 주황이 파랑 쪽으로, 빨강이 P3 파랑으로 갑니다).
// 3. JPEG 경로(`translate_to_output_icc`)가 화소를 실제로 프로파일 공간으로 옮겨야 합니다.

#include "icm_rgb16_parallel.h"
#include "scanner_to_working_detail.h"
#include "icm_rgb16_transform.h"
#include "wic_srgb16_support.h"

#include "negaflow/color/output_color_space.h"
#include "negaflow/color/srgb_transfer.h"

#include <cmath>
#include <cstring>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

std::uint16_t encode16(const float linear, const negaflow::color::OutputColorSpace space) {
    const float encoded = negaflow::color::encode_output_component(linear, space);
    return static_cast<std::uint16_t>(std::lround(encoded * 65535.0F));
}

// 행마다 크게 다른 값을 넣어 행이 밀리면 바로 드러나게 합니다.
std::vector<std::uint16_t> rows_pattern(const std::uint32_t width, const std::uint32_t height) {
    std::vector<std::uint16_t> samples(static_cast<std::size_t>(width) * height * 3U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t at = (static_cast<std::size_t>(y) * width + x) * 3U;
            const std::uint16_t base = static_cast<std::uint16_t>(8000U + (y % 6U) * 9000U);
            samples[at] = static_cast<std::uint16_t>(base + x * 300U);
            samples[at + 1U] = static_cast<std::uint16_t>(base + x * 150U);
            samples[at + 2U] = static_cast<std::uint16_t>(base + x * 75U);
        }
    }
    return samples;
}

bool close_to(const std::vector<std::uint16_t>& actual, const std::vector<std::uint16_t>& expected) {
    if (actual.size() != expected.size()) {
        return false;
    }
    for (std::size_t index = 0U; index < actual.size(); ++index) {
        if (std::abs(static_cast<int>(actual[index]) - static_cast<int>(expected[index])) > 700) {
            std::cerr << "  sample " << index << " = " << actual[index] << " expected "
                      << expected[index] << '\n';
            return false;
        }
    }
    return true;
}

void test_odd_width_rows_stay_in_place() {
    const std::vector<std::uint8_t> srgb =
        negaflow::color::build_icc_profile(negaflow::color::OutputColorSpace::srgb);
    constexpr std::uint32_t width = 5U;  // 30 바이트 행 - 4 의 배수가 아닙니다.
    constexpr std::uint32_t height = 3U;
    const std::vector<std::uint16_t> source = rows_pattern(width, height);
    std::vector<std::uint16_t> destination(source.size(), 0U);
    negaflow::imaging::detail::IcmRgb16Transform transform{};
    std::uint32_t code = 0U;
    expect(
        transform.initialize_to_profile(srgb, code) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "sRGB to a built sRGB profile links");
    expect(
        transform.translate(
            source.data(), width, height, width * 6U, destination.data(), width * 6U, code) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "odd-width 16-bit rows translate");
    expect(close_to(destination, source), "odd-width 16-bit rows are not shifted");

    constexpr std::uint32_t tall = 61U;
    constexpr std::uint32_t narrow = 7U;
    const std::vector<std::uint16_t> many = rows_pattern(narrow, tall);
    std::vector<std::uint16_t> moved(many.size(), 0U);
    negaflow::imaging::detail::ParallelIcmRgb16Transform parallel{};
    expect(
        parallel.initialize_to_profile(srgb, code) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "parallel transform links to a profile");
    expect(
        parallel.translate(
            many.data(), narrow, tall, narrow * 6U, moved.data(), narrow * 6U, code) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "parallel odd-width translate succeeds");
    expect(close_to(moved, many), "parallel odd-width rows are not shifted");
}

void test_p3_encoded_source_is_read_as_p3() {
    using negaflow::color::OutputColorSpace;
    const std::vector<std::uint8_t> srgb = negaflow::color::build_icc_profile(OutputColorSpace::srgb);
    const std::vector<std::uint8_t> p3 =
        negaflow::color::build_icc_profile(OutputColorSpace::display_p3);
    // sRGB 의 진한 주황(선형 0.5, 0.15, 0.08)을 P3 로 인코딩한 값입니다. ICM 은 33칸 LUT 로
    // 보간하므로 sRGB 색역 꼭짓점(순수 빨강)에서는 칸 안에 색역 밖 마디가 섞여 수백 단계가
    // 틀립니다. 경계에서 떨어진 색이어야 P3 해석 자체를 잴 수 있습니다.
    const negaflow::color::ColorMatrix to_p3 = negaflow::color::linear_srgb_to(OutputColorSpace::display_p3);
    const float linear[3]{0.5F, 0.15F, 0.08F};
    const auto p3_component = [&](const std::size_t row) {
        return (to_p3[row * 3U] * linear[0]) + (to_p3[(row * 3U) + 1U] * linear[1]) +
               (to_p3[(row * 3U) + 2U] * linear[2]);
    };
    const std::vector<std::uint16_t> source{
        encode16(p3_component(0U), OutputColorSpace::display_p3),
        encode16(p3_component(1U), OutputColorSpace::display_p3),
        encode16(p3_component(2U), OutputColorSpace::display_p3),
        0U, 0U, 0U,
    };
    const std::uint16_t expected[3]{
        encode16(linear[0], OutputColorSpace::srgb),
        encode16(linear[1], OutputColorSpace::srgb),
        encode16(linear[2], OutputColorSpace::srgb),
    };
    std::vector<std::uint16_t> destination(source.size(), 0U);
    negaflow::imaging::detail::IcmRgb16Transform transform{};
    std::uint32_t code = 0U;
    expect(
        transform.initialize_to_profile(srgb, code, p3) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "P3 source to sRGB destination links");
    expect(
        transform.translate(source.data(), 2U, 1U, 12U, destination.data(), 12U, code) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "P3 source translates");
    bool matches = true;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        matches = matches &&
            std::abs(static_cast<int>(destination[channel]) - static_cast<int>(expected[channel])) < 400;
    }
    expect(matches, "P3-encoded orange comes back as the same sRGB orange");
    if (!matches) {
        std::cerr << "  P3 source " << source[0] << ',' << source[1] << ',' << source[2]
                  << " -> sRGB " << destination[0] << ',' << destination[1] << ','
                  << destination[2] << " expected " << expected[0] << ',' << expected[1] << ','
                  << expected[2] << '\n';
    }
}

void test_jpeg_path_moves_pixels_into_the_profile() {
    using negaflow::color::OutputColorSpace;
    const std::vector<std::uint8_t> p3 = negaflow::color::build_icc_profile(OutputColorSpace::display_p3);
    negaflow::output::Srgb16Image image{};
    image.width = 3U;
    image.height = 1U;
    image.channels = 3U;
    image.bits_per_sample = 16U;
    image.stride_bytes = 18U;
    image.samples = {65535U, 0U, 0U, 0U, 65535U, 0U, 32768U, 32768U, 32768U};
    negaflow::output::WorkingToSrgb16Limits limits{};
    limits.output_icc_profile = p3;
    std::uint32_t code = 0U;
    expect(
        negaflow::output::detail::translate_to_output_icc(image, limits, code),
        "JPEG pixels translate into the output profile");
    const negaflow::color::ColorMatrix to_p3 = negaflow::color::linear_srgb_to(OutputColorSpace::display_p3);
    const std::uint16_t red = encode16(to_p3[0], OutputColorSpace::display_p3);
    expect(
        std::abs(static_cast<int>(image.samples[0]) - static_cast<int>(red)) < 700 &&
            image.samples[1] > 5000U,
        "sRGB red becomes P3-encoded red instead of keeping sRGB codes");
    expect(
        std::abs(static_cast<int>(image.samples[6]) - 32768) < 700 &&
            std::abs(static_cast<int>(image.samples[7]) - 32768) < 700,
        "neutral grey stays neutral");

    negaflow::output::WorkingToSrgb16Limits none{};
    const std::vector<std::uint16_t> before = image.samples;
    expect(
        negaflow::output::detail::translate_to_output_icc(image, none, code) &&
            image.samples == before,
        "no output profile leaves pixels alone");
}

void put_u32(std::vector<std::uint8_t>& bytes, const std::size_t at, const std::uint32_t value) {
    bytes[at] = static_cast<std::uint8_t>(value >> 24U);
    bytes[at + 1U] = static_cast<std::uint8_t>(value >> 16U);
    bytes[at + 2U] = static_cast<std::uint8_t>(value >> 8U);
    bytes[at + 3U] = static_cast<std::uint8_t>(value);
}

// 흑백 스캔이 흔히 다는 "Gray Gamma 2.2" 와 같은 꼴입니다: GRAY 데이터 공간, wtpt, kTRC(감마).
std::vector<std::uint8_t> gray_gamma_profile(const double gamma) {
    std::vector<std::uint8_t> bytes(132U + 2U * 12U + 20U + 16U, 0U);
    put_u32(bytes, 0U, static_cast<std::uint32_t>(bytes.size()));
    put_u32(bytes, 8U, 0x02400000U);
    std::memcpy(bytes.data() + 12U, "mntr", 4U);
    std::memcpy(bytes.data() + 16U, "GRAY", 4U);
    std::memcpy(bytes.data() + 20U, "XYZ ", 4U);
    std::memcpy(bytes.data() + 36U, "acsp", 4U);
    put_u32(bytes, 68U, 0x0000F6D6U);
    put_u32(bytes, 72U, 0x00010000U);
    put_u32(bytes, 76U, 0x0000D32DU);
    put_u32(bytes, 128U, 2U);
    const std::size_t wtpt = 132U + 24U;
    const std::size_t trc = wtpt + 20U;
    std::memcpy(bytes.data() + 132U, "wtpt", 4U);
    put_u32(bytes, 136U, static_cast<std::uint32_t>(wtpt));
    put_u32(bytes, 140U, 20U);
    std::memcpy(bytes.data() + 144U, "kTRC", 4U);
    put_u32(bytes, 148U, static_cast<std::uint32_t>(trc));
    put_u32(bytes, 152U, 14U);
    std::memcpy(bytes.data() + wtpt, "XYZ ", 4U);
    put_u32(bytes, wtpt + 8U, 0x0000F6D6U);
    put_u32(bytes, wtpt + 12U, 0x00010000U);
    put_u32(bytes, wtpt + 16U, 0x0000D32DU);
    std::memcpy(bytes.data() + trc, "curv", 4U);
    put_u32(bytes, trc + 8U, 1U);
    const auto fixed = static_cast<std::uint16_t>(std::lround(gamma * 256.0));
    bytes[trc + 12U] = static_cast<std::uint8_t>(fixed >> 8U);
    bytes[trc + 13U] = static_cast<std::uint8_t>(fixed);
    return bytes;
}

// kTRC 를 'para' 함수 1(Y = (a·X + b)^g, X ≥ -b/a)로 바꾼 Gray 프로파일입니다.
std::vector<std::uint8_t> gray_para_profile(const double g, const double a, const double b) {
    std::vector<std::uint8_t> bytes = gray_gamma_profile(2.2);
    const std::size_t trc = 132U + 24U + 20U;
    bytes.resize(trc + 24U, 0U);
    put_u32(bytes, 0U, static_cast<std::uint32_t>(bytes.size()));
    put_u32(bytes, 152U, 24U);
    std::memcpy(bytes.data() + trc, "para", 4U);
    put_u32(bytes, trc + 4U, 0U);
    put_u32(bytes, trc + 8U, 0x00010000U);  // 함수 1, 예약 0
    const auto s15 = [](const double value) {
        return static_cast<std::uint32_t>(static_cast<std::int32_t>(std::lround(value * 65536.0)));
    };
    put_u32(bytes, trc + 12U, s15(g));
    put_u32(bytes, trc + 16U, s15(a));
    put_u32(bytes, trc + 20U, s15(b));
    return bytes;
}

// 'para' 의 a 가 0 이면 경계 -b/a 가 0 으로 나누기입니다. 곡선이 아니므로 변환을 만들지
// 않습니다. 정상 값(a = 1, b = 0)은 같은 경로로 감마 곡선이 됩니다.
void test_gray_para_with_zero_slope_is_refused() {
    expect(
        negaflow::color::rgb_profile_for_gray_profile(gray_para_profile(2.2, 0.0, 0.0)).empty(),
        "a gray para curve with a = 0 is refused instead of dividing by zero");
    expect(
        !negaflow::color::rgb_profile_for_gray_profile(gray_para_profile(2.2, 1.0, 0.0)).empty(),
        "a well-formed gray para curve converts");
}

// Gray ICC 흑백 스캔은 같은 회색 축의 RGB 프로파일로 옮겨 읽습니다. 앞 판은 데이터 공간이 RGB
// 가 아니면 열지 못했습니다. 회색 0.5(감마 2.2)는 선형 0.5^2.2 = 0.2176 이어야 합니다.
void test_gray_profile_reads_as_its_gray_axis() {
    const std::vector<std::uint8_t> gray = gray_gamma_profile(2.2);
    const std::vector<std::uint8_t> rgb = negaflow::color::rgb_profile_for_gray_profile(gray);
    expect(!rgb.empty(), "a gray gamma profile becomes an RGB matrix/TRC profile");
    negaflow::imaging::detail::IcmRgb16Transform transform{};
    std::uint32_t code = 0U;
    const std::span<const std::uint8_t> intermediate =
        negaflow::imaging::detail::working_intermediate_profile();
    expect(
        transform.initialize(rgb, code, intermediate) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "gray-as-RGB links to the working intermediate");
    const std::vector<std::uint16_t> source{32768U, 32768U, 32768U, 13107U, 13107U, 13107U};
    std::vector<std::uint16_t> destination(source.size(), 0U);
    expect(
        transform.translate(source.data(), 2U, 1U, 12U, destination.data(), 12U, code) ==
            negaflow::imaging::ScannerToWorkingStatus::ok,
        "gray-as-RGB translates");
    const negaflow::imaging::detail::IntermediateToWorking decode{};
    const negaflow::core::Rgba32F mid = decode(destination[0], destination[1], destination[2], 1.0F);
    const float expected = std::pow(32768.0F / 65535.0F, 2.2F);
    expect(
        std::abs(mid.red - expected) < 0.004F && std::abs(mid.green - expected) < 0.004F &&
            std::abs(mid.blue - expected) < 0.004F,
        "gray 0.5 at gamma 2.2 decodes to linear 0.2176 on all three channels");
    expect(
        negaflow::color::rgb_profile_for_gray_profile(
            negaflow::color::build_icc_profile(negaflow::color::OutputColorSpace::srgb))
            .empty(),
        "an RGB profile is not treated as gray");
}

}  // namespace

int main() {
    test_odd_width_rows_stay_in_place();
    test_p3_encoded_source_is_read_as_p3();
    test_jpeg_path_moves_pixels_into_the_profile();
    test_gray_profile_reads_as_its_gray_axis();
    test_gray_para_with_zero_slope_is_refused();
    if (failures != 0) {
        std::cerr << failures << " output ICC transform test(s) failed\n";
        return EXIT_FAILURE;
    }
    std::cout << "output ICC transform tests passed\n";
    return EXIT_SUCCESS;
}
