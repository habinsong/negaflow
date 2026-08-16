#pragma once

#include "negaflow/output/export_metadata.h"

#include <cstdint>
#include <string>

namespace negaflow::output::detail {

/// 원본에서 읽는 동안 어느 덩이 안에 있는지. 걸러내는 규칙이 덩이마다 다르다.
enum class SourceMetadataBlock : std::uint8_t {
    root,
    exif,
    gps,
    iptc,
    other,
};

/// WIC 가 열거한 이름이 어느 덩이를 가리키는가. TIFF 는 이름이 아니라 가리키는 태그
/// 번호로 나온다 — `/exif` 가 아니라 `/{ushort=34665}` 다.
[[nodiscard]] SourceMetadataBlock source_block_of(const std::wstring& name);

/// 이 덩이 안으로 들어갈 것인가.
[[nodiscard]] bool enters_source_block(
    ExportMetadataPolicy policy,
    SourceMetadataBlock block) noexcept;

/// 이 잎을 옮길 것인가. 정책과 덩이만 보고 정한다.
[[nodiscard]] bool copies_source_leaf(
    ExportMetadataPolicy policy,
    SourceMetadataBlock block,
    const std::wstring& name);

}  // namespace negaflow::output::detail
