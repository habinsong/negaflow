#include "negaflow/imaging/display_color_lut.h"

#include "negaflow/color/output_color_space.h"
#include "negaflow/core/parallel_rows.h"

#include <Windows.h>
#include <icm.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr std::uint32_t kGrid = DisplayColorLut::grid;
constexpr float kLastCell = static_cast<float>(kGrid - 1U);

class Profile final {
public:
    explicit Profile(std::vector<std::uint8_t>& bytes) noexcept {
        PROFILE description{};
        description.dwType = PROFILE_MEMBUFFER;
        description.pProfileData = bytes.data();
        description.cbDataSize = static_cast<DWORD>(bytes.size());
        handle_ = OpenColorProfileW(&description, PROFILE_READ, FILE_SHARE_READ, OPEN_EXISTING);
        if (handle_ == nullptr) {
            error_ = static_cast<std::uint32_t>(GetLastError());
        }
    }
    Profile(const Profile&) = delete;
    Profile& operator=(const Profile&) = delete;
    ~Profile() noexcept {
        if (handle_ != nullptr) {
            static_cast<void>(CloseColorProfile(handle_));
        }
    }
    [[nodiscard]] HPROFILE get() const noexcept { return handle_; }
    [[nodiscard]] std::uint32_t error() const noexcept { return error_; }

private:
    HPROFILE handle_{nullptr};
    std::uint32_t error_{0U};
};

[[nodiscard]] std::size_t node(const std::uint32_t r, const std::uint32_t g, const std::uint32_t b) noexcept {
    return ((((static_cast<std::size_t>(r) * kGrid) + g) * kGrid) + b) * 3U;
}

// 8비트 값마다 격자 칸과 칸 안 위치를 미리 정해 둡니다. 화소마다 나눗셈을 하지 않습니다.
struct CellTable final {
    std::array<std::uint8_t, 256> cell{};
    std::array<float, 256> fraction{};
    CellTable() noexcept {
        for (std::uint32_t value = 0U; value < 256U; ++value) {
            const float position = (static_cast<float>(value) / 255.0F) * kLastCell;
            const auto lower = std::min(static_cast<std::uint32_t>(position), kGrid - 2U);
            cell[value] = static_cast<std::uint8_t>(lower);
            fraction[value] = position - static_cast<float>(lower);
        }
    }
};

const CellTable& cells() noexcept {
    static const CellTable table{};
    return table;
}

// 사면체 보간. x = R, y = G, z = B 칸 안 위치이며 c000…c111 은 칸 꼭짓점입니다.
void tetrahedral(
    const float* const table,
    const std::uint32_t r,
    const std::uint32_t g,
    const std::uint32_t b,
    const float fx,
    const float fy,
    const float fz,
    float out[3]) noexcept {
    const float* const c000 = table + node(r, g, b);
    const float* const c111 = table + node(r + 1U, g + 1U, b + 1U);
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        float value = 0.0F;
        if (fx >= fy) {
            if (fy >= fz) {
                const float* const c100 = table + node(r + 1U, g, b);
                const float* const c110 = table + node(r + 1U, g + 1U, b);
                value = c000[channel] + (fx * (c100[channel] - c000[channel])) +
                        (fy * (c110[channel] - c100[channel])) + (fz * (c111[channel] - c110[channel]));
            } else if (fx >= fz) {
                const float* const c100 = table + node(r + 1U, g, b);
                const float* const c101 = table + node(r + 1U, g, b + 1U);
                value = c000[channel] + (fx * (c100[channel] - c000[channel])) +
                        (fz * (c101[channel] - c100[channel])) + (fy * (c111[channel] - c101[channel]));
            } else {
                const float* const c001 = table + node(r, g, b + 1U);
                const float* const c101 = table + node(r + 1U, g, b + 1U);
                value = c000[channel] + (fz * (c001[channel] - c000[channel])) +
                        (fx * (c101[channel] - c001[channel])) + (fy * (c111[channel] - c101[channel]));
            }
        } else {
            if (fz >= fy) {
                const float* const c001 = table + node(r, g, b + 1U);
                const float* const c011 = table + node(r, g + 1U, b + 1U);
                value = c000[channel] + (fz * (c001[channel] - c000[channel])) +
                        (fy * (c011[channel] - c001[channel])) + (fx * (c111[channel] - c011[channel]));
            } else if (fz >= fx) {
                const float* const c010 = table + node(r, g + 1U, b);
                const float* const c011 = table + node(r, g + 1U, b + 1U);
                value = c000[channel] + (fy * (c010[channel] - c000[channel])) +
                        (fz * (c011[channel] - c010[channel])) + (fx * (c111[channel] - c011[channel]));
            } else {
                const float* const c010 = table + node(r, g + 1U, b);
                const float* const c110 = table + node(r + 1U, g + 1U, b);
                value = c000[channel] + (fy * (c010[channel] - c000[channel])) +
                        (fx * (c110[channel] - c010[channel])) + (fz * (c111[channel] - c110[channel]));
            }
        }
        out[channel] = value;
    }
}

