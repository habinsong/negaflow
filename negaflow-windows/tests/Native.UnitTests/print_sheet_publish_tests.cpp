#include "negaflow/output/print_sheet_publish.h"
#include "negaflow/color/output_color_space.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

// 인화 판 게시의 두 가지를 증명합니다.
//
//  - **심도**: 16-bit 로 넣은 계조가 파일에서 그대로 나오는가. 앞 판은 BGRA8 로 합성해서
//    16-bit TIFF/PNG 를 골라도 8-bit 로 접힌 판이 나왔습니다 - 인접한 두 코드값이 같은 값이
//    되면 그것이 그 증거입니다.
//  - **프로파일**: 랩이 준 ICC 바이트가 최종 파일에 한 바이트도 다르지 않게 박히는가. 앞 판은
//    중간 현상본에만 걸고 최종 파일에는 걸지 않아, 받는 쪽이 sRGB 로 읽었습니다.

namespace {

int failures = 0;
using Microsoft::WRL::ComPtr;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void report(const negaflow::output::PrintSheetPublishResult& result, const char* const label) {
    std::cerr << "  " << label << " status="
              << negaflow::output::print_sheet_publish_status_name(result.status)
              << " native=0x" << std::hex << result.native_error_code << std::dec
              << " bits=" << result.info.bits_per_sample
              << " icc=" << result.info.color_profile_bytes << '\n';
}

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-print-sheet-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary print sheet directory is created");
    }
    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;
    ~TempDirectory() {
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
    }
    [[nodiscard]] const std::filesystem::path& path() const noexcept { return path_; }

private:
    std::filesystem::path path_{};
};

constexpr std::uint32_t kWidth = 8U;
constexpr std::uint32_t kHeight = 4U;

// 8-bit 로 접히면 무너지는 계조입니다. 한 행 안에서 코드값이 1 씩만 움직이므로, 8-bit 를
// 지나면 여덟 화소가 모두 같은 값이 됩니다.
std::vector<std::uint16_t> make_page() {
    std::vector<std::uint16_t> page(
        static_cast<std::size_t>(kWidth) * kHeight * 3U, 0U);
    for (std::uint32_t y = 0U; y < kHeight; ++y) {
        for (std::uint32_t x = 0U; x < kWidth; ++x) {
            const std::size_t at =
                ((static_cast<std::size_t>(y) * kWidth) + x) * 3U;
            page[at] = static_cast<std::uint16_t>(1000U + x);            // 암부 ramp
            page[at + 1] = static_cast<std::uint16_t>(30000U + (x * 3U));
            page[at + 2] = static_cast<std::uint16_t>(65000U + x);       // 하이라이트 ramp
        }
    }
    return page;
}

struct ReadBack final {
    bool opened{false};
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::wstring pixel_format{};
    double dpi_x{0.0};
    std::vector<std::uint8_t> profile{};
    std::vector<std::uint16_t> samples{};
    bool is_rgb48{false};
};

ReadBack read_back(const std::filesystem::path& path, const bool decode_pixels) {
    ReadBack out{};
    ComPtr<IWICImagingFactory2> factory{};
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory2, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
        return out;
    }
    ComPtr<IWICBitmapDecoder> decoder{};
    if (FAILED(factory->CreateDecoderFromFilename(
            path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))) {
        return out;
    }
    ComPtr<IWICBitmapFrameDecode> frame{};
    if (FAILED(decoder->GetFrame(0U, &frame))) {
        return out;
    }
    out.opened = true;
    frame->GetSize(&out.width, &out.height);
    double dpi_y = 0.0;
    frame->GetResolution(&out.dpi_x, &dpi_y);

    WICPixelFormatGUID format{};
    if (SUCCEEDED(frame->GetPixelFormat(&format))) {
        out.is_rgb48 = IsEqualGUID(format, GUID_WICPixelFormat48bppRGB) != FALSE;
    }

    UINT context_count = 0U;
    if (SUCCEEDED(frame->GetColorContexts(0U, nullptr, &context_count)) && context_count == 1U) {
        ComPtr<IWICColorContext> context{};
        if (SUCCEEDED(factory->CreateColorContext(&context))) {
            IWICColorContext* raw = context.Get();
            UINT actual = 0U;
            UINT size = 0U;
            if (SUCCEEDED(frame->GetColorContexts(1U, &raw, &actual)) && actual == 1U &&
                SUCCEEDED(context->GetProfileBytes(0U, nullptr, &size)) && size != 0U) {
                out.profile.resize(size);
                UINT written = 0U;
                if (FAILED(context->GetProfileBytes(size, out.profile.data(), &written)) ||
                    written != size) {
                    out.profile.clear();
                }
            }
        }
    }

    if (decode_pixels && out.is_rgb48) {
        const std::uint32_t stride = out.width * 3U * 2U;
        std::vector<std::uint8_t> bytes(
            static_cast<std::size_t>(stride) * out.height, 0U);
        if (SUCCEEDED(frame->CopyPixels(
                nullptr, stride, static_cast<UINT>(bytes.size()), bytes.data()))) {
            out.samples.resize(bytes.size() / 2U);
            for (std::size_t index = 0U; index < out.samples.size(); ++index) {
                out.samples[index] = static_cast<std::uint16_t>(
                    bytes[index * 2U] | (bytes[(index * 2U) + 1U] << 8U));
            }
        }
    }
    return out;
}

