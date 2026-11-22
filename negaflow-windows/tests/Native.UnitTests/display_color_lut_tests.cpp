// 화면 색관리 표(`DisplayColorLut`)입니다.
//
// 1. sRGB 모니터(또는 Advanced Color 가 켜져 sRGB 를 돌려받은 경우)는 항등이어야 합니다 —
//    부르는 쪽은 그때 화소를 건드리지 않습니다.
// 2. Display P3 모니터에서 sRGB 빨강은 P3 코드 (234, 51, 35) 로 가야 합니다. 이 값은 엔진과
//    따로 계산했습니다: sRGB 빨강 = P3 선형 (0.8225, 0.0332, 0.0171).
// 3. 알파는 그대로이고 무채색은 무채색으로 남습니다.

#include "negaflow/imaging/display_color_lut.h"

#include "negaflow/color/output_color_space.h"

#include <cmath>
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

bool within(const int actual, const int expected, const int tolerance) {
    return std::abs(actual - expected) <= tolerance;
}

void test_srgb_monitor_is_identity() {
    const std::vector<std::uint8_t> profile =
        negaflow::color::build_icc_profile(negaflow::color::OutputColorSpace::srgb);
    negaflow::imaging::DisplayColorLut lut{};
    std::uint32_t code = 0U;
    expect(lut.build(profile, code), "an sRGB monitor profile builds");
    expect(lut.identity(), "an sRGB monitor needs no conversion");
    if (!lut.identity()) {
        // 어디서 얼마나 벗어나는지 적습니다(8비트 단위).
        float worst = 0.0F;
        int at[3]{};
        float got[3]{};
        for (int r = 0; r < 33; ++r) {
            for (int g = 0; g < 33; ++g) {
                for (int b = 0; b < 33; ++b) {
                    const float in[3]{r / 32.0F, g / 32.0F, b / 32.0F};
                    float out[3]{};
                    lut.map(in, out);
                    for (int c = 0; c < 3; ++c) {
                        const float shift = std::abs(out[c] - in[c]) * 255.0F;
                        if (shift > worst) {
                            worst = shift;
                            at[0] = r; at[1] = g; at[2] = b;
                            got[0] = out[0] * 255.0F; got[1] = out[1] * 255.0F; got[2] = out[2] * 255.0F;
                        }
                    }
                }
            }
        }
        std::cerr << "  worst shift " << worst << " (8-bit) at grid " << at[0] << ',' << at[1] << ','
                  << at[2] << " -> " << got[0] << ',' << got[1] << ',' << got[2] << '\n';
    }
}

void test_p3_monitor_moves_srgb_into_p3() {
    const std::vector<std::uint8_t> profile =
        negaflow::color::build_icc_profile(negaflow::color::OutputColorSpace::display_p3);
    negaflow::imaging::DisplayColorLut lut{};
    std::uint32_t code = 0U;
    expect(lut.build(profile, code), "a P3 monitor profile builds");
    expect(!lut.identity(), "a P3 monitor is not the identity");

    // 홀수 너비(3)에 행 끝 여백을 두어 행 간격도 시험합니다. BGRA 입니다.
    constexpr std::uint32_t width = 3U;
    constexpr std::uint32_t height = 2U;
    constexpr std::size_t stride = 16U;
    std::vector<std::uint8_t> source(stride * height, 0xABU);
    const std::uint8_t pixels[3][4]{
        {0U, 0U, 255U, 200U},      // 빨강, 알파 200
        {128U, 128U, 128U, 255U},  // 중간 회색
        {255U, 255U, 255U, 17U},   // 흰색, 알파 17
    };
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            for (std::size_t c = 0U; c < 4U; ++c) {
                source[(y * stride) + (x * 4U) + c] = pixels[x][c];
            }
        }
    }
    std::vector<std::uint8_t> destination(source.size(), 0x5AU);
    lut.apply_bgra(source.data(), stride, destination.data(), stride, width, height);

    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint8_t* const row = destination.data() + (y * stride);
        expect(within(row[2], 234, 2) && within(row[1], 51, 2) && within(row[0], 35, 2),
               "sRGB red becomes P3-encoded red on a P3 monitor");
        expect(row[3] == 200U, "alpha is copied unchanged");
        expect(row[4] == row[5] && row[5] == row[6] && within(row[4], 128, 1),
               "a neutral grey stays neutral");
        expect(row[8] == 255U && row[9] == 255U && row[10] == 255U && row[11] == 17U,
               "white stays white and keeps its alpha");
        expect(row[12] == 0x5AU, "the row padding is not written");
    }
    std::cout << "  P3 monitor red -> " << int{destination[2]} << ',' << int{destination[1]}
              << ',' << int{destination[0]} << '\n';

    // 같은 버퍼에서도 같은 값입니다.
    std::vector<std::uint8_t> in_place = source;
    lut.apply_bgra(in_place.data(), stride, in_place.data(), stride, width, height);
    bool same = true;
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::size_t c = 0U; c < width * 4U; ++c) {
            same = same && in_place[(y * stride) + c] == destination[(y * stride) + c];
        }
    }
    expect(same, "in-place conversion matches the separate-buffer result");
}

void test_invalid_profile_is_refused() {
    std::vector<std::uint8_t> junk(256U, 0x11U);
    negaflow::imaging::DisplayColorLut lut{};
    std::uint32_t code = 0U;
    expect(!lut.build(junk, code) && !lut.ready(), "bytes that are not a profile are refused");
    std::vector<std::uint8_t> short_bytes(64U, 0U);
    expect(!lut.build(short_bytes, code), "a buffer shorter than an ICC header is refused");
}

}  // namespace

int main() {
    test_srgb_monitor_is_identity();
    test_p3_monitor_moves_srgb_into_p3();
    test_invalid_profile_is_refused();
    if (failures != 0) {
        std::cerr << failures << " display colour LUT test(s) failed\n";
        return EXIT_FAILURE;
    }
    std::cout << "display colour LUT tests passed\n";
    return EXIT_SUCCESS;
}
