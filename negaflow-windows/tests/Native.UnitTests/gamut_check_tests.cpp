#include "negaflow/color/gamut_check.h"

#include <array>
#include <cstdio>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const what) {
    if (!condition) {
        ++failures;
        std::printf("FAIL: %s\n", what);
    }
}

/// sRGB 로 부호화된 BGR 세 바이트.
void put(std::vector<std::uint8_t>& pixels, const std::size_t at,
         const std::uint8_t b, const std::uint8_t g, const std::uint8_t r) {
    pixels[at] = b;
    pixels[at + 1U] = g;
    pixels[at + 2U] = r;
}

}  // namespace

int main() {
    using negaflow::color::GamutCheckStatus;
    using negaflow::color::OutputColorSpace;

    expect(
        negaflow::color::gamut_check_supported(OutputColorSpace::srgb),
        "ICM can build a gamut-check transform for sRGB");

    // 네 화소: 중간 회색, 흰색, 검정, 가장 진한 빨강.
    constexpr std::uint32_t width = 4U;
    constexpr std::uint32_t height = 1U;
    std::vector<std::uint8_t> pixels(static_cast<std::size_t>(width) * 3U, 0U);
    put(pixels, 0U, 128U, 128U, 128U);
    put(pixels, 3U, 255U, 255U, 255U);
    put(pixels, 6U, 0U, 0U, 0U);
    put(pixels, 9U, 0U, 0U, 255U);

    // sRGB 화소를 sRGB 로 판정하면 색역을 벗어나는 것이 없어야 합니다. 여기서 무언가
    // 표시되면 판정 자체가 틀린 것이고, 넓은 공간 결과도 믿을 수 없습니다.
    const auto same = negaflow::color::check_gamut_bgr8(
        pixels.data(), width, height, width * 3U, OutputColorSpace::srgb);
    expect(same.status == GamutCheckStatus::ok, "checking sRGB against sRGB succeeds");
    expect(
        same.out_of_gamut.size() == static_cast<std::size_t>(width) * height,
        "the result carries one byte per pixel");
    // 어떤 화소가 걸리는지 적어 둡니다. 색역 경계에 정확히 놓인 색은 1 LSB 를 밀어도 ICM 이
    // 바깥으로 볼 수 있습니다 — 그래서 "전부 안에 있다" 를 요구하지 않습니다. 대신 **명백히
    // 안쪽인 색**은 반드시 안에 있어야 합니다. 그것마저 걸리면 판정 자체가 틀린 것입니다.
    std::printf(
        "  sRGB->sRGB flags: gray=%u white=%u black=%u red=%u\n",
        same.out_of_gamut[0],
        same.out_of_gamut[1],
        same.out_of_gamut[2],
        same.out_of_gamut[3]);
    expect(same.out_of_gamut[0] == 0U, "mid grey is inside sRGB");

    // 넓은 공간을 목표로 하면 sRGB 색은 전부 그 안에 들어갑니다 — sRGB 는 둘의 부분집합입니다.
    for (const OutputColorSpace wider :
         {OutputColorSpace::display_p3, OutputColorSpace::adobe_rgb}) {
        const auto result = negaflow::color::check_gamut_bgr8(
            pixels.data(), width, height, width * 3U, wider);
        expect(result.status == GamutCheckStatus::ok, "checking against a wider space succeeds");
        expect(
            result.out_of_gamut_count == 0U,
            "sRGB colours are inside a space that contains sRGB");
    }

    // 빈 입력은 판정하지 않습니다. 못 한 것과 "전부 안에 있다" 는 다릅니다.
    const auto empty = negaflow::color::check_gamut_bgr8(
        nullptr, 0U, 0U, 0U, OutputColorSpace::srgb);
    expect(empty.status == GamutCheckStatus::invalid_input, "an empty request is refused");
    expect(empty.out_of_gamut.empty(), "a refused request carries no flags");

    if (failures != 0) {
        std::printf("%d gamut check test(s) failed\n", failures);
        return 1;
    }
    std::printf("gamut check tests passed\n");
    return 0;
}