void verify_sixteen_bit_round_trip(
    const TempDirectory& temp,
    const negaflow::output::PrintSheetFormat format,
    const wchar_t* const extension,
    const char* const label) {
    const std::vector<std::uint16_t> page = make_page();
    const std::filesystem::path destination =
        temp.path() / (std::wstring(L"sheet") + extension);
    negaflow::output::PrintSheetPublishLimits limits{};
    limits.output_dpi = 300U;
    const negaflow::output::PrintSheetPublishResult result =
        negaflow::output::publish_print_sheet(
            page, kWidth, kHeight, kWidth * 3U * 2U, destination, format, limits);
    if (result.status != negaflow::output::PrintSheetPublishStatus::ok) {
        report(result, label);
    }
    expect(result.status == negaflow::output::PrintSheetPublishStatus::ok, label);
    expect(result.info.bits_per_sample == 16U, "sixteen bit sheet reports sixteen bits");
    expect(result.info.published, "sixteen bit sheet is published");

    const ReadBack read = read_back(destination, true);
    expect(read.opened, "published sheet opens");
    expect(read.width == kWidth && read.height == kHeight, "published sheet keeps its size");
    expect(read.is_rgb48, "published sheet carries 48bpp RGB");
    expect(static_cast<int>(read.dpi_x + 0.5) == 300, "published sheet keeps 300 dpi");
    expect(read.samples.size() == page.size(), "published sheet returns every sample");
    // 화소가 하나도 어긋나면 안 됩니다 - 무손실 컨테이너이고 색 변환도 없습니다.
    expect(read.samples == page, "published sheet keeps every sixteen bit code exactly");
    // 8-bit 로 접혔다면 한 행의 여덟 화소가 모두 같아졌을 것입니다.
    expect(
        read.samples.size() >= 22U && read.samples[0] != read.samples[21U],
        "published sheet did not collapse the dark ramp to eight bits");
}

void verify_output_profile_is_attached(const TempDirectory& temp) {
    const std::vector<std::uint16_t> page = make_page();
    // 랩이 준 프로파일 자리에 Adobe RGB 를 씁니다. 시스템 sRGB 와 확실히 다른 바이트라서
    // "그냥 기본 프로파일이 붙었다" 와 구분됩니다.
    const std::vector<std::uint8_t> lab_profile =
        negaflow::color::build_icc_profile(negaflow::color::OutputColorSpace::adobe_rgb);
    expect(lab_profile.size() >= 128U, "the stand-in lab profile is built");

    for (const auto& entry : {
             std::pair{negaflow::output::PrintSheetFormat::png16, L".png"},
             std::pair{negaflow::output::PrintSheetFormat::tiff16, L".tif"},
             std::pair{negaflow::output::PrintSheetFormat::jpeg8, L".jpg"},
         }) {
        const std::filesystem::path destination =
            temp.path() / (std::wstring(L"profiled") + entry.second);
        negaflow::output::PrintSheetPublishLimits limits{};
        limits.output_dpi = 300U;
        limits.jpeg_quality = 1.0F;
        limits.output_icc_profile = lab_profile;
        const negaflow::output::PrintSheetPublishResult result =
            negaflow::output::publish_print_sheet(
                page, kWidth, kHeight, kWidth * 3U * 2U, destination, entry.first, limits);
        if (result.status != negaflow::output::PrintSheetPublishStatus::ok) {
            report(result, "profiled sheet");
        }
        expect(
            result.status == negaflow::output::PrintSheetPublishStatus::ok,
            "the sheet publishes with the chosen output profile");
        expect(
            result.info.color_profile_bytes == lab_profile.size(),
            "the published sheet reports the chosen profile size");
        expect(
            result.info.bits_per_sample ==
                (entry.first == negaflow::output::PrintSheetFormat::jpeg8 ? 8U : 16U),
            "the format decides the published depth");

        const ReadBack read = read_back(destination, false);
        expect(read.opened, "the profiled sheet opens");
        expect(
            read.profile == lab_profile,
            "the published file carries the chosen profile byte for byte");
    }
}

