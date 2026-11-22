#include "negaflow/color/gamut_check.h"
#include "negaflow/color/output_color_space.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
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

/// sRGB 프로파일의 원색을 비대칭으로 섞은 공간입니다. 빨강 원색은 70% 로 줄이고 그 몫(15%씩)을
/// 초록·파랑 원색에 더해 흰색(원색의 합)은 그대로 둡니다. 장치값은 d0 = c0/0.7,
/// d1 = c1 − 0.15·d0, d2 = c2 − 0.15·d0 이라, 진한 빨강은 밖이고 진한 파랑은 안입니다.
/// R 과 B 를 바꿔 읽으면 결과가 거꾸로 나오므로 ICM 에 넘기는 채널 순서를 가려냅니다.
std::vector<std::uint8_t> red_weighted_profile() {
    std::vector<std::uint8_t> profile =
        negaflow::color::build_icc_profile(negaflow::color::OutputColorSpace::srgb);
    const auto read32 = [&](const std::size_t at) {
        return static_cast<std::int32_t>(
            (static_cast<std::uint32_t>(profile[at]) << 24U) |
            (static_cast<std::uint32_t>(profile[at + 1U]) << 16U) |
            (static_cast<std::uint32_t>(profile[at + 2U]) << 8U) | profile[at + 3U]);
    };
    const auto write32 = [&](const std::size_t at, const std::int32_t value) {
        const auto bits = static_cast<std::uint32_t>(value);
        for (std::size_t byte = 0U; byte < 4U; ++byte) {
            profile[at + byte] = static_cast<std::uint8_t>(bits >> (24U - (byte * 8U)));
        }
    };
    const auto tag = [&](const char* const signature) -> std::size_t {
        const auto count = static_cast<std::uint32_t>(read32(128U));
        for (std::uint32_t index = 0U; index < count; ++index) {
            const std::size_t entry = 132U + (static_cast<std::size_t>(index) * 12U);
            if (std::memcmp(profile.data() + entry, signature, 4U) == 0) {
                return static_cast<std::size_t>(read32(entry + 4U)) + 8U;
            }
        }
        return 0U;
    };
    const std::size_t red = tag("rXYZ"), green = tag("gXYZ"), blue = tag("bXYZ");
    for (std::size_t component = 0U; component < 3U; ++component) {
        const std::size_t offset = component * 4U;
        const std::int32_t r = read32(red + offset);
        const std::int32_t share = (r * 15) / 100;
        write32(red + offset, r - (2 * share));
        write32(green + offset, read32(green + offset) + share);
        write32(blue + offset, read32(blue + offset) + share);
    }
    return profile;
}

// ICM 의 8비트 형식 이름은 메모리 순서와 거꾸로 붙어 있습니다(`BM_RGBTRIPLETS` = B,G,R).
// 앞 판은 BGR 사본을 `BM_BGRTRIPLETS` 로 넘겨 빨강을 파랑으로 다뤘습니다. 판정
// (`CheckBitmapBits`)과 프루프(`TranslateBitmapBits`)가 같은 형식 상수를 쓰므로 순서는
// 프루프로 잽니다. ICM 의 판정 표는 이런 변형 프로파일에서 안쪽 파랑도 밖으로 보는 근사라
// (2026-11-22 실측) 판정 결과로는 순서를 가릴 수 없습니다.
void test_channel_order_reaches_icm() {
    const std::vector<std::uint8_t> profile = red_weighted_profile();
    // 경계에서 떨어진 진한 빨강(d0 = 1.24)과 진한 파랑(가장 가까운 장치값 0.06)입니다.
    // 빨강만 눌리고(수식상 240 → 218) 파랑은 그대로입니다.
    std::vector<std::uint8_t> bgra{60U, 60U, 240U, 255U, 220U, 80U, 80U, 255U};
    expect(negaflow::color::soft_proof_convert_bgra_icc(
               bgra.data(), 2U, 1U, 8U, profile.data(), static_cast<std::uint32_t>(profile.size())),
           "red-weighted soft proof runs");
    std::printf("  red-weighted proof: red=%u blue=%u\n", bgra[2], bgra[4]);
    expect(bgra[2] < 232U && bgra[4] > 214U && bgra[4] < 226U,
           "the proof presses the red and keeps the blue");
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

    // ICC TRC를 디코딩 방향으로 바로잡은 뒤 경계색의 ICM 판정도 달라졌습니다.
    // 색역 포함 관계는 경계에서 떨어진 색으로 검사하고, 위 경계색은 API 성공을 검사합니다.
    auto interior = pixels;
    put(interior, 3U, 240U, 240U, 240U);
    put(interior, 6U, 16U, 16U, 16U);
    put(interior, 9U, 64U, 64U, 192U);
    for (const OutputColorSpace wider :
         {OutputColorSpace::display_p3, OutputColorSpace::adobe_rgb}) {
        const auto result = negaflow::color::check_gamut_bgr8(
            interior.data(), width, height, width * 3U, wider);
        expect(result.status == GamutCheckStatus::ok, "checking against a wider space succeeds");
        expect(
            result.out_of_gamut_count == 0U,
            "interior sRGB colours are inside a space that contains sRGB");
    }

    // 빈 입력은 판정하지 않습니다. 못 한 것과 "전부 안에 있다" 는 다릅니다.
    const auto empty = negaflow::color::check_gamut_bgr8(
        nullptr, 0U, 0U, 0U, OutputColorSpace::srgb);
    expect(empty.status == GamutCheckStatus::invalid_input, "an empty request is refused");
    expect(empty.out_of_gamut.empty(), "a refused request carries no flags");

    test_channel_order_reaches_icm();

    if (failures != 0) {
        std::printf("%d gamut check test(s) failed\n", failures);
        return 1;
    }
    std::printf("gamut check tests passed\n");
    return 0;
}
