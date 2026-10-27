// DNG 머리말 블록 기록기 시험. 블록을 기록기와 별개로 짠 최소 TIFF 해석기로 다시 읽는다.
// 이식 가능한 코드뿐이라 Windows 밖에서도 컴파일된다.
#include "dng_tiff_block.h"

#include <cstdint>
#include <iostream>
#include <map>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

std::uint32_t le32(const std::vector<std::uint8_t>& bytes, const std::size_t at) {
    return static_cast<std::uint32_t>(bytes[at]) | (static_cast<std::uint32_t>(bytes[at + 1U]) << 8U) |
           (static_cast<std::uint32_t>(bytes[at + 2U]) << 16U) |
           (static_cast<std::uint32_t>(bytes[at + 3U]) << 24U);
}

std::uint16_t le16(const std::vector<std::uint8_t>& bytes, const std::size_t at) {
    return static_cast<std::uint16_t>(bytes[at] | (bytes[at + 1U] << 8U));
}

struct ParsedEntry final {
    std::uint16_t type{0U};
    std::uint32_t count{0U};
    std::vector<std::uint8_t> value{};
};

constexpr std::size_t type_size(const std::uint16_t type) {
    switch (type) {
        case 3: return 2U;
        case 4: case 11: return 4U;
        case 5: case 10: return 8U;
        default: return 1U;
    }
}

std::map<std::uint16_t, ParsedEntry> parse_directory(
    const std::vector<std::uint8_t>& bytes, const std::size_t offset) {
    std::map<std::uint16_t, ParsedEntry> entries{};
    expect(offset % 2U == 0U, "IFD 는 짝수 오프셋이다");
    const std::size_t count = le16(bytes, offset);
    int previous = -1;
    for (std::size_t index = 0U; index < count; ++index) {
        const std::size_t at = offset + 2U + (index * 12U);
        ParsedEntry entry{};
        const std::uint16_t tag = le16(bytes, at);
        expect(static_cast<int>(tag) > previous, "IFD 항목은 태그 오름차순이다");
        previous = tag;
        entry.type = le16(bytes, at + 2U);
        entry.count = le32(bytes, at + 4U);
        const std::size_t size = entry.count * type_size(entry.type);
        std::size_t value_at = at + 8U;
        if (size > 4U) {
            value_at = le32(bytes, at + 8U);
            expect(value_at % 2U == 0U, "바깥 값은 짝수 오프셋이다");
        }
        entry.value.assign(bytes.begin() + static_cast<std::ptrdiff_t>(value_at),
                           bytes.begin() + static_cast<std::ptrdiff_t>(value_at + size));
        entries[tag] = std::move(entry);
    }
    expect(le32(bytes, offset + 2U + (count * 12U)) == 0U, "다음 IFD 가 없다");
    return entries;
}

}  // namespace

int main() {
    using namespace negaflow::output::detail;

    // 일부러 거꾸로 넣는다: 바깥 값(문자열·배열)과 인라인 값이 섞이고 EXIF IFD 가 붙는다.
    std::vector<TiffEntry> ifd0{
        tiff_ascii(305U, std::string{"Negaflow test build"}),
        tiff_longs(273U, {1000U, 2000U, 3000U}),
        tiff_shorts(258U, {16U, 16U, 16U}),
        tiff_shorts(259U, {1U}),
        tiff_bytes(50706U, {1U, 4U, 0U, 0U}),
        tiff_signed_rationals(50721U, {{-1, 1000000}, {2, 3}, {3, 1}, {4, 1}, {5, 1}, {6, 1}, {7, 1}, {8, 1}, {9, 1}}),
        tiff_floats(50940U, {0.0F, 0.0F, 1.0F, 1.0F}),
        tiff_ascii(306U, std::wstring{L"2023:11:14 22:13:20"}),
    };
    std::vector<TiffEntry> exif{
        tiff_undefined(37510U, {'A', 'S', 'C', 'I', 'I', 0U, 0U, 0U, 'h', 'i'}),
        tiff_ascii(36867U, std::string{"2023:11:14 22:13:20"}),
        tiff_undefined(36864U, {'0', '2', '3', '1'}),
    };
    const std::vector<std::uint8_t> block = make_tiff_header_block(ifd0, exif);

    expect(block.size() > 8U, "블록이 비어 있지 않다");
    expect(block[0] == 0x49U && block[1] == 0x49U && le16(block, 2U) == 42U, "II + 42 머리말");
    expect(le32(block, 4U) == 8U, "IFD0 는 머리말 바로 뒤다");

    const auto main = parse_directory(block, 8U);
    expect(main.size() == ifd0.size() + 1U, "항목 수 = 입력 + EXIF 포인터");
    expect(main.at(305U).type == 2U && main.at(305U).count == 20U, "ASCII 개수는 널을 포함한다");
    expect(std::string(main.at(305U).value.begin(), main.at(305U).value.end() - 1) == "Negaflow test build", "ASCII 값");
    expect(main.at(273U).count == 3U && le32(main.at(273U).value, 4U) == 2000U, "LONG 배열 값");
    expect(main.at(258U).count == 3U && le16(main.at(258U).value, 2U) == 16U, "SHORT 배열 값");
    expect(main.at(259U).count == 1U && le16(main.at(259U).value, 0U) == 1U, "인라인 SHORT");
    expect(main.at(50706U).value == std::vector<std::uint8_t>({1U, 4U, 0U, 0U}), "BYTE 4개는 인라인이다");
    expect(main.at(50721U).count == 9U, "SRATIONAL 9개");
    expect(static_cast<std::int32_t>(le32(main.at(50721U).value, 0U)) == -1, "음수 분자");
    expect(le32(main.at(50721U).value, 4U) == 1000000U, "분모");
    expect(main.at(50940U).count == 4U, "FLOAT 4개");
    expect(main.at(34665U).count == 1U, "EXIF 포인터가 자동으로 들어간다");

    const std::size_t exif_offset = le32(main.at(34665U).value, 0U);
    expect(exif_offset > 8U && exif_offset < block.size(), "EXIF 포인터가 블록 안을 가리킨다");
    const auto exif_entries = parse_directory(block, exif_offset);
    expect(exif_entries.size() == 3U, "EXIF IFD 항목 수");
    expect(exif_entries.at(36864U).value == std::vector<std::uint8_t>({'0', '2', '3', '1'}), "ExifVersion");
    expect(exif_entries.at(37510U).count == 10U, "UserComment 길이");

    // 크기는 값이 아니라 구성에만 달렸다: 값만 바꿔 만들면 크기가 같다.
    std::vector<TiffEntry> changed = ifd0;
    changed[1] = tiff_longs(273U, {7U, 8U, 9U});
    expect(make_tiff_header_block(changed, exif).size() == block.size(), "오프셋 값이 달라도 블록 크기는 같다");

    // 7비트 밖 글자는 '?' 로 바뀐다.
    const TiffEntry mixed = tiff_ascii(271U, std::wstring{L"Epson 엡손"});
    expect(mixed.payload.back() == 0U && mixed.payload[6] == '?', "ASCII 밖 글자는 ? 로 바뀐다");

    // EXIF 가 없으면 포인터 항목도 없다.
    const auto plain = parse_directory(make_tiff_header_block({tiff_shorts(259U, {1U})}), 8U);
    expect(plain.size() == 1U, "EXIF 가 없으면 포인터를 넣지 않는다");

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "dng_tiff_block_tests passed\n";
    return 0;
}
