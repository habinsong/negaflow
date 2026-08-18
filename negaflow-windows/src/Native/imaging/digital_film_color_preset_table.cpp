#include "negaflow/imaging/digital_film_color_preset.h"

#include <cstddef>

namespace negaflow::imaging {
namespace {

// 아래 값은 필름별로 측정한 색 표입니다. 화소 처리는 이 파일에 없습니다 - 표가 늘어도
// 적용 코드는 그대로여야 하기 때문입니다.

class PresetBuilder final {
public:
    void shadows(const float hue, const float saturation,
                 const float luminance = 0.0F) noexcept {
        preset_.grading.shadows = {hue, saturation, luminance};
    }
    void midtones(const float hue, const float saturation,
                  const float luminance = 0.0F) noexcept {
        preset_.grading.midtones = {hue, saturation, luminance};
    }
    void highlights(const float hue, const float saturation,
                    const float luminance = 0.0F) noexcept {
        preset_.grading.highlights = {hue, saturation, luminance};
    }
    void band(
        const ColorMixerBand band,
        const float hue = 0.0F,
        const float saturation = 0.0F,
        const float luminance = 0.0F) noexcept {
        const std::size_t index = static_cast<std::size_t>(band);
        preset_.mixer.hue[index] = hue;
        preset_.mixer.saturation[index] = saturation;
        preset_.mixer.luminance[index] = luminance;
    }
    void primaries(
        const float red_hue = 0.0F,
        const float red_saturation = 0.0F,
        const float green_hue = 0.0F,
        const float green_saturation = 0.0F,
        const float blue_hue = 0.0F,
        const float blue_saturation = 0.0F) noexcept {
        preset_.calibration = {
            red_hue, red_saturation, green_hue, green_saturation,
            blue_hue, blue_saturation};
    }
    [[nodiscard]] DigitalFilmColorPreset build() const noexcept {
        return preset_;
    }

private:
    DigitalFilmColorPreset preset_{};
};

[[nodiscard]] DigitalFilmColorPreset make_ektachrome_e100() noexcept {
    PresetBuilder b;
    b.shadows(150.0F, 0.055F); b.midtones(215.0F, 0.030F);
    b.highlights(220.0F, 0.045F);
    b.band(ColorMixerBand::blue, 0.0F, 0.10F);
    b.band(ColorMixerBand::aqua, 0.0F, 0.06F);
    b.band(ColorMixerBand::orange, 0.0F, -0.06F, 0.02F);
    b.band(ColorMixerBand::green, 0.04F, -0.02F);
    b.primaries(0, 0, 0, 0, 0.06F, 0.05F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_provia_100f() noexcept {
    PresetBuilder b;
    b.midtones(35.0F, 0.035F); b.highlights(205.0F, 0.030F);
    b.band(ColorMixerBand::orange, 0, 0.07F, 0.03F);
    b.band(ColorMixerBand::red, 0, 0.05F);
    b.band(ColorMixerBand::green, 0.03F, 0.06F);
    b.band(ColorMixerBand::blue, 0, 0.08F);
    b.primaries(0, 0, 0, 0.04F, 0, 0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_velvia_50() noexcept {
    PresetBuilder b;
    b.midtones(25.0F, 0.030F); b.highlights(30.0F, 0.040F);
    b.shadows(250.0F, 0.045F);
    b.band(ColorMixerBand::green, -0.04F, 0.10F);
    b.band(ColorMixerBand::blue, 0, 0.10F);
    b.band(ColorMixerBand::purple, 0, 0.10F);
    b.band(ColorMixerBand::magenta, 0, 0.06F);
    b.band(ColorMixerBand::red, 0, -0.03F);
    b.primaries(0, 0, 0, 0.05F, 0, 0.06F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_portra_160() noexcept {
    PresetBuilder b;
    b.shadows(215.0F, 0.042F); b.midtones(40.0F, 0.020F);
    b.highlights(45.0F, 0.030F);
    b.band(ColorMixerBand::orange, 0, 0.03F, 0.03F);
    b.band(ColorMixerBand::red, 0, -0.04F);
    b.band(ColorMixerBand::green, 0.03F, -0.03F);
    b.band(ColorMixerBand::blue, 0, -0.02F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_portra_400() noexcept {
    PresetBuilder b;
    b.shadows(212.0F, 0.050F); b.midtones(38.0F, 0.030F);
    b.highlights(42.0F, 0.055F, 0.02F);
    b.band(ColorMixerBand::orange, 0, 0.05F, 0.03F);
    b.band(ColorMixerBand::red, 0, -0.02F);
    b.band(ColorMixerBand::green, 0.04F, -0.02F);
    b.band(ColorMixerBand::blue, 0, 0.02F);
    b.primaries(0.03F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_portra_800() noexcept {
    PresetBuilder b;
    b.shadows(218.0F, 0.052F); b.midtones(45.0F, 0.034F);
    b.highlights(55.0F, 0.076F);
    b.band(ColorMixerBand::yellow, 0, 0.09F);
    b.band(ColorMixerBand::orange, 0, 0.07F, 0.02F);
    b.band(ColorMixerBand::red, 0, 0.04F);
    b.band(ColorMixerBand::green, 0.05F);
    b.primaries(0.04F, 0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_ektar_100() noexcept {
    PresetBuilder b;
    b.shadows(197.0F, 0.105F, -0.02F); b.midtones(20.0F, 0.025F);
    b.highlights(25.0F, 0.030F);
    b.band(ColorMixerBand::aqua, 0, 0.13F);
    b.band(ColorMixerBand::blue, 0, 0.11F);
    b.band(ColorMixerBand::red, -0.05F, 0.11F);
    b.band(ColorMixerBand::magenta, 0, 0.09F);
    b.band(ColorMixerBand::orange, 0, 0.05F);
    b.band(ColorMixerBand::green, 0, 0.05F);
    b.primaries(-0.05F, 0.07F, 0, 0, 0, 0.06F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_ultramax_400() noexcept {
    PresetBuilder b;
    b.shadows(205.0F, 0.048F); b.highlights(15.0F, 0.075F);
    b.midtones(35.0F, 0.025F);
    b.band(ColorMixerBand::red, 0, 0.06F);
    b.band(ColorMixerBand::orange, 0, 0.05F, 0.02F);
    b.band(ColorMixerBand::green, 0.03F, 0.02F);
    b.band(ColorMixerBand::blue, 0, 0.03F);
    b.primaries(0, 0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_colorplus_200() noexcept {
    PresetBuilder b;
    b.shadows(25.0F, 0.018F); b.midtones(40.0F, 0.055F);
    b.highlights(22.0F, 0.085F);
    b.band(ColorMixerBand::red, 0, 0.12F);
    b.band(ColorMixerBand::orange, 0, 0.11F, 0.03F);
    b.band(ColorMixerBand::yellow, 0, 0.09F);
    b.band(ColorMixerBand::green, 0.06F, -0.05F);
    b.band(ColorMixerBand::blue, 0, -0.07F);
    b.band(ColorMixerBand::aqua, 0, -0.05F);
    b.primaries(0, 0.08F, 0, 0, 0, -0.05F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_fujicolor_c200() noexcept {
    PresetBuilder b;
    b.shadows(140.0F, 0.090F); b.midtones(195.0F, 0.040F);
    b.highlights(200.0F, 0.045F);
    b.band(ColorMixerBand::green, -0.03F, 0.13F);
    b.band(ColorMixerBand::aqua, 0, 0.09F);
    b.band(ColorMixerBand::blue, 0, 0.11F);
    b.band(ColorMixerBand::red, 0, -0.11F);
    b.band(ColorMixerBand::orange, 0, -0.07F);
    b.band(ColorMixerBand::yellow, 0, 0.04F, 0.02F);
    b.primaries(0, -0.06F, 0, 0.07F, 0, 0.06F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_pro_400h() noexcept {
    PresetBuilder b;
    b.shadows(200.0F, 0.055F); b.midtones(190.0F, 0.030F);
    b.highlights(180.0F, 0.050F, 0.02F);
    b.band(ColorMixerBand::green, -0.16F, 0.05F);
    b.band(ColorMixerBand::aqua, 0, 0.10F);
    b.band(ColorMixerBand::blue, 0, 0.06F);
    b.band(ColorMixerBand::red, 0, -0.06F);
    b.band(ColorMixerBand::orange, 0, -0.04F, 0.03F);
    b.primaries(0, 0, -0.07F, 0.05F, 0, 0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_velvia_100() noexcept {
    PresetBuilder b;
    b.shadows(240.0F, 0.030F); b.midtones(30.0F, 0.025F);
    b.highlights(35.0F, 0.028F);
    b.band(ColorMixerBand::green, -0.02F, 0.07F);
    b.band(ColorMixerBand::blue, 0, 0.07F);
    b.band(ColorMixerBand::purple, 0, 0.06F);
    b.primaries(0, 0, 0, 0.03F, 0, 0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_e100_vs() noexcept {
    PresetBuilder b;
    b.shadows(190.0F, 0.060F); b.midtones(30.0F, 0.035F);
    b.highlights(40.0F, 0.045F);
    b.band(ColorMixerBand::red, 0, 0.08F);
    b.band(ColorMixerBand::blue, 0, 0.09F);
    b.band(ColorMixerBand::green, 0, 0.05F);
    b.band(ColorMixerBand::magenta, 0, 0.07F);
    b.primaries(0, 0.05F, 0, 0.03F, 0, 0.05F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_astia_100f() noexcept {
    PresetBuilder b;
    b.midtones(40.0F, 0.020F); b.highlights(45.0F, 0.025F);
    b.band(ColorMixerBand::orange, 0, 0.04F, 0.03F);
    b.band(ColorMixerBand::red, 0, -0.03F);
    b.band(ColorMixerBand::green, 0, -0.02F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_kodachrome_64() noexcept {
    PresetBuilder b;
    b.shadows(0, 0.004F); b.midtones(15.0F, 0.030F);
    b.highlights(20.0F, 0.040F);
    b.band(ColorMixerBand::red, -0.04F, 0.12F);
    b.band(ColorMixerBand::blue, 0, -0.05F);
    b.band(ColorMixerBand::aqua, 0, -0.03F);
    b.band(ColorMixerBand::yellow, 0, 0.06F);
    b.primaries(-0.04F, 0.08F, 0, 0, 0, -0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_gold_200() noexcept {
    PresetBuilder b;
    b.shadows(30.0F, 0.020F); b.midtones(42.0F, 0.050F);
    b.highlights(25.0F, 0.075F);
    b.band(ColorMixerBand::red, 0, 0.10F);
    b.band(ColorMixerBand::orange, 0, 0.09F, 0.03F);
    b.band(ColorMixerBand::yellow, 0, 0.08F);
    b.band(ColorMixerBand::green, 0.05F, -0.04F);
    b.primaries(0, 0.06F, 0, 0, 0, -0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_pro_image_100() noexcept {
    PresetBuilder b;
    b.midtones(42.0F, 0.030F); b.highlights(48.0F, 0.040F);
    b.band(ColorMixerBand::orange, 0, 0.06F, 0.03F);
    b.band(ColorMixerBand::red, 0, 0.02F);
    b.band(ColorMixerBand::green, 0.03F, -0.02F);
    b.primaries(0.02F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_superia_400() noexcept {
    PresetBuilder b;
    b.shadows(150.0F, 0.075F); b.midtones(195.0F, 0.035F);
    b.highlights(200.0F, 0.040F);
    b.band(ColorMixerBand::green, -0.04F, 0.11F);
    b.band(ColorMixerBand::aqua, 0, 0.08F);
    b.band(ColorMixerBand::blue, 0, 0.10F);
    b.band(ColorMixerBand::red, 0, -0.08F);
    b.band(ColorMixerBand::orange, 0, -0.05F);
    b.primaries(0, -0.04F, 0, 0.06F, 0, 0.05F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_superia_premium_400() noexcept {
    PresetBuilder b;
    b.shadows(205.0F, 0.025F); b.midtones(40.0F, 0.035F);
    b.highlights(35.0F, 0.035F);
    b.band(ColorMixerBand::orange, 0, 0.08F, 0.02F);
    b.band(ColorMixerBand::red, 0, 0.025F);
    b.band(ColorMixerBand::green, 0, -0.01F);
    b.primaries(0, 0.01F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_superia_200() noexcept {
    PresetBuilder b;
    b.shadows(148.0F, 0.065F); b.midtones(192.0F, 0.030F);
    b.highlights(198.0F, 0.035F);
    b.band(ColorMixerBand::green, -0.03F, 0.09F);
    b.band(ColorMixerBand::aqua, 0, 0.06F);
    b.band(ColorMixerBand::blue, 0, 0.08F);
    b.band(ColorMixerBand::red, 0, -0.06F);
    b.primaries(0, -0.03F, 0, 0.05F, 0, 0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_reala_100() noexcept {
    PresetBuilder b;
    b.shadows(330.0F, 0.012F); b.midtones(330.0F, 0.010F);
    b.highlights(330.0F, 0.014F, 0.01F);
    b.band(ColorMixerBand::green, 0, -0.05F);
    b.band(ColorMixerBand::aqua, 0, -0.02F);
    b.band(ColorMixerBand::magenta, 0, 0.03F);
    b.primaries(0, 0, 0, -0.03F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_industrial_100() noexcept {
    PresetBuilder b;
    b.shadows(200.0F, 0.045F); b.midtones(190.0F, 0.020F);
    b.highlights(195.0F, 0.030F);
    b.band(ColorMixerBand::green, -0.05F, 0.06F);
    b.band(ColorMixerBand::blue, 0, 0.05F);
    b.band(ColorMixerBand::red, 0, -0.04F);
    b.primaries(0, 0, 0, 0.03F, 0, 0.03F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_lomo_cn_800() noexcept {
    PresetBuilder b;
    b.shadows(210.0F, 0.055F); b.midtones(30.0F, 0.040F);
    b.highlights(25.0F, 0.065F);
    b.band(ColorMixerBand::red, 0, 0.08F);
    b.band(ColorMixerBand::orange, 0, 0.06F);
    b.band(ColorMixerBand::blue, 0, 0.06F);
    b.band(ColorMixerBand::green, 0, -0.03F);
    b.primaries(0, 0.05F, 0, 0, 0, 0.03F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_vision3_500t() noexcept {
    PresetBuilder b;
    b.shadows(200.0F, 0.065F, -0.01F); b.midtones(195.0F, 0.020F);
    b.highlights(190.0F, 0.035F, 0.02F);
    b.band(ColorMixerBand::blue, 0, 0.08F);
    b.band(ColorMixerBand::aqua, 0, 0.06F);
    b.band(ColorMixerBand::orange, 0, -0.04F);
    b.primaries(0, 0, 0, 0, 0, 0.04F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_vision3_250d() noexcept {
    PresetBuilder b;
    b.shadows(205.0F, 0.045F); b.midtones(35.0F, 0.020F);
    b.highlights(40.0F, 0.030F);
    b.band(ColorMixerBand::blue, 0, 0.05F);
    b.band(ColorMixerBand::aqua, 0, 0.04F);
    b.primaries(0, 0, 0, 0, 0, 0.02F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_vision3_50d() noexcept {
    PresetBuilder b;
    b.shadows(208.0F, 0.040F); b.midtones(38.0F, 0.020F);
    b.highlights(42.0F, 0.030F);
    b.band(ColorMixerBand::blue, 0, 0.04F);
    b.band(ColorMixerBand::green, 0, 0.03F);
    b.primaries(0, 0, 0, 0.02F, 0, 0.02F);
    return b.build();
}

[[nodiscard]] DigitalFilmColorPreset make_vision3_200t() noexcept {
    PresetBuilder b;
    b.shadows(198.0F, 0.055F); b.midtones(190.0F, 0.018F);
    b.highlights(188.0F, 0.032F);
    b.band(ColorMixerBand::blue, 0, 0.06F);
    b.band(ColorMixerBand::aqua, 0, 0.05F);
    b.primaries(0, 0, 0, 0, 0, 0.03F);
    return b.build();
}

const DigitalFilmColorPreset ektachrome_e100 = make_ektachrome_e100();
const DigitalFilmColorPreset provia_100f = make_provia_100f();
const DigitalFilmColorPreset velvia_50 = make_velvia_50();
const DigitalFilmColorPreset portra_160 = make_portra_160();
const DigitalFilmColorPreset portra_400 = make_portra_400();
const DigitalFilmColorPreset portra_800 = make_portra_800();
const DigitalFilmColorPreset ektar_100 = make_ektar_100();
const DigitalFilmColorPreset ultramax_400 = make_ultramax_400();
const DigitalFilmColorPreset colorplus_200 = make_colorplus_200();
const DigitalFilmColorPreset fujicolor_c200 = make_fujicolor_c200();
const DigitalFilmColorPreset pro_400h = make_pro_400h();
const DigitalFilmColorPreset velvia_100 = make_velvia_100();
const DigitalFilmColorPreset e100_vs = make_e100_vs();
const DigitalFilmColorPreset astia_100f = make_astia_100f();
const DigitalFilmColorPreset kodachrome_64 = make_kodachrome_64();
const DigitalFilmColorPreset gold_200 = make_gold_200();
const DigitalFilmColorPreset pro_image_100 = make_pro_image_100();
const DigitalFilmColorPreset superia_400 = make_superia_400();
const DigitalFilmColorPreset superia_premium_400 = make_superia_premium_400();
const DigitalFilmColorPreset superia_200 = make_superia_200();
const DigitalFilmColorPreset reala_100 = make_reala_100();
const DigitalFilmColorPreset industrial_100 = make_industrial_100();
const DigitalFilmColorPreset lomo_cn_800 = make_lomo_cn_800();
const DigitalFilmColorPreset vision3_500t = make_vision3_500t();
const DigitalFilmColorPreset vision3_250d = make_vision3_250d();
const DigitalFilmColorPreset vision3_50d = make_vision3_50d();
const DigitalFilmColorPreset vision3_200t = make_vision3_200t();

}  // namespace

const DigitalFilmColorPreset* digital_film_color_preset(
    const FilmEmulation emulation) noexcept {
    switch (emulation) {
        case FilmEmulation::none: return nullptr;
        case FilmEmulation::ektachrome_e100: return &ektachrome_e100;
        case FilmEmulation::provia_100f: return &provia_100f;
        case FilmEmulation::velvia_50: return &velvia_50;
        case FilmEmulation::portra_160: return &portra_160;
        case FilmEmulation::portra_400: return &portra_400;
        case FilmEmulation::portra_800: return &portra_800;
        case FilmEmulation::ektar_100: return &ektar_100;
        case FilmEmulation::ultramax_400: return &ultramax_400;
        case FilmEmulation::colorplus_200: return &colorplus_200;
        case FilmEmulation::fujicolor_c200: return &fujicolor_c200;
        case FilmEmulation::pro_400h: return &pro_400h;
        case FilmEmulation::velvia_100: return &velvia_100;
        case FilmEmulation::e100_vs: return &e100_vs;
        case FilmEmulation::astia_100f: return &astia_100f;
        case FilmEmulation::kodachrome_64: return &kodachrome_64;
        case FilmEmulation::gold_200: return &gold_200;
        case FilmEmulation::pro_image_100: return &pro_image_100;
        case FilmEmulation::superia_400: return &superia_400;
        case FilmEmulation::superia_premium_400:
            return &superia_premium_400;
        case FilmEmulation::superia_200: return &superia_200;
        case FilmEmulation::reala_100: return &reala_100;
        case FilmEmulation::industrial_100: return &industrial_100;
        case FilmEmulation::lomo_cn_800: return &lomo_cn_800;
        case FilmEmulation::vision3_500t: return &vision3_500t;
        case FilmEmulation::vision3_250d: return &vision3_250d;
        case FilmEmulation::vision3_50d: return &vision3_50d;
        case FilmEmulation::vision3_200t: return &vision3_200t;
    }
    return nullptr;
}

}  // namespace negaflow::imaging
