#include "negaflow/output/export_metadata.h"

#include <wrl/client.h>

#include <string>

namespace negaflow::output {
namespace {

using Microsoft::WRL::ComPtr;

// TIFF 는 IFD 가 파일 뿌리에 있고 JPEG 은 APP1 안에 있다. 그 차이만 접두사로 흡수한다.
[[nodiscard]] const wchar_t* ifd_prefix(const ExportMetadataContainer container) noexcept {
    return container == ExportMetadataContainer::jpeg ? L"/app1/ifd" : L"/ifd";
}

/// 문자열 한 항목을 쓴다. 빈 값은 쓰지 않는다 — 빈 태그는 없느니만 못하다.
[[nodiscard]] bool write_text(
    IWICMetadataQueryWriter* const writer,
    const std::wstring& path,
    const std::wstring& value,
    std::uint32_t& native_error_code) noexcept {
    if (value.empty()) {
        return true;
    }
    PROPVARIANT variant{};
    PropVariantInit(&variant);
    variant.vt = VT_LPWSTR;
    // WIC 는 쓰기 동안만 이 버퍼를 읽는다. 소유권을 넘기지 않으므로 Clear 도 하지 않는다.
    variant.pwszVal = const_cast<wchar_t*>(value.c_str());
    const HRESULT status = writer->SetMetadataByName(path.c_str(), &variant);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return false;
    }
    return true;
}

[[nodiscard]] bool write_ushort(
    IWICMetadataQueryWriter* const writer,
    const std::wstring& path,
    const std::uint16_t value,
    std::uint32_t& native_error_code) noexcept {
    PROPVARIANT variant{};
    PropVariantInit(&variant);
    variant.vt = VT_UI2;
    variant.uiVal = value;
    const HRESULT status = writer->SetMetadataByName(path.c_str(), &variant);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return false;
    }
    return true;
}

/// macOS 는 `FilmType: x; FilmStock: y` 를 UserComment 에 넣는다. 같은 문자열을 만든다.
[[nodiscard]] std::wstring film_comment(
    const ExportMetadataFields& fields,
    const bool include_stock) {
    std::wstring comment;
    if (!fields.film_type.empty()) {
        comment.append(L"FilmType: ").append(fields.film_type);
    }
    if (include_stock && !fields.film_stock.empty()) {
        if (!comment.empty()) comment.append(L"; ");
        comment.append(L"FilmStock: ").append(fields.film_stock);
    }
    return comment;
}

}  // namespace

bool is_known_export_metadata_policy(const std::uint32_t value) noexcept {
    return value <= static_cast<std::uint32_t>(ExportMetadataPolicy::all);
}

ExportMetadataStatus write_export_metadata(
    IWICBitmapFrameEncode* const frame,
    const ExportMetadataContainer container,
    const ExportMetadataPolicy policy,
    const ExportMetadataFields& fields,
    std::uint32_t& native_error_code) noexcept {
    if (frame == nullptr) {
        return ExportMetadataStatus::write_failed;
    }

    ComPtr<IWICMetadataQueryWriter> writer{};
    const HRESULT acquired = frame->GetMetadataQueryWriter(&writer);
    if (FAILED(acquired) || writer == nullptr) {
        // PNG 인코더처럼 EXIF 를 받지 않는 컨테이너가 있다. 게시 자체를 막지는 않는다.
        native_error_code = static_cast<std::uint32_t>(acquired);
        return ExportMetadataStatus::unsupported;
    }

    const std::wstring ifd = ifd_prefix(container);
    const std::wstring exif = ifd + L"/exif";

    // 기하 변형은 픽셀에 구워져 있다. 뷰어가 한 번 더 돌리지 않도록 언제나 1 이다.
    if (!write_ushort(writer.Get(), ifd + L"/{ushort=274}", 1U, native_error_code)) {
        return ExportMetadataStatus::write_failed;
    }

    // 저작권만 남기기로 한 정책에서는 장비도 소프트웨어도 날짜도 적지 않는다.
    const bool identify_equipment = policy != ExportMetadataPolicy::copyright_only;

    struct Entry final {
        const wchar_t* path;
        const std::wstring* value;
        bool included;
    };

    const std::wstring comment =
        film_comment(fields, policy != ExportMetadataPolicy::minimal);

    const Entry entries[] = {
        // 저작권 표시는 어느 정책에서도 남긴다 — 지우는 것이 목적인 정책은 없다.
        {L"/{ushort=315}", &fields.artist, true},
        {L"/{ushort=33432}", &fields.copyright, true},
        {L"/{ushort=271}", &fields.make, identify_equipment},
        {L"/{ushort=272}", &fields.model, identify_equipment},
        {L"/{ushort=305}", &fields.software, identify_equipment},
        {L"/{ushort=306}", &fields.captured_at, identify_equipment},
    };
    for (const Entry& entry : entries) {
        if (!entry.included) continue;
        if (!write_text(writer.Get(), ifd + entry.path, *entry.value, native_error_code)) {
            return ExportMetadataStatus::write_failed;
        }
    }

    if (!identify_equipment) {
        return ExportMetadataStatus::ok;
    }

    // EXIF 하위 IFD. 촬영 시각은 두 태그가 같은 값을 갖는다 — 스캔은 디지털화 시각이
    // 곧 이 파일이 생긴 시각이고, 원본 촬영 시각은 알 수 없다.
    const Entry exif_entries[] = {
        {L"/{ushort=36867}", &fields.captured_at, true},   // DateTimeOriginal
        {L"/{ushort=36868}", &fields.captured_at, true},   // DateTimeDigitized
        {L"/{ushort=37510}", &comment, true},              // UserComment
    };
    for (const Entry& entry : exif_entries) {
        if (!write_text(writer.Get(), exif + entry.path, *entry.value, native_error_code)) {
            return ExportMetadataStatus::write_failed;
        }
    }
    return ExportMetadataStatus::ok;
}

}  // namespace negaflow::output