void verify_refusals(const TempDirectory& temp) {
    const std::vector<std::uint16_t> page = make_page();
    const std::filesystem::path destination = temp.path() / L"refusals.png";

    negaflow::output::PrintSheetPublishLimits limits{};
    expect(
        negaflow::output::publish_print_sheet(
            page, 0U, kHeight, kWidth * 3U * 2U, destination,
            negaflow::output::PrintSheetFormat::png16, limits).status ==
            negaflow::output::PrintSheetPublishStatus::invalid_dimensions,
        "a zero width sheet is refused");
    expect(
        negaflow::output::publish_print_sheet(
            page, kWidth, kHeight, (kWidth * 3U * 2U) - 2U, destination,
            negaflow::output::PrintSheetFormat::png16, limits).status ==
            negaflow::output::PrintSheetPublishStatus::buffer_size_mismatch,
        "a stride narrower than one row is refused");
    expect(
        negaflow::output::publish_print_sheet(
            std::span<const std::uint16_t>(page.data(), page.size() - 3U),
            kWidth, kHeight, kWidth * 3U * 2U, destination,
            negaflow::output::PrintSheetFormat::png16, limits).status ==
            negaflow::output::PrintSheetPublishStatus::buffer_size_mismatch,
        "a short buffer is refused instead of read past");

    negaflow::output::PrintSheetPublishLimits tight{};
    tight.max_encoded_pixel_bytes = 8U;
    expect(
        negaflow::output::publish_print_sheet(
            page, kWidth, kHeight, kWidth * 3U * 2U, destination,
            negaflow::output::PrintSheetFormat::png16, tight).status ==
            negaflow::output::PrintSheetPublishStatus::memory_limit_exceeded,
        "a sheet larger than the budget is refused");

    // 파일이 이미 있으면 대체하지 않습니다. 인화 판이 남의 파일을 덮으면 안 됩니다.
    expect(
        negaflow::output::publish_print_sheet(
            page, kWidth, kHeight, kWidth * 3U * 2U, destination,
            negaflow::output::PrintSheetFormat::png16, limits).status ==
            negaflow::output::PrintSheetPublishStatus::ok,
        "the first sheet publishes");
    expect(
        negaflow::output::publish_print_sheet(
            page, kWidth, kHeight, kWidth * 3U * 2U, destination,
            negaflow::output::PrintSheetFormat::png16, limits).status ==
            negaflow::output::PrintSheetPublishStatus::destination_exists,
        "an existing file is never replaced");
    // 거절된 게시가 임시 파일을 남기지 않습니다.
    std::size_t leftovers = 0U;
    for (const auto& entry : std::filesystem::directory_iterator(temp.path())) {
        if (entry.path().extension() == L".tmp") {
            ++leftovers;
        }
    }
    expect(leftovers == 0U, "a refused publish leaves no staging file behind");
}

}  // namespace

int main() {
    const HRESULT apartment = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(apartment)) {
        std::cerr << "FAIL: COM apartment\n";
        return 1;
    }
    {
        TempDirectory temp{};
        verify_sixteen_bit_round_trip(
            temp, negaflow::output::PrintSheetFormat::png16, L".png", "a 16-bit PNG sheet publishes");
        verify_sixteen_bit_round_trip(
            temp, negaflow::output::PrintSheetFormat::tiff16, L".tif", "a 16-bit TIFF sheet publishes");
        verify_output_profile_is_attached(temp);
        verify_refusals(temp);
    }
    CoUninitialize();
    if (failures == 0) {
        std::cout << "print_sheet_publish tests passed\n";
    }
    return failures == 0 ? 0 : 1;
}
