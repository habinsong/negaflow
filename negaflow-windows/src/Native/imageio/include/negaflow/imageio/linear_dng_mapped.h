#pragma once

#include "negaflow/imageio/decoded_image.h"

#include <cstdint>
#include <filesystem>
#include <stop_token>

namespace negaflow::imageio {

/// 필름 스캐너의 선형 DNG 를 LibRaw 의 unpack 없이 메모리 매핑으로 바로 읽어 프리뷰 상자로
/// 줄입니다.
///
/// 이런 DNG(LinearRaw · 16 bit · 3 채널 · 무압축 스트립, 검정 0 · 흰색 65535)는 LibRaw 가 표본을
/// 그대로 옮길 뿐인데, 그 unpack 이 530 MB 파일을 읽어 화소당 8 바이트로 펼치느라 장당 400~480 ms
/// 를 썼습니다. 매핑한 파일에서 곧바로 면적 평균을 내면 같은 화소가 73~102 ms 에 나옵니다(이
/// 기계 실측 네 장, LibRaw 길과 비트 단위로 같음). 면적 평균은 브리지의
/// `negaflow_libraw_make_linear_preview` 와 같은 가중치·같은 누적 순서입니다.
///
/// 파일 구조가 조금이라도 다르면(타일, 압축, 선형화 표, 크기 불일치 …) false 를 돌려주고 아무것도
/// 바꾸지 않습니다 — 호출자는 LibRaw 길로 갑니다. 검정·흰색·여백 같은 값의 판정은 호출자가 LibRaw
/// 머리(`negaflow_libraw_linear_header`)로 이미 했습니다. 매핑은 함수 안에서 열고 닫으므로 파일을
/// 붙잡지 않습니다.
///
/// `source_row_step` 이 1 보다 크면 **임시 첫 화면**입니다. 원본 행을 그 간격으로만 읽어(나머지 행은
/// 페이지조차 건드리지 않습니다) 읽는 양을 그만큼 줄이고, 읽은 행끼리 같은 면적 가중치로 평균합니다.
/// 정착 결과(1)와 화소가 다르므로 호출자는 캐시에 담지 않습니다.
enum class LinearDngMappedStatus : std::uint8_t {
    ok = 0,
    // 이 길로 읽을 수 없는 파일입니다. LibRaw 길로 가면 됩니다.
    not_applicable,
    cancelled,
};

[[nodiscard]] LinearDngMappedStatus decode_linear_dng_mapped(
    const std::filesystem::path& path,
    std::uint32_t expected_width,
    std::uint32_t expected_height,
    int flip,
    std::uint32_t target_width,
    std::uint32_t target_height,
    std::stop_token stop_token,
    DecodedImage& destination,
    std::uint32_t source_row_step = 1U) noexcept;

}  // namespace negaflow::imageio