[[nodiscard]] std::uint8_t to_byte(const float value) noexcept {
    return static_cast<std::uint8_t>(std::lround(std::clamp(value, 0.0F, 1.0F) * 255.0F));
}

}  // namespace

bool DisplayColorLut::build(
    const std::span<const std::uint8_t> monitor_icc,
    std::uint32_t& native_error_code,
    const bool round_trip) noexcept {
    native_error_code = 0U;
    table_.clear();
    identity_ = false;
    if (monitor_icc.size() < 128U ||
        monitor_icc.size() > static_cast<std::size_t>(std::numeric_limits<DWORD>::max())) {
        return false;
    }
    std::vector<std::uint8_t> source_bytes{};
    std::vector<std::uint8_t> destination_bytes{};
    std::vector<COLOR> input{};
    std::vector<COLOR> output{};
    std::vector<float> table{};
    try {
        source_bytes = negaflow::color::build_icc_profile(negaflow::color::OutputColorSpace::srgb);
        destination_bytes.assign(monitor_icc.begin(), monitor_icc.end());
        input.resize(static_cast<std::size_t>(kGrid) * kGrid * kGrid);
        output.resize(input.size());
        table.resize(input.size() * 3U);
    } catch (const std::bad_alloc&) {
        return false;
    }
    const Profile source(source_bytes);
    const Profile destination(destination_bytes);
    if (source.get() == nullptr || destination.get() == nullptr) {
        native_error_code = source.get() == nullptr ? source.error() : destination.error();
        return false;
    }
    HPROFILE profiles[]{source.get(), destination.get(), source.get()};
    DWORD intents[]{
        INTENT_RELATIVE_COLORIMETRIC, INTENT_RELATIVE_COLORIMETRIC, INTENT_RELATIVE_COLORIMETRIC};
    const DWORD profile_count = round_trip ? 3U : 2U;
    SetLastError(ERROR_SUCCESS);
    // 왕복 프루프는 `soft_proof_convert_bgra_icc` 와 같은 플래그(상대 색도 + BEST_MODE)입니다.
    HTRANSFORM transform = CreateMultiProfileTransform(
        profiles,
        profile_count,
        intents,
        profile_count,
        round_trip ? (USE_RELATIVE_COLORIMETRIC | BEST_MODE) : BEST_MODE,
        INDEX_DONT_CARE);
    if (transform == nullptr) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return false;
    }
    // `TranslateColors` 의 COLOR_RGB 는 red·green·blue 이름 그대로 읽힙니다. 비트맵 형식
    // (`BM_16b_RGB` 는 메모리 B,G,R)과 달리 채널 순서를 맞출 일이 없습니다(2026-11-22 실측).
    for (std::uint32_t r = 0U; r < kGrid; ++r) {
        for (std::uint32_t g = 0U; g < kGrid; ++g) {
            for (std::uint32_t b = 0U; b < kGrid; ++b) {
                COLOR& color = input[node(r, g, b) / 3U];
                color.rgb.red = static_cast<WORD>(std::lround((r / kLastCell) * 65535.0F));
                color.rgb.green = static_cast<WORD>(std::lround((g / kLastCell) * 65535.0F));
                color.rgb.blue = static_cast<WORD>(std::lround((b / kLastCell) * 65535.0F));
            }
        }
    }
    SetLastError(ERROR_SUCCESS);
    const BOOL translated = TranslateColors(
        transform, input.data(), static_cast<DWORD>(input.size()), COLOR_RGB, output.data(), COLOR_RGB);
    if (translated == FALSE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
    }
    static_cast<void>(DeleteColorTransform(transform));
    if (translated == FALSE) {
        return false;
    }
    int largest_shift = 0;
    for (std::size_t index = 0U; index < output.size(); ++index) {
        const WORD in[3]{input[index].rgb.red, input[index].rgb.green, input[index].rgb.blue};
        const WORD out[3]{output[index].rgb.red, output[index].rgb.green, output[index].rgb.blue};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            table[(index * 3U) + channel] = static_cast<float>(out[channel]) / 65535.0F;
            largest_shift = std::max(largest_shift, std::abs(static_cast<int>(out[channel]) - static_cast<int>(in[channel])));
        }
    }
    table_ = std::move(table);
    // 8비트 두 단계(514) 안이면 항등으로 봅니다. ICM 은 sRGB→sRGB 에서도 어두운 끝 격자점을
    // 한 단계쯤 옮깁니다(2026-11-22 검증 PC 실측 1.04 단계, 7.97 → 9.0). 광색역 모니터는
    // 수십 단계가 벌어집니다.
    identity_ = largest_shift <= 514;
    return true;
}

