#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace negaflow::output::detail {

// DNG 는 TIFF 6.0 구조(8바이트 머리말 + IFD 목록)에 태그를 더한 형식입니다. 이 파일은 그 구조를
// 리틀엔디언으로 쌓는 작은 기록기이며 이미지 줄 데이터는 다루지 않습니다. 줄 데이터는 호출하는
// 쪽이 머리말 블록 뒤에 이어서 씁니다.
//
// TIFF 6.0 규격의 배치(IFD = 항목 수 + 12바이트 항목들 + 다음 IFD 오프셋, 4바이트를 넘는 값은
// 짝수 오프셋의 바깥 영역)만 따릅니다. macOS `TIFFStructure.swift` 와 같은 규칙입니다.

/// TIFF 6.0 필드 타입 코드(DNG·EXIF 가 같은 코드를 씁니다).
enum class TiffFieldType : std::uint16_t {
    byte = 1,
    ascii = 2,
    short_value = 3,
    long_value = 4,
    rational = 5,
    undefined = 7,
    signed_rational = 10,
    float32 = 11,
};

/// IFD 항목 하나. 값은 이미 리틀엔디언 바이트로 인코딩해 가집니다.
struct TiffEntry final {
    std::uint16_t tag{0U};
    TiffFieldType type{TiffFieldType::byte};
    std::uint32_t count{0U};
    std::vector<std::uint8_t> payload{};
};

[[nodiscard]] TiffEntry tiff_bytes(std::uint16_t tag, const std::vector<std::uint8_t>& values);
[[nodiscard]] TiffEntry tiff_undefined(std::uint16_t tag, const std::vector<std::uint8_t>& values);
[[nodiscard]] TiffEntry tiff_shorts(std::uint16_t tag, const std::vector<std::uint16_t>& values);
[[nodiscard]] TiffEntry tiff_longs(std::uint16_t tag, const std::vector<std::uint32_t>& values);
[[nodiscard]] TiffEntry tiff_floats(std::uint16_t tag, const std::vector<float>& values);
[[nodiscard]] TiffEntry tiff_rationals(
    std::uint16_t tag, const std::vector<std::pair<std::uint32_t, std::uint32_t>>& values);
[[nodiscard]] TiffEntry tiff_signed_rationals(
    std::uint16_t tag, const std::vector<std::pair<std::int32_t, std::int32_t>>& values);

/// 널로 끝나는 ASCII 문자열. 7비트 밖의 글자는 '?' 로 바꿉니다(TIFF ASCII 는 7비트 규격입니다).
[[nodiscard]] TiffEntry tiff_ascii(std::uint16_t tag, const std::wstring& text);
[[nodiscard]] TiffEntry tiff_ascii(std::uint16_t tag, const std::string& text);

/// 7비트 ASCII 바이트로 바꿉니다(널 종결 없음).
[[nodiscard]] std::vector<std::uint8_t> ascii_bytes(const std::wstring& text);

/// 이미지 줄 데이터 앞에 오는 블록: 머리말 + IFD0 + 바깥 값 영역 + (있으면) EXIF IFD.
///
/// - `exif` 가 비어 있지 않으면 IFD0 에 EXIF IFD 포인터(태그 34665)를 자동으로 넣습니다.
/// - 항목은 태그 번호 오름차순으로 정렬됩니다(TIFF 요구사항).
/// - 블록 크기는 값 내용이 아니라 항목의 개수·타입·개수에만 달려 있습니다. 호출하는 쪽은
///   줄 오프셋 자리에 임시 값을 넣어 한 번 만들어 크기를 잰 뒤 진짜 값으로 다시 만들면 됩니다.
[[nodiscard]] std::vector<std::uint8_t> make_tiff_header_block(
    std::vector<TiffEntry> ifd0,
    std::vector<TiffEntry> exif = {});

}  // namespace negaflow::output::detail
