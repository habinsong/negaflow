#include "develop_export_abi_test_support.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>
#include <vector>

namespace negaflow::develop_export_abi_tests {
namespace {

// 16비트 sRGB PNG 한 장의 채널 평균을 0..1 로 읽습니다. 화면과 파일을 견주려면
// 같은 척도가 필요합니다.
struct ChannelMean final {
    double red{0.0};
    double green{0.0};
    double blue{0.0};
};

[[nodiscard]] ChannelMean preview_mean(
    const std::vector<std::uint8_t>& pixels,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    ChannelMean mean{};
    const std::size_t count = static_cast<std::size_t>(width) * height;
    if (count == 0U) {
        return mean;
    }
    double sum_r = 0.0;
    double sum_g = 0.0;
    double sum_b = 0.0;
    for (std::size_t index = 0U; index < count; ++index) {
        const std::size_t at = index * 4U;
        if (at + 2U >= pixels.size()) {
            break;
        }
        // BGRA8.
        sum_b += static_cast<double>(pixels[at]);
        sum_g += static_cast<double>(pixels[at + 1U]);
        sum_r += static_cast<double>(pixels[at + 2U]);
    }
    const double total = static_cast<double>(count) * 255.0;
    mean.red = sum_r / total;
    mean.green = sum_g / total;
    mean.blue = sum_b / total;
    return mean;
}

} // namespace

// **화면과 파일은 같은 그림이어야 합니다.**
//
// 2026-08-30 이 불변식이 깨져 있었습니다. `publish` 의 내보내기 갈래가 GPU 에 머문
// 화소를 호스트로 내리지 않고 인코더에 넘겨, 인코더가 상주 **이전** 내용 — 곧 반전 전
// 네거티브 — 을 그대로 파일에 적었습니다. 미리보기는 `write_preview` 가 스스로 내리므로
// 멀쩡했고, 그래서 "앱에서는 제대로 보이는데 내보내기만 원본이 나온다" 였습니다.
//
// 현상 타깃에 따라 되고 안 되고가 갈린 것도 같은 이유입니다: `grade.cpp` 는
// `target_active` 일 때만 `flush_resident()` 를 부르므로 노리츠·SP3000·F135·HR·복원은
// 우연히 살아났고, 스캐너 프로파일 없는 MAIN·PRINT 만 무너졌습니다. 그래서 이 시험은
// **MAIN** 으로 돌립니다 — 우연히 통과하던 갈래가 아니라 무너지던 갈래입니다.
void test_preview_and_export_agree(const std::filesystem::path& source) {
    const std::filesystem::path destination =
        std::filesystem::temp_directory_path() /
        L"negaflow-abi-preview-export-parity.png";
    std::error_code ignored{};
    std::filesystem::remove(destination, ignored);

    const std::wstring source_text = source.wstring();
    const std::wstring destination_text = destination.wstring();

    constexpr std::uint32_t box = 256U;
    std::vector<std::uint8_t> pixels(
        static_cast<std::size_t>(box) * static_cast<std::size_t>(box) * 4U, 0U);

    nf_develop_export_request_v1 preview_request =
        make_request(source_text.c_str(), nullptr);
    nf_develop_export_result_v1 preview_result = make_result();
    expect(
        nf_develop_preview_v1(
            &preview_request,
            box,
            box,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            &preview_result) == NF_STATUS_OK,
        "the parity preview call is well formed");
    if (preview_result.succeeded == 0U) {
        std::cerr << "FAIL: parity preview failed at stage " << preview_result.failed_stage
                  << " with " << preview_result.failure_name << '\n';
        ++failures;
        return;
    }

    nf_develop_export_request_v1 export_request =
        make_request(source_text.c_str(), destination_text.c_str());
    nf_develop_export_result_v1 export_result = make_result();
    expect(
        nf_develop_export_v1(&export_request, &export_result) == NF_STATUS_OK,
        "the parity export call is well formed");
    if (export_result.succeeded == 0U) {
        std::cerr << "FAIL: parity export failed at stage " << export_result.failed_stage
                  << " with " << export_result.failure_name << '\n';
        ++failures;
        return;
    }

    const ChannelMean preview =
        preview_mean(pixels, preview_result.image_width, preview_result.image_height);

    // 필름 스캔은 네거티브입니다. 반전을 거친 양화는 어느 채널도 바닥에 붙지 않습니다.
    // 반전을 건너뛴 그림은 이 문턱 아래로 떨어집니다(실측: 실패하던 파일이 0.11 대).
    expect(
        preview.red > 0.20 && preview.green > 0.20 && preview.blue > 0.20,
        "the preview of a negative scan is a developed positive");

    const std::vector<std::uint8_t> published = decode_png_bgra8(
        destination, export_result.image_width, export_result.image_height);
    expect(!published.empty(), "the published file decodes back");
    if (published.empty()) {
        return;
    }
    const ChannelMean exported = preview_mean(
        published, export_result.image_width, export_result.image_height);
    const double worst = std::max({
        std::fabs(exported.red - preview.red),
        std::fabs(exported.green - preview.green),
        std::fabs(exported.blue - preview.blue),
    });

    // 미리보기는 축소본이고 파일은 원본 해상도이므로 정확히 같을 수는 없습니다.
    // 실측 차이는 0.03 아래였고, 반전을 통째로 건너뛰면 0.4 를 넘습니다.
    if (worst > 0.08) {
        std::cerr << "FAIL: preview and export disagree by " << worst
                  << " preview=(" << preview.red << ", " << preview.green << ", "
                  << preview.blue << ") export=(" << exported.red << ", "
                  << exported.green << ", " << exported.blue << ")\n";
        ++failures;
    } else {
        std::cout << "[parity] preview/export max channel delta " << worst << '\n';
    }

    std::filesystem::remove(destination, ignored);
}

} // namespace negaflow::develop_export_abi_tests