void DisplayColorLut::map(const float rgb[3], float out[3]) const noexcept {
    if (table_.empty()) {
        out[0] = rgb[0];
        out[1] = rgb[1];
        out[2] = rgb[2];
        return;
    }
    std::uint32_t cell[3]{};
    float fraction[3]{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        const float position = std::clamp(rgb[channel], 0.0F, 1.0F) * kLastCell;
        cell[channel] = std::min(static_cast<std::uint32_t>(position), kGrid - 2U);
        fraction[channel] = position - static_cast<float>(cell[channel]);
    }
    tetrahedral(table_.data(), cell[0], cell[1], cell[2], fraction[0], fraction[1], fraction[2], out);
}

void DisplayColorLut::apply_bgra(
    const std::uint8_t* const source,
    const std::size_t source_stride_bytes,
    std::uint8_t* const destination,
    const std::size_t destination_stride_bytes,
    const std::uint32_t width,
    const std::uint32_t height) const noexcept {
    if (table_.empty() || source == nullptr || destination == nullptr || width == 0U || height == 0U) {
        return;
    }
    const CellTable& lookup = cells();
    const float* const table = table_.data();
    negaflow::core::for_each_row_block(
        height,
        static_cast<std::uint64_t>(width) * height * 8U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                const std::uint8_t* in = source + (static_cast<std::size_t>(y) * source_stride_bytes);
                std::uint8_t* out = destination + (static_cast<std::size_t>(y) * destination_stride_bytes);
                for (std::uint32_t x = 0U; x < width; ++x, in += 4, out += 4) {
                    const std::uint8_t b = in[0];
                    const std::uint8_t g = in[1];
                    const std::uint8_t r = in[2];
                    const std::uint8_t a = in[3];
                    float mapped[3]{};
                    tetrahedral(
                        table, lookup.cell[r], lookup.cell[g], lookup.cell[b],
                        lookup.fraction[r], lookup.fraction[g], lookup.fraction[b], mapped);
                    out[0] = to_byte(mapped[2]);
                    out[1] = to_byte(mapped[1]);
                    out[2] = to_byte(mapped[0]);
                    out[3] = a;
                }
            }
        });
}

}  // namespace negaflow::imaging
