#include "negaflow/color/input_gamma_profile.h"
#include "negaflow/color/icc_profile.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <new>

namespace negaflow::color {
namespace {
constexpr std::size_t maximum_bytes = 16U * 1024U * 1024U;
constexpr std::array<std::uint32_t, 7> required{
    0x72545243U, 0x67545243U, 0x62545243U,
    0x7258595AU, 0x6758595AU, 0x6258595AU, 0x77747074U};

std::uint32_t read32(std::span<const std::uint8_t> bytes, std::size_t at) noexcept {
    std::uint32_t result = 0;
    for (std::size_t i = 0; i < 4U; ++i) { result = (result << 8U) | bytes[at + i]; }
    return result;
}

void write32(std::vector<std::uint8_t>& bytes, std::size_t at, std::uint32_t value) noexcept {
    for (std::size_t i = 0; i < 4U; ++i) {
        bytes[at + i] = static_cast<std::uint8_t>(value >> ((3U - i) * 8U));
    }
}

bool valid_curve(std::span<const std::uint8_t> curve) noexcept {
    if (curve.size() < 12U) { return false; }
    if (read32(curve, 0U) == 0x63757276U) {
        return read32(curve, 8U) <= (curve.size() - 12U) / 2U;
    }
    if (read32(curve, 0U) == 0x70617261U) {
        constexpr std::array<std::size_t, 5> counts{1U, 3U, 4U, 5U, 7U};
        const auto type = (static_cast<std::size_t>(curve[8]) << 8U) | curve[9];
        return type < counts.size() && curve.size() >= 12U + counts[type] * 4U;
    }
    return false;
}
}  // namespace

InputGammaProfileResult make_input_gamma_profile(
    const std::span<const std::uint8_t> source,
    const InputGammaInterpretation gamma) noexcept {
    InputGammaProfileResult result{};
    if (!gamma.valid() || gamma.mode != 1U) {
        result.status = InputGammaProfileStatus::invalid_gamma;
        return result;
    }
    const auto validated = validate_icc_profile(source);
    if (validated.status != IccProfileStatus::ok) { return result; }
    if ((source[8] != 2U && source[8] != 4U) ||
        (validated.info.device_class != 0x73636E72U && validated.info.device_class != 0x6D6E7472U) ||
        validated.info.data_color_space != 0x52474220U || validated.info.pcs != 0x58595A20U) {
        result.status = InputGammaProfileStatus::unsupported_profile;
        return result;
    }
    try {
        const auto count = static_cast<std::size_t>(validated.info.tag_count);
        const auto table_end = 132U + count * 12U;
        std::array<bool, required.size()> found{};
        // 16-bit 원본 코드 각각의 power 값을 담습니다. v2 ICC의 8.8 gamma 반올림을 피하며
        // RGB 채널은 같은 표를 공유합니다. 최대 TRC 양자화 오차는 0.5/65535입니다.
        const std::size_t samples = gamma.value == 1.0 ? 0U : 65536U;
        std::vector<std::uint8_t> curve(12U + samples * 2U, 0U);
        write32(curve, 0U, 0x63757276U);
        write32(curve, 8U, static_cast<std::uint32_t>(samples));
        for (std::size_t i = 0U; i < samples; ++i) {
            const auto value = static_cast<std::uint16_t>(std::lround(
                std::pow(static_cast<double>(i) / 65535.0, gamma.value) * 65535.0));
            curve[12U + i * 2U] = static_cast<std::uint8_t>(value >> 8U);
            curve[13U + i * 2U] = static_cast<std::uint8_t>(value);
        }
        std::vector<std::uint8_t> bytes(source.begin(), source.begin() + static_cast<std::ptrdiff_t>(table_end));
        std::size_t curve_offset = 0U;
        for (std::size_t i = 0U; i < count; ++i) {
            const auto record = 132U + i * 12U;
            const auto name = read32(source, record);
            const auto offset = read32(source, record + 4U);
            const auto size = read32(source, record + 8U);
            const auto tag = source.subspan(offset, size);
            const auto prefix = name >> 8U;
            if (prefix == 0x413242U || prefix == 0x423241U || prefix == 0x443242U || prefix == 0x423244U) {
                result.status = InputGammaProfileStatus::unsupported_profile;
                return result;
            }
            const auto position = std::find(required.begin(), required.end(), name);
            const auto index = static_cast<std::size_t>(position - required.begin());
            const bool is_curve = index < 3U;
            if (position != required.end()) {
                found[index] = true;
                if ((is_curve && !valid_curve(tag)) ||
                    (!is_curve && (tag.size() < 20U || read32(tag, 0U) != 0x58595A20U))) {
                    return result;
                }
            }
            if (is_curve && curve_offset != 0U) {
                write32(bytes, record + 4U, static_cast<std::uint32_t>(curve_offset));
                write32(bytes, record + 8U, static_cast<std::uint32_t>(curve.size()));
                continue;
            }
            const std::span<const std::uint8_t> payload = is_curve ? std::span<const std::uint8_t>(curve) : tag;
            if (payload.size() + 3U > maximum_bytes - bytes.size()) { return result; }
            write32(bytes, record + 4U, static_cast<std::uint32_t>(bytes.size()));
            write32(bytes, record + 8U, static_cast<std::uint32_t>(payload.size()));
            if (is_curve) { curve_offset = bytes.size(); }
            bytes.insert(bytes.end(), payload.begin(), payload.end());
            while (bytes.size() % 4U != 0U) { bytes.push_back(0U); }
        }
        if (std::find(found.begin(), found.end(), false) != found.end()) {
            result.status = InputGammaProfileStatus::unsupported_profile;
            return result;
        }
        std::fill(bytes.begin() + 84, bytes.begin() + 100, 0U);
        write32(bytes, 0U, static_cast<std::uint32_t>(bytes.size()));
        result.bytes = std::move(bytes);
        result.status = InputGammaProfileStatus::ok;
    } catch (const std::bad_alloc&) {
        result.status = InputGammaProfileStatus::allocation_failed;
    } catch (...) {
        result.status = InputGammaProfileStatus::invalid_profile;
    }
    return result;
}

std::optional<double> recorded_input_gamma(const std::span<const std::uint8_t> source) noexcept {
    if (make_input_gamma_profile(source, {1U, 1.0}).status != InputGammaProfileStatus::ok) { return {}; }
    std::optional<double> power;
    std::size_t found = 0;
    for (std::size_t i = 0; i < read32(source, 128U); ++i) {
        const auto entry = 132U + i * 12U;
        const auto name = read32(source, entry);
        if (std::find(required.begin(), required.begin() + 3, name) == required.begin() + 3) { continue; }
        const auto offset = read32(source, entry + 4U);
        const auto type = read32(source, offset);
        double value = 0;
        if (type == 0x63757276U && read32(source, offset + 8U) == 0U) { value = 1.0; }
        else if (type == 0x63757276U && read32(source, offset + 8U) == 1U) {
            value = (static_cast<double>(source[offset + 12U]) * 256.0 + source[offset + 13U]) / 256.0;
        } else if (type == 0x70617261U && source[offset + 8U] == 0U && source[offset + 9U] == 0U) {
            const auto fixed = read32(source, offset + 12U);
            if (fixed > 0x7fffffffU) { return {}; }
            value = static_cast<double>(fixed) / 65536.0;
        } else { return {}; }
        if (value <= 0 || !std::isfinite(value) || (power && *power != value)) { return {}; }
        power = value;
        ++found;
    }
    return found == 3U ? power : std::nullopt;
}
}  // namespace negaflow::color
