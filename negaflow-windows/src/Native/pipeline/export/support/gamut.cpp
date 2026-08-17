#include "gamut.h"

#include "negaflow/color/gamut_check.h"

#include <new>
#include <vector>

namespace negaflow::pipeline::develop_export_detail {

void mark_out_of_gamut(
    std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const negaflow::color::OutputColorSpace destination) noexcept {
    if (pixels == nullptr || width == 0U || height == 0U) {
        return;
    }
    // ICM 은 BGR 세 바이트를 받으므로 BGRA 에서 알파를 뺀 사본을 만듭니다.
    std::vector<std::uint8_t> bgr;
    try {
        bgr.resize(static_cast<std::size_t>(width) * height * 3U);
    } catch (const std::bad_alloc&) {
        return;
    }
    for (std::size_t index = 0U;
         index < static_cast<std::size_t>(width) * height;
         ++index) {
        bgr[index * 3U] = pixels[index * 4U];
        bgr[(index * 3U) + 1U] = pixels[(index * 4U) + 1U];
        bgr[(index * 3U) + 2U] = pixels[(index * 4U) + 2U];
    }

    const auto judged = negaflow::color::check_gamut_bgr8(
        bgr.data(), width, height, width * 3U, destination);
    if (judged.status != negaflow::color::GamutCheckStatus::ok) {
        return;
    }

    // macOS 의 오버레이는 R=255, A=166 입니다. 같은 합성을 여기서 미리 해 둡니다.
    constexpr float alpha = 166.0F / 255.0F;
    constexpr float keep = 1.0F - alpha;
    for (std::size_t index = 0U; index < judged.out_of_gamut.size(); ++index) {
        if (judged.out_of_gamut[index] == 0U) {
            continue;
        }
        std::uint8_t* const pixel = pixels + (index * 4U);
        pixel[0] = static_cast<std::uint8_t>(static_cast<float>(pixel[0]) * keep);
        pixel[1] = static_cast<std::uint8_t>(static_cast<float>(pixel[1]) * keep);
        pixel[2] = static_cast<std::uint8_t>(
            (static_cast<float>(pixel[2]) * keep) + (255.0F * alpha));
    }
}

}  // namespace negaflow::pipeline::develop_export_detail
