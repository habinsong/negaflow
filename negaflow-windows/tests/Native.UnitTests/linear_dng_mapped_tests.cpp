#include "negaflow/imageio/linear_dng_mapped.h"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <string>
#include <vector>

#include <windows.h>

namespace {

using negaflow::imageio::DecodedImage;
using negaflow::imageio::LinearDngMappedStatus;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

/// 필름 스캐너가 쓰는 모양의 선형 DNG(LinearRaw · 16 bit · 3 채널 · 무압축 한 스트립)입니다.
/// `sample(row, column, channel)` 이 원본 화소 값을 정합니다.
class TiffWriter final {
public:
    explicit TiffWriter(const bool little) : little_(little) {}

    void u16(const std::uint16_t value) {
        if (little_) {
            bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
            bytes.push_back(static_cast<std::uint8_t>(value >> 8U));
        } else {
            bytes.push_back(static_cast<std::uint8_t>(value >> 8U));
            bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
        }
    }

    void u32(const std::uint32_t value) {
        if (little_) {
            u16(static_cast<std::uint16_t>(value & 0xFFFFU));
            u16(static_cast<std::uint16_t>(value >> 16U));
        } else {
            u16(static_cast<std::uint16_t>(value >> 16U));
            u16(static_cast<std::uint16_t>(value & 0xFFFFU));
        }
    }

    void short_entry(const std::uint16_t tag, const std::uint16_t value) {
        u16(tag);
        u16(3U);
        u32(1U);
        u16(value);
        u16(0U);
    }

    void long_entry(const std::uint16_t tag, const std::uint32_t value) {
        u16(tag);
        u16(4U);
        u32(1U);
        u32(value);
    }

