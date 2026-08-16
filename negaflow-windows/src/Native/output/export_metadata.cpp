#include "negaflow/output/export_metadata.h"

#include "export_metadata_rules.h"

#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <string>
#include <string_view>

namespace negaflow::output {
namespace {

using Microsoft::WRL::ComPtr;

/// 옮기지 않는 TIFF IFD 태그. 원본의 크기·스트립 자리·색 프로파일을 그대로 베끼면 새 파일이
/// 자기 픽셀과 어긋난 표를 갖게 된다 — 이 값들은 인코더가 쓴 것이 옳다.
constexpr std::array<std::uint16_t, 30> structural_tiff_tags{
    254U,    // NewSubfileType
    255U,    // SubfileType
    256U,    // ImageWidth
    257U,    // ImageLength
    258U,    // BitsPerSample
    259U,    // Compression
    262U,    // PhotometricInterpretation
    266U,    // FillOrder
    273U,    // StripOffsets
    274U,    // Orientation — 기하는 픽셀에 구워져 있다
    277U,    // SamplesPerPixel
    278U,    // RowsPerStrip
    279U,    // StripByteCounts
    282U,    // XResolution
    283U,    // YResolution
    284U,    // PlanarConfiguration
    296U,    // ResolutionUnit
    317U,    // Predictor
    320U,    // ColorMap
    322U,    // TileWidth
    323U,    // TileLength
    324U,    // TileOffsets
    325U,    // TileByteCounts
    330U,    // SubIFDs
    338U,    // ExtraSamples
    339U,    // SampleFormat
    347U,    // JPEGTables
    34665U,  // ExifIFDPointer — 자리값이라 블록을 옮기면 인코더가 다시 쓴다
    34853U,  // GPSInfoIFDPointer
    34675U,  // ICCProfile — 출력의 색 프로파일은 우리가 정한다
};

/// 이름에서 구분 기호를 걷어내고 소문자로 만든다. IPTC 항목 이름은 WIC 판마다
/// `Sub-location` / `SubLocation` 처럼 표기가 갈리므로, 표기가 아니라 글자로 견준다.
[[nodiscard]] std::wstring normalized(const std::wstring_view name) {
    std::wstring result;
    result.reserve(name.size());
    for (const wchar_t character : name) {
        if (std::iswalnum(static_cast<std::wint_t>(character)) != 0) {
            result.push_back(static_cast<wchar_t>(
                std::towlower(static_cast<std::wint_t>(character))));
        }
    }
    return result;
}

/// IPTC 항목은 `/{str=By-line}` 처럼 열거된다. 껍데기를 벗기고 글자만 남긴다 —
/// 통째로 정규화하면 `strbyline` 이 되어 어떤 이름과도 맞지 않는다.
[[nodiscard]] std::wstring iptc_key(const std::wstring& name) {
    constexpr std::wstring_view prefix = L"/{str=";
    if (name.starts_with(prefix) && name.back() == L'}') {
        return normalized(std::wstring_view{name}.substr(
            prefix.size(), name.size() - prefix.size() - 1U));
    }
    return normalized(name);
}

/// 장소를 지우는 정책에서 뺄 IPTC 항목(macOS `locationIPTCKeys`).
[[nodiscard]] bool is_location_iptc(const std::wstring& normalized_name) noexcept {
    return normalized_name == L"city" || normalized_name == L"sublocation" ||
           normalized_name == L"provincestate" ||
           normalized_name == L"countryprimarylocationcode" ||
           normalized_name == L"countryprimarylocationname";
}

/// 저작권만 남기는 정책에서 남길 IPTC 항목(macOS `copyrightIPTCKeys`).
[[nodiscard]] bool is_copyright_iptc(const std::wstring& normalized_name) noexcept {
    return normalized_name == L"byline" || normalized_name == L"bylinetitle" ||
           normalized_name == L"credit" || normalized_name == L"source" ||
           normalized_name == L"copyrightnotice" ||
           normalized_name == L"rightsusageterms";
}

/// `/{ushort=315}` 에서 315 를 꺼낸다. 다른 모양이면 태그가 아니다.
[[nodiscard]] bool tiff_tag_of(const std::wstring& name, std::uint16_t& tag) noexcept {
    constexpr std::wstring_view prefix = L"/{ushort=";
    if (!name.starts_with(prefix) || name.back() != L'}') {
        return false;
    }
    std::uint32_t value = 0U;
    for (std::size_t index = prefix.size(); index + 1U < name.size(); ++index) {
        const wchar_t character = name[index];
        if (character < L'0' || character > L'9' || value > 6553U) {
            return false;
        }
        value = (value * 10U) + static_cast<std::uint32_t>(character - L'0');
    }
    tag = static_cast<std::uint16_t>(value);
    return true;
}

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

namespace detail {

/// WIC 는 TIFF 의 하위 덩이를 이름이 아니라 **가리키는 태그 번호**로 열거한다 —
/// `/exif` 가 아니라 `/{ushort=34665}` 다. JPEG 쪽 이름도 함께 받아 둔다.
SourceMetadataBlock source_block_of(const std::wstring& name) {
    std::uint16_t tag = 0U;
    if (tiff_tag_of(name, tag)) {
        switch (tag) {
            case 34665U: return SourceMetadataBlock::exif;
            case 34853U: return SourceMetadataBlock::gps;
            case 33723U: return SourceMetadataBlock::iptc;
            default: return SourceMetadataBlock::other;
        }
    }
    const std::wstring key = normalized(name);
    if (key == L"exif") return SourceMetadataBlock::exif;
    if (key == L"gps") return SourceMetadataBlock::gps;
    if (key == L"iptc") return SourceMetadataBlock::iptc;
    return SourceMetadataBlock::other;
}

/// 쓸 때는 WIC 가 알아듣는 이름을 쓴다. 번호로 가리키는 자리는 인코더가 스스로 채운다.
[[nodiscard]] const wchar_t* destination_segment(const SourceMetadataBlock block) noexcept {
    switch (block) {
        case SourceMetadataBlock::exif: return L"/exif";
        case SourceMetadataBlock::gps: return L"/gps";
        case SourceMetadataBlock::iptc: return L"/iptc";
        default: return nullptr;
    }
}

bool copies_source_leaf(
    const ExportMetadataPolicy policy,
    const SourceMetadataBlock block,
    const std::wstring& name) {
    if (block == SourceMetadataBlock::root) {
        std::uint16_t tag = 0U;
        if (!tiff_tag_of(name, tag)) {
            // 태그 모양이 아니면 무엇인지 모르는 항목이다. 모르는 것은 옮기지 않는다.
            return false;
        }
        if (std::ranges::find(structural_tiff_tags, tag) != structural_tiff_tags.end()) {
            return false;
        }
        if (policy == ExportMetadataPolicy::copyright_only) {
            return tag == 315U || tag == 33432U;  // Artist, Copyright
        }
        return true;
    }
    if (block == SourceMetadataBlock::iptc) {
        const std::wstring key = iptc_key(name);
        if (policy == ExportMetadataPolicy::copyright_only) {
            return is_copyright_iptc(key);
        }
        if (policy == ExportMetadataPolicy::remove_location) {
            return !is_location_iptc(key);
        }
        return true;
    }
    // exif 와 gps 는 정책이 여기까지 들여보냈다면 통째로 옮긴다. 들어올 수 있는지는
    // `enters_block` 이 이미 정했다 — gps 는 `all` 에서만 들어온다.
    return block == SourceMetadataBlock::exif || block == SourceMetadataBlock::gps;
}

bool enters_source_block(
    const ExportMetadataPolicy policy,
    const SourceMetadataBlock block) noexcept {
    switch (block) {
        case SourceMetadataBlock::exif:
            // 저작권만 남기는 정책은 촬영 기록을 통째로 뺀다.
            return policy != ExportMetadataPolicy::copyright_only;
        case SourceMetadataBlock::gps:
            // 장소는 `all` 에서만 남는다. macOS 도 나머지 정책에서 GPS 를 빼 버린다.
            return policy == ExportMetadataPolicy::all;
        case SourceMetadataBlock::iptc:
            return true;
        default:
            return false;
    }
}

}  // namespace detail

namespace {

using detail::copies_source_leaf;
using detail::enters_source_block;
using detail::source_block_of;
using detail::SourceMetadataBlock;

void copy_block(
    IWICMetadataQueryReader* const reader,
    IWICMetadataQueryWriter* const writer,
    const std::wstring& destination_prefix,
    const ExportMetadataPolicy policy,
    const SourceMetadataBlock block,
    const std::uint32_t depth) noexcept {
    // 원본이 스스로를 가리키는 파일이라도 여기서 멈춘다.
    constexpr std::uint32_t maximum_depth = 4U;
    if (reader == nullptr || depth > maximum_depth) {
        return;
    }
    ComPtr<IEnumString> names{};
    if (FAILED(reader->GetEnumerator(&names)) || names == nullptr) {
        return;
    }
    LPOLESTR raw_name = nullptr;
    ULONG fetched = 0U;
    while (names->Next(1U, &raw_name, &fetched) == S_OK && fetched == 1U) {
        const std::wstring name = raw_name != nullptr ? raw_name : L"";
        CoTaskMemFree(raw_name);
        raw_name = nullptr;
        if (name.empty()) {
            continue;
        }
        PROPVARIANT value{};
        PropVariantInit(&value);
        if (FAILED(reader->GetMetadataByName(name.c_str(), &value))) {
            static_cast<void>(PropVariantClear(&value));
            continue;
        }
        if (value.vt == VT_UNKNOWN && value.punkVal != nullptr) {
            ComPtr<IWICMetadataQueryReader> nested{};
            if (SUCCEEDED(value.punkVal->QueryInterface(IID_PPV_ARGS(&nested)))) {
                const SourceMetadataBlock child = source_block_of(name);
                const wchar_t* const segment = destination_segment(child);
                if (segment != nullptr && enters_source_block(policy, child)) {
                    copy_block(
                        nested.Get(),
                        writer,
                        destination_prefix + segment,
                        policy,
                        child,
                        depth + 1U);
                }
            }
        } else if (copies_source_leaf(policy, block, name)) {
            // 실패해도 게시를 접지 않는다. 원본의 어떤 항목을 이 컨테이너가 못 받는 것은
            // 사용자가 고른 정책을 어긴 것이 아니다.
            static_cast<void>(
                writer->SetMetadataByName((destination_prefix + name).c_str(), &value));
        }
        static_cast<void>(PropVariantClear(&value));
    }
}

/// 원본 파일의 메타데이터를 정책대로 걸러 옮긴다. macOS `ExportSourceMetadata` 와 같은
/// 규칙이며, 앱이 아는 값보다 **먼저** 쓴다 — 겹치면 앱이 아는 값이 이긴다.
void copy_source_metadata(
    IWICMetadataQueryWriter* const writer,
    const std::wstring& destination_ifd,
    const ExportMetadataPolicy policy,
    const std::wstring& source_path) noexcept {
    ComPtr<IWICImagingFactory> factory{};
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory))) ||
        factory == nullptr) {
        return;
    }
    ComPtr<IWICBitmapDecoder> decoder{};
    if (FAILED(factory->CreateDecoderFromFilename(
            source_path.c_str(),
            nullptr,
            GENERIC_READ,
            WICDecodeMetadataCacheOnDemand,
            &decoder)) ||
        decoder == nullptr) {
        return;
    }
    ComPtr<IWICBitmapFrameDecode> frame{};
    if (FAILED(decoder->GetFrame(0U, &frame)) || frame == nullptr) {
        return;
    }
    ComPtr<IWICMetadataQueryReader> root{};
    if (FAILED(frame->GetMetadataQueryReader(&root)) || root == nullptr) {
        return;
    }

    // 컨테이너마다 IFD 가 앉는 자리가 다르다. 원본이 무엇이든 우리 IFD 로 옮긴다.
    for (const wchar_t* const candidate : {L"/ifd", L"/app1/ifd"}) {
        PROPVARIANT value{};
        PropVariantInit(&value);
        if (SUCCEEDED(root->GetMetadataByName(candidate, &value)) &&
            value.vt == VT_UNKNOWN && value.punkVal != nullptr) {
            ComPtr<IWICMetadataQueryReader> ifd{};
            if (SUCCEEDED(value.punkVal->QueryInterface(IID_PPV_ARGS(&ifd)))) {
                copy_block(
                    ifd.Get(), writer, destination_ifd, policy, SourceMetadataBlock::root, 0U);
                static_cast<void>(PropVariantClear(&value));
                return;
            }
        }
        static_cast<void>(PropVariantClear(&value));
    }
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

    // 원본에서 가져올 것을 **먼저** 쓴다. 뒤에 쓰는 앱의 값이 같은 태그를 덮으므로,
    // 겹치는 자리에서는 앱이 아는 값이 이긴다 — macOS 와 같은 우선순위다.
    if (policy != ExportMetadataPolicy::minimal && !fields.source_path.empty()) {
        copy_source_metadata(writer.Get(), ifd, policy, fields.source_path);
    }

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
    // 시각은 UTC 로 적으므로 오프셋도 함께 적는다. 오프셋 없는 EXIF 시각은 읽는 쪽이
    // 제 시간대로 해석해 몇 시간씩 어긋난다 — macOS 도 세 태그를 같이 쓴다.
    const std::wstring utc_offset = fields.captured_at.empty() ? std::wstring{} : L"+00:00";
    const Entry exif_entries[] = {
        {L"/{ushort=36867}", &fields.captured_at, true},   // DateTimeOriginal
        {L"/{ushort=36868}", &fields.captured_at, true},   // DateTimeDigitized
        {L"/{ushort=36880}", &utc_offset, true},           // OffsetTime
        {L"/{ushort=36881}", &utc_offset, true},           // OffsetTimeOriginal
        {L"/{ushort=36882}", &utc_offset, true},           // OffsetTimeDigitized
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
