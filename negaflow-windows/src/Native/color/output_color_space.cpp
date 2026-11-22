#include "negaflow/color/output_color_space.h"

#include "negaflow/color/icc_profile.h"
#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <optional>

namespace negaflow::color {
namespace {

using Matrix3 = std::array<double, 9>;

struct Primaries final {
    double red_x{0.0};
    double red_y{0.0};
    double green_x{0.0};
    double green_y{0.0};
    double blue_x{0.0};
    double blue_y{0.0};
};

// Every space here is D65. D50 appears only as the profile connection white point.
constexpr double kD65X = 0.3127;
constexpr double kD65Y = 0.3290;
constexpr double kD50X = 0.34567;
constexpr double kD50Y = 0.35850;

[[nodiscard]] Primaries primaries_of(const OutputColorSpace space) noexcept {
    switch (space) {
        case OutputColorSpace::display_p3:
            return {0.680, 0.320, 0.265, 0.690, 0.150, 0.060};
        case OutputColorSpace::adobe_rgb:
            return {0.640, 0.330, 0.210, 0.710, 0.150, 0.060};
        case OutputColorSpace::srgb:
        default:
            return {0.640, 0.330, 0.300, 0.600, 0.150, 0.060};
    }
}

[[nodiscard]] Matrix3 multiply(const Matrix3& left, const Matrix3& right) noexcept {
    Matrix3 result{};
    for (std::size_t row = 0U; row < 3U; ++row) {
        for (std::size_t column = 0U; column < 3U; ++column) {
            double sum = 0.0;
            for (std::size_t index = 0U; index < 3U; ++index) {
                sum += left[(row * 3U) + index] * right[(index * 3U) + column];
            }
            result[(row * 3U) + column] = sum;
        }
    }
    return result;
}

[[nodiscard]] Matrix3 invert(const Matrix3& m) noexcept {
    const double determinant =
        (m[0] * ((m[4] * m[8]) - (m[5] * m[7]))) -
        (m[1] * ((m[3] * m[8]) - (m[5] * m[6]))) +
        (m[2] * ((m[3] * m[7]) - (m[4] * m[6])));
    if (std::abs(determinant) < 1.0e-12) {
        return {1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0};
    }
    const double inverse = 1.0 / determinant;
    return {
        ((m[4] * m[8]) - (m[5] * m[7])) * inverse,
        ((m[2] * m[7]) - (m[1] * m[8])) * inverse,
        ((m[1] * m[5]) - (m[2] * m[4])) * inverse,
        ((m[5] * m[6]) - (m[3] * m[8])) * inverse,
        ((m[0] * m[8]) - (m[2] * m[6])) * inverse,
        ((m[2] * m[3]) - (m[0] * m[5])) * inverse,
        ((m[3] * m[7]) - (m[4] * m[6])) * inverse,
        ((m[1] * m[6]) - (m[0] * m[7])) * inverse,
        ((m[0] * m[4]) - (m[1] * m[3])) * inverse,
    };
}

// Linear RGB into XYZ for the given primaries and white point, by the standard
// construction: scale each primary's chromaticity so the sum reproduces the white.
[[nodiscard]] Matrix3 rgb_to_xyz(
    const Primaries& primaries,
    const double white_x,
    const double white_y) noexcept {
    const Matrix3 chromaticities{
        primaries.red_x / primaries.red_y,
        primaries.green_x / primaries.green_y,
        primaries.blue_x / primaries.blue_y,
        1.0,
        1.0,
        1.0,
        (1.0 - primaries.red_x - primaries.red_y) / primaries.red_y,
        (1.0 - primaries.green_x - primaries.green_y) / primaries.green_y,
        (1.0 - primaries.blue_x - primaries.blue_y) / primaries.blue_y,
    };
    const Matrix3 inverse = invert(chromaticities);
    const double white[3]{white_x / white_y, 1.0, (1.0 - white_x - white_y) / white_y};
    const double scale[3]{
        (inverse[0] * white[0]) + (inverse[1] * white[1]) + (inverse[2] * white[2]),
        (inverse[3] * white[0]) + (inverse[4] * white[1]) + (inverse[5] * white[2]),
        (inverse[6] * white[0]) + (inverse[7] * white[1]) + (inverse[8] * white[2]),
    };
    Matrix3 result{};
    for (std::size_t row = 0U; row < 3U; ++row) {
        for (std::size_t column = 0U; column < 3U; ++column) {
            result[(row * 3U) + column] =
                chromaticities[(row * 3U) + column] * scale[column];
        }
    }
    return result;
}

// Bradford adaptation from D65 to D50, used only for the profile's XYZ tags.
[[nodiscard]] Matrix3 bradford_d65_to_d50() noexcept {
    constexpr Matrix3 forward{
        0.8951, 0.2664, -0.1614,
        -0.7502, 1.7135, 0.0367,
        0.0389, -0.0685, 1.0296,
    };
    const Matrix3 backward = invert(forward);
    auto cone = [&](const double x, const double y) {
        const double xyz[3]{x / y, 1.0, (1.0 - x - y) / y};
        return std::array<double, 3>{
            (forward[0] * xyz[0]) + (forward[1] * xyz[1]) + (forward[2] * xyz[2]),
            (forward[3] * xyz[0]) + (forward[4] * xyz[1]) + (forward[5] * xyz[2]),
            (forward[6] * xyz[0]) + (forward[7] * xyz[1]) + (forward[8] * xyz[2]),
        };
    };
    const std::array<double, 3> source = cone(kD65X, kD65Y);
    const std::array<double, 3> destination = cone(kD50X, kD50Y);
    const Matrix3 ratio{
        destination[0] / source[0], 0.0, 0.0,
        0.0, destination[1] / source[1], 0.0,
        0.0, 0.0, destination[2] / source[2],
    };
    return multiply(backward, multiply(ratio, forward));
}

void append_u32(std::vector<std::uint8_t>& bytes, const std::uint32_t value) {
    bytes.push_back(static_cast<std::uint8_t>((value >> 24U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 16U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
}

void append_u16(std::vector<std::uint8_t>& bytes, const std::uint16_t value) {
    bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
}

void append_tag(std::vector<std::uint8_t>& bytes, const char* const tag) {
    for (std::size_t index = 0U; index < 4U; ++index) {
        bytes.push_back(static_cast<std::uint8_t>(tag[index]));
    }
}

[[nodiscard]] std::int32_t to_s15fixed16(const double value) noexcept {
    return static_cast<std::int32_t>(std::lround(value * 65536.0));
}

void write_u32(std::vector<std::uint8_t>& bytes, const std::size_t at, const std::uint32_t value) {
    bytes[at] = static_cast<std::uint8_t>((value >> 24U) & 0xFFU);
    bytes[at + 1U] = static_cast<std::uint8_t>((value >> 16U) & 0xFFU);
    bytes[at + 2U] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
    bytes[at + 3U] = static_cast<std::uint8_t>(value & 0xFFU);
}

[[nodiscard]] std::vector<std::uint8_t> xyz_element(
    const double x,
    const double y,
    const double z) {
    std::vector<std::uint8_t> element{};
    append_tag(element, "XYZ ");
    append_u32(element, 0U);
    append_u32(element, static_cast<std::uint32_t>(to_s15fixed16(x)));
    append_u32(element, static_cast<std::uint32_t>(to_s15fixed16(y)));
    append_u32(element, static_cast<std::uint32_t>(to_s15fixed16(z)));
    return element;
}

// A parametric curve would be exact for the sRGB piecewise transfer, but 'para' is v4 and
// this profile is v2. A 1024-point sampled 'curv' reproduces either EOTF (encoded -> linear
// PCS) to well under a 16-bit step, which is what an 8- or 16-bit file can carry anyway.
[[nodiscard]] std::vector<std::uint8_t> curve_element(
    const OutputColorSpace space,
    const bool linear_transfer) {
    constexpr std::uint32_t points = 1024U;
    std::vector<std::uint8_t> element{};
    append_tag(element, "curv");
    append_u32(element, 0U);
    append_u32(element, points);
    for (std::uint32_t index = 0U; index < points; ++index) {
        const double encoded = static_cast<double>(index) / static_cast<double>(points - 1U);
        double linear = encoded;
        if (!linear_transfer) {
            linear = space == OutputColorSpace::adobe_rgb
                ? std::pow(encoded, 563.0 / 256.0)
                : static_cast<double>(srgb_encoded_to_linear(static_cast<float>(encoded)));
        }
        append_u16(
            element,
            static_cast<std::uint16_t>(std::lround(std::clamp(linear, 0.0, 1.0) * 65535.0)));
    }
    return element;
}

[[nodiscard]] std::vector<std::uint8_t> desc_element(const char* const text) {
    std::vector<std::uint8_t> element{};
    append_tag(element, "desc");
    append_u32(element, 0U);
    const std::uint32_t length = static_cast<std::uint32_t>(std::strlen(text)) + 1U;
    append_u32(element, length);
    for (std::uint32_t index = 0U; index < length; ++index) {
        element.push_back(static_cast<std::uint8_t>(text[index]));
    }
    // 'desc' carries unicode and script code counts after the ASCII body.
    element.insert(element.end(), 12U + 67U, 0U);
    return element;
}

[[nodiscard]] std::vector<std::uint8_t> cprt_text_element(const char* const text) {
    std::vector<std::uint8_t> element{};
    append_tag(element, "text");
    append_u32(element, 0U);
    const std::uint32_t length = static_cast<std::uint32_t>(std::strlen(text)) + 1U;
    for (std::uint32_t index = 0U; index < length; ++index) {
        element.push_back(static_cast<std::uint8_t>(text[index]));
    }
    return element;
}

[[nodiscard]] const char* icc_profile_description(
    const OutputColorSpace space,
    const bool linear_transfer) noexcept {
    if (linear_transfer) {
        return space == OutputColorSpace::srgb ? "Linear sRGB" : nullptr;
    }
    switch (space) {
        case OutputColorSpace::srgb: return "sRGB";
        case OutputColorSpace::display_p3: return "Negaflow Compatible P3";
        case OutputColorSpace::adobe_rgb: return "Compatible with Adobe RGB (1998)";
    }
    return nullptr;
}

}  // namespace

ColorMatrix linear_srgb_to(const OutputColorSpace space) noexcept {
    if (space == OutputColorSpace::srgb) {
        return {1.0F, 0.0F, 0.0F, 0.0F, 1.0F, 0.0F, 0.0F, 0.0F, 1.0F};
    }
    const Matrix3 source = rgb_to_xyz(primaries_of(OutputColorSpace::srgb), kD65X, kD65Y);
    const Matrix3 destination = rgb_to_xyz(primaries_of(space), kD65X, kD65Y);
    const Matrix3 combined = multiply(invert(destination), source);
    ColorMatrix result{};
    for (std::size_t index = 0U; index < 9U; ++index) {
        result[index] = static_cast<float>(combined[index]);
    }
    return result;
}

std::array<double, 9> d65_xyz_to_linear_rgb(const OutputColorSpace space) noexcept {
    return invert(rgb_to_xyz(primaries_of(space), kD65X, kD65Y));
}

float encode_output_component(const float linear, const OutputColorSpace space) noexcept {
    if (space == OutputColorSpace::adobe_rgb) {
        // Adobe RGB (1998) states 563/256. Negatives cannot happen here - the caller
        // clamps before encoding - but guard anyway so a stray value cannot become NaN.
        return linear <= 0.0F
            ? 0.0F
            : std::pow(linear, 1.0F / (563.0F / 256.0F));
    }
    return linear_to_srgb_encoded(linear);
}

namespace {

// Rec.2020 기본색입니다. 입력 ICC 를 옮길 내부 중간 공간에만 씁니다 — 게시 색공간이 아닙니다.
constexpr Primaries kRec2020Primaries{0.708, 0.292, 0.170, 0.797, 0.131, 0.046};

[[nodiscard]] std::vector<std::uint8_t> build_matrix_trc_profile(
    const Primaries& primaries,
    const char* description,
    const std::vector<std::uint8_t>& curve);

}  // namespace

std::vector<std::uint8_t> build_icc_profile(
    const OutputColorSpace space,
    const bool linear_transfer) {
    if (linear_transfer && space != OutputColorSpace::srgb) {
        return {};
    }
    const char* description = icc_profile_description(space, linear_transfer);
    if (description == nullptr) {
        return {};
    }
    return build_matrix_trc_profile(
        primaries_of(space), description, curve_element(space, linear_transfer));
}

std::vector<std::uint8_t> build_working_intermediate_icc_profile() {
    return build_matrix_trc_profile(
        kRec2020Primaries,
        "Negaflow Working Intermediate (Rec.2020, sRGB curve)",
        curve_element(OutputColorSpace::srgb, false));
}

ColorMatrix working_intermediate_to_linear_srgb() noexcept {
    const Matrix3 source = rgb_to_xyz(kRec2020Primaries, kD65X, kD65Y);
    const Matrix3 destination = rgb_to_xyz(primaries_of(OutputColorSpace::srgb), kD65X, kD65Y);
    const Matrix3 combined = multiply(invert(destination), source);
    ColorMatrix result{};
    for (std::size_t index = 0U; index < 9U; ++index) {
        result[index] = static_cast<float>(combined[index]);
    }
    return result;
}

namespace {

std::vector<std::uint8_t> build_matrix_trc_profile(
    const Primaries& primaries,
    const char* const description,
    const std::vector<std::uint8_t>& curve) {
    const Matrix3 to_xyz_d65 = rgb_to_xyz(primaries, kD65X, kD65Y);
    const Matrix3 to_d50 = multiply(bradford_d65_to_d50(), to_xyz_d65);

    struct TagEntry final {
        const char* signature;
        std::vector<std::uint8_t> element;
    };
    std::vector<TagEntry> tags{};
    tags.push_back({"desc", desc_element(description)});
    tags.push_back({"wtpt", xyz_element(
        kD50X / kD50Y,
        1.0,
        (1.0 - kD50X - kD50Y) / kD50Y)});
    tags.push_back({"rXYZ", xyz_element(to_d50[0], to_d50[3], to_d50[6])});
    tags.push_back({"gXYZ", xyz_element(to_d50[1], to_d50[4], to_d50[7])});
    tags.push_back({"bXYZ", xyz_element(to_d50[2], to_d50[5], to_d50[8])});
    tags.push_back({"rTRC", curve});
    tags.push_back({"gTRC", curve});
    tags.push_back({"bTRC", curve});
    tags.push_back({"cprt", cprt_text_element("Copyright Song Habin. CC0 1.0 Universal.")});

    const std::uint32_t tag_count = static_cast<std::uint32_t>(tags.size());
    const std::uint32_t table_bytes = 4U + (tag_count * 12U);
    std::uint32_t offset = 128U + table_bytes;

    std::vector<std::uint8_t> profile(128U, 0U);
    append_u32(profile, tag_count);
    std::vector<std::uint32_t> offsets{};
    for (const TagEntry& tag : tags) {
        append_tag(profile, tag.signature);
        append_u32(profile, offset);
        append_u32(profile, static_cast<std::uint32_t>(tag.element.size()));
        offsets.push_back(offset);
        // Elements are four-byte aligned, as the specification requires.
        offset += static_cast<std::uint32_t>((tag.element.size() + 3U) & ~std::size_t{3U});
    }
    for (const TagEntry& tag : tags) {
        profile.insert(profile.end(), tag.element.begin(), tag.element.end());
        while ((profile.size() & 3U) != 0U) {
            profile.push_back(0U);
        }
    }

    write_u32(profile, 0U, static_cast<std::uint32_t>(profile.size()));
    std::memcpy(profile.data() + 12U, "mntr", 4U);
    std::memcpy(profile.data() + 16U, "RGB ", 4U);
    std::memcpy(profile.data() + 20U, "XYZ ", 4U);
    // Version 2.4.0, and the 'acsp' signature every profile carries.
    write_u32(profile, 8U, 0x02400000U);
    std::memcpy(profile.data() + 36U, "acsp", 4U);
    // Perceptual is the rendering intent macOS writes for these display spaces.
    write_u32(profile, 64U, 0U);
    write_u32(profile, 68U, static_cast<std::uint32_t>(to_s15fixed16(kD50X / kD50Y)));
    write_u32(profile, 72U, static_cast<std::uint32_t>(to_s15fixed16(1.0)));
    write_u32(profile, 76U,
        static_cast<std::uint32_t>(to_s15fixed16((1.0 - kD50X - kD50Y) / kD50Y)));
    return profile;
}

}  // namespace

namespace {

[[nodiscard]] std::uint32_t read_u32(std::span<const std::uint8_t> bytes, std::size_t at) noexcept {
    return (static_cast<std::uint32_t>(bytes[at]) << 24U) |
           (static_cast<std::uint32_t>(bytes[at + 1U]) << 16U) |
           (static_cast<std::uint32_t>(bytes[at + 2U]) << 8U) |
           static_cast<std::uint32_t>(bytes[at + 3U]);
}

[[nodiscard]] double read_s15(std::span<const std::uint8_t> bytes, std::size_t at) noexcept {
    return static_cast<double>(static_cast<std::int32_t>(read_u32(bytes, at))) / 65536.0;
}

// ICC `curv`·`para` 곡선을 [0,1] 입력에서 계산합니다. 못 읽으면 빈 값입니다.
[[nodiscard]] std::optional<double> evaluate_gray_trc(
    std::span<const std::uint8_t> element,
    const double x) noexcept {
    const std::uint32_t type = read_u32(element, 0U);
    if (type == 0x63757276U) {  // 'curv'
        const std::uint32_t count = read_u32(element, 8U);
        if (count == 0U) {
            return x;
        }
        if (count == 1U) {
            if (element.size() < 14U) {
                return std::nullopt;
            }
            const double gamma = static_cast<double>(
                (static_cast<std::uint32_t>(element[12U]) << 8U) | element[13U]) / 256.0;
            return std::pow(x, gamma);
        }
        if (element.size() < 12U + static_cast<std::size_t>(count) * 2U) {
            return std::nullopt;
        }
        const double position = x * static_cast<double>(count - 1U);
        const std::size_t lower = std::min<std::size_t>(
            static_cast<std::size_t>(position), count - 1U);
        const std::size_t upper = std::min<std::size_t>(lower + 1U, count - 1U);
        const double fraction = position - static_cast<double>(lower);
        const auto sample = [&](const std::size_t index) {
            return static_cast<double>(
                (static_cast<std::uint32_t>(element[12U + index * 2U]) << 8U) |
                element[13U + index * 2U]) / 65535.0;
        };
        return sample(lower) + ((sample(upper) - sample(lower)) * fraction);
    }
    if (type == 0x70617261U && element.size() >= 16U) {  // 'para'
        const std::uint32_t function = (static_cast<std::uint32_t>(element[8U]) << 8U) | element[9U];
        constexpr std::array<std::size_t, 5U> parameter_counts{1U, 3U, 4U, 5U, 7U};
        if (function >= parameter_counts.size() ||
            element.size() < 12U + parameter_counts[function] * 4U) {
            return std::nullopt;
        }
        std::array<double, 7U> p{};
        for (std::size_t index = 0U; index < parameter_counts[function]; ++index) {
            p[index] = read_s15(element, 12U + index * 4U);
        }
        const double g = p[0];
        // 함수 1~4 는 a·x + b 위에 감마를 겁니다. a 가 0 이하면 경계 -b/a 가 0 으로 나누기거나
        // 뒤집혀 곡선이 아니므로 거절합니다. 경계 위라도 저장 반올림으로 a·x + b 가 아주 조금
        // 음수가 될 수 있어 0 으로 받친 뒤 거듭제곱합니다(음수의 비정수 거듭제곱은 NaN).
        if (!(g > 0.0) || (function >= 1U && !(p[1] > 0.0))) {
            return std::nullopt;
        }
        const auto power = [&](const double value) {
            return std::pow(std::max((p[1] * value) + p[2], 0.0), g);
        };
        switch (function) {
            case 0U: return std::pow(x, g);
            case 1U: return x >= -p[2] / p[1] ? power(x) : 0.0;
            case 2U: return x >= -p[2] / p[1] ? power(x) + p[3] : p[3];
            case 3U: return x >= p[4] ? power(x) : p[3] * x;
            default: return x >= p[4] ? power(x) + p[5] : (p[3] * x) + p[6];
        }
    }
    return std::nullopt;
}

}  // namespace

std::vector<std::uint8_t> rgb_profile_for_gray_profile(
    const std::span<const std::uint8_t> gray_profile) {
    const IccProfileValidationResult validation = validate_icc_profile(gray_profile);
    if (validation.status != IccProfileStatus::ok ||
        validation.info.data_color_space != 0x47524159U) {  // 'GRAY'
        return {};
    }
    std::span<const std::uint8_t> trc{};
    for (std::uint32_t index = 0U; index < validation.info.tag_count; ++index) {
        const std::size_t record = 132U + static_cast<std::size_t>(index) * 12U;
        if (read_u32(gray_profile, record) == 0x6B545243U) {  // 'kTRC'
            trc = gray_profile.subspan(
                read_u32(gray_profile, record + 4U), read_u32(gray_profile, record + 8U));
            break;
        }
    }
    if (trc.size() < 12U) {
        return {};
    }
    constexpr std::uint32_t points = 1024U;
    std::vector<std::uint8_t> curve{};
    append_tag(curve, "curv");
    append_u32(curve, 0U);
    append_u32(curve, points);
    for (std::uint32_t index = 0U; index < points; ++index) {
        const std::optional<double> value = evaluate_gray_trc(
            trc, static_cast<double>(index) / static_cast<double>(points - 1U));
        if (!value.has_value() || !std::isfinite(*value)) {
            return {};
        }
        append_u16(curve, static_cast<std::uint16_t>(
            std::lround(std::clamp(*value, 0.0, 1.0) * 65535.0)));
    }
    return build_matrix_trc_profile(
        primaries_of(OutputColorSpace::srgb), "Negaflow Gray (as RGB)", curve);
}

const char* output_color_space_name(const OutputColorSpace space) noexcept {
    switch (space) {
        case OutputColorSpace::srgb: return "sRGB";
        case OutputColorSpace::display_p3: return "Display P3";
        case OutputColorSpace::adobe_rgb: return "Adobe RGB (1998)";
    }
    return nullptr;
}

}  // namespace negaflow::color