    std::vector<std::uint8_t> bytes{};

private:
    bool little_;
};

[[nodiscard]] std::vector<std::uint8_t> linear_dng(
    const bool little,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint16_t compression,
    const std::function<std::uint16_t(std::uint32_t, std::uint32_t, int)>& sample) {
    TiffWriter tiff{little};
    tiff.bytes.push_back(little ? 'I' : 'M');
    tiff.bytes.push_back(little ? 'I' : 'M');
    tiff.u16(42U);
    tiff.u32(8U);
    constexpr std::uint16_t entries = 11U;
    const std::uint32_t bits_offset = 8U + 2U + entries * 12U + 4U;
    const std::uint32_t data_offset = bits_offset + 6U;
    const std::uint32_t data_bytes = width * height * 6U;
    tiff.u16(entries);
    tiff.long_entry(254U, 0U);
    tiff.long_entry(256U, width);
    tiff.long_entry(257U, height);
    tiff.u16(258U);
    tiff.u16(3U);
    tiff.u32(3U);
    tiff.u32(bits_offset);
    tiff.short_entry(259U, compression);
    tiff.short_entry(262U, 34892U);
    tiff.long_entry(273U, data_offset);
    tiff.short_entry(277U, 3U);
    tiff.long_entry(278U, height);
    tiff.long_entry(279U, data_bytes);
    tiff.short_entry(284U, 1U);
    tiff.u32(0U);
    tiff.u16(16U);
    tiff.u16(16U);
    tiff.u16(16U);
    for (std::uint32_t row = 0U; row < height; ++row) {
        for (std::uint32_t column = 0U; column < width; ++column) {
            for (int channel = 0; channel < 3; ++channel) {
                tiff.u16(sample(row, column, channel));
            }
        }
    }
    return tiff.bytes;
}

/// 빨강은 원본 행 × 10, 초록은 원본 열, 파랑은 1000 입니다 — 어느 행을 읽었는지가 빨강에 남습니다.
[[nodiscard]] std::uint16_t row_marked(const std::uint32_t row, const std::uint32_t column, const int channel) {
    return static_cast<std::uint16_t>(channel == 0 ? row * 10U : (channel == 1 ? column : 1000U));
}

struct Decoded final {
    LinearDngMappedStatus status{LinearDngMappedStatus::not_applicable};
    DecodedImage image{};
};

[[nodiscard]] Decoded decode(const std::vector<std::uint8_t>& file, const std::uint32_t width,
                             const std::uint32_t height, const int flip, const std::uint32_t target_width,
                             const std::uint32_t target_height, const std::uint32_t row_step) {
    static int serial = 0;
    const std::filesystem::path path = std::filesystem::temp_directory_path() /
        ("negaflow-linear-dng-mapped-" + std::to_string(::GetCurrentProcessId()) + "-" +
         std::to_string(++serial) + ".dng");
    {
        std::ofstream out{path, std::ios::binary};
        out.write(reinterpret_cast<const char*>(file.data()), static_cast<std::streamsize>(file.size()));
    }
    Decoded decoded{};
    decoded.status = negaflow::imageio::decode_linear_dng_mapped(
        path, width, height, flip, target_width, target_height, std::stop_token{}, decoded.image, row_step);
    std::error_code ignored{};
    std::filesystem::remove(path, ignored);
    return decoded;
}

[[nodiscard]] std::uint16_t at(const DecodedImage& image, const std::uint32_t x, const std::uint32_t y,
                               const int channel) {
    return image.samples[(static_cast<std::size_t>(y) * image.width + x) * 4U + static_cast<std::size_t>(channel)];
}

void settled_average_reads_every_row() {
    for (const bool little : {true, false}) {
        const std::string order = little ? "II" : "MM";
        const Decoded decoded = decode(linear_dng(little, 8U, 8U, 1U, row_marked), 8U, 8U, 0, 4U, 4U, 1U);
        expect(decoded.status == LinearDngMappedStatus::ok, order + " settled decode succeeds");
        if (decoded.status != LinearDngMappedStatus::ok) {
            continue;
        }
        expect(decoded.image.width == 4U && decoded.image.height == 4U, order + " settled size");
        bool rows_ok = true;
        bool columns_ok = true;
        for (std::uint32_t y = 0U; y < 4U; ++y) {
            for (std::uint32_t x = 0U; x < 4U; ++x) {
                // 행 2y, 2y+1 의 평균 = 20y + 5. 열 2x, 2x+1 의 평균 2x + 0.5 는 반올림해 2x + 1.
                rows_ok = rows_ok && at(decoded.image, x, y, 0) == 20U * y + 5U;
                columns_ok = columns_ok && at(decoded.image, x, y, 1) == 2U * x + 1U &&
                    at(decoded.image, x, y, 2) == 1000U && at(decoded.image, x, y, 3) == 65535U;
            }
        }
        expect(rows_ok, order + " settled average covers both rows of each window");
        expect(columns_ok, order + " settled columns, blue and alpha");
    }
}

void first_preview_reads_only_every_other_row() {
    const Decoded decoded = decode(linear_dng(true, 8U, 8U, 1U, row_marked), 8U, 8U, 0, 4U, 4U, 2U);
    expect(decoded.status == LinearDngMappedStatus::ok, "sampled decode succeeds");
    if (decoded.status != LinearDngMappedStatus::ok) {
        return;
    }
    bool rows_ok = true;
    bool columns_ok = true;
    for (std::uint32_t y = 0U; y < 4U; ++y) {
        for (std::uint32_t x = 0U; x < 4U; ++x) {
            // 창 {2y, 2y+1} 에서 짝수 행 2y 만 읽습니다.
            rows_ok = rows_ok && at(decoded.image, x, y, 0) == 20U * y;
            columns_ok = columns_ok && at(decoded.image, x, y, 1) == 2U * x + 1U &&
                at(decoded.image, x, y, 2) == 1000U;
        }
    }
    expect(rows_ok, "sampled preview averages only the kept source rows");
    expect(columns_ok, "sampled preview still averages every column");
}

void rotated_first_preview_samples_source_rows() {
    // 원본 8 × 4, flip 6(90° 시계 방향: 축 교환 + 원본 행 뒤집기) → 출력 4 × 8 을 2 × 4 로.
    const std::vector<std::uint8_t> file = linear_dng(true, 8U, 4U, 1U, row_marked);
    const Decoded settled = decode(file, 8U, 4U, 6, 2U, 4U, 1U);
    const Decoded sampled = decode(file, 8U, 4U, 6, 2U, 4U, 2U);
    expect(settled.status == LinearDngMappedStatus::ok, "rotated settled decode succeeds");
    expect(sampled.status == LinearDngMappedStatus::ok, "rotated sampled decode succeeds");
    if (settled.status != LinearDngMappedStatus::ok || sampled.status != LinearDngMappedStatus::ok) {
        return;
    }
    expect(settled.image.width == 2U && settled.image.height == 4U, "rotated size");
    bool ok = true;
    for (std::uint32_t y = 0U; y < 4U; ++y) {
        // 출력 열 0 은 원본 행 {3, 2}, 열 1 은 {1, 0} 입니다. 간격 2 면 원본 짝수 행만(2, 0) 남습니다.
        ok = ok && at(settled.image, 0U, y, 0) == 25U && at(settled.image, 1U, y, 0) == 5U;
        ok = ok && at(sampled.image, 0U, y, 0) == 20U && at(sampled.image, 1U, y, 0) == 0U;
        // 출력 행 y 는 원본 열 {2y, 2y+1} 입니다.
        ok = ok && at(settled.image, 0U, y, 1) == 2U * y + 1U && at(sampled.image, 1U, y, 1) == 2U * y + 1U;
    }
    expect(ok, "rotation maps the sampled axis to source rows");
}

void unsupported_files_fall_back() {
    expect(decode(linear_dng(true, 8U, 8U, 8U, row_marked), 8U, 8U, 0, 4U, 4U, 1U).status ==
               LinearDngMappedStatus::not_applicable,
        "compressed data is left to LibRaw");
    expect(decode(linear_dng(true, 8U, 8U, 1U, row_marked), 8U, 6U, 0, 4U, 4U, 1U).status ==
               LinearDngMappedStatus::not_applicable,
        "a size that differs from the LibRaw header is left to LibRaw");
    expect(decode(linear_dng(true, 8U, 8U, 1U, row_marked), 8U, 8U, 0, 16U, 16U, 1U).status ==
               LinearDngMappedStatus::not_applicable,
        "enlarging is not this path's job");
}

}  // namespace

int main() {
    settled_average_reads_every_row();
    first_preview_reads_only_every_other_row();
    rotated_first_preview_samples_source_rows();
    unsupported_files_fall_back();
    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "linear_dng_mapped: all checks passed\n";
    return 0;
}
