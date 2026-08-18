// CPU/GPU 동치 시험 — 스캐너 타겟 프로파일 그레이드.
//
// ☠️ **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_scanner_target_grade` 를
//    그대로 부르고 그 결과와 겨룹니다. 프로파일 표도 진짜 것이 쓰입니다.
//
// ☠️ **엔진에서 가장 비싼 커널이고, 가장 긴 사슬입니다.** 화소마다 Lab 왕복 세 번 ×
//    정방향/역방향 두 번 + `atan2`·`log`·`exp`·`pow`·`fmod`. CPU 는 그 안이 `double`
//    이고 GPU 는 float 이므로 **다른 커널보다 오차가 큽니다.** 이 시험은 그 값을
//    허용치로 고정하는 것이 목적이고, 허용치는 실측으로 정합니다.
//
// 왜 스타일마다 도는가 — 프로파일 표가 스타일마다 다릅니다. 하나만 보면 색상 앵커
// 개수·중성 빈 개수 같은 분기가 우연히 한 갈래만 돌아갑니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::ScannerTargetGradeInfo;
using negaflow::imaging::ScannerTargetStyle;
using negaflow::pipeline::GpuAccelerator;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// ☠️ **허용치가 둘입니다. 이유가 다릅니다.**
//
// ① **누적 오차** — 사슬이 길고(Lab 왕복 세 번 × 정방향/역방향) CPU 는 그 안이
//    `double` 입니다. 이것은 화소마다 조금씩 쌓이는 종류이고, 실측 상한이 1e-4 입니다.
//
// ② **게이트 뒤집힘** — NORITSU 장치 질감에는 **하드 게이트**가 있습니다:
//    `low < 0 || high > 1` 이면 화소를 통째로 통과시킵니다
//    (`scanner_target_grade.cpp` `apply_noritsu_texture`). 그 경계에 정확히 앉은
//    화소는 1ulp 차이로 "질감을 얹는다/안 얹는다" 가 갈리고, 그때 차이는 **누적 오차가
//    아니라 질감 자체의 크기**입니다. 그래서 최대치만 재면 뜻이 없고, **몇 화소가
//    그러는지**를 같이 묶어야 계약이 됩니다.
//
// ☠️ **이 숫자들을 근거 없이 올리지 마십시오.** 올려야 한다면 먼저 "누적이 커진 것인가,
//    게이트가 더 많이 뒤집힌 것인가" 를 가르십시오 — 시험이 최악 화소의 입력 밝기와
//    이탈 화소 수를 찍는 이유가 그것입니다.
constexpr float accumulation_tolerance = 1.0e-4F;
// 게이트가 뒤집힌 화소에서만 나오는 값입니다. 질감의 진폭이 그 상한입니다.
constexpr float gate_flip_tolerance = 5.0e-3F;
// 게이트 경계는 이미지의 **가느다란 등고선**입니다. 그보다 넓게 벌어지면 게이트가 아니라
// 다른 것이 깨진 것입니다.
constexpr double gate_flip_pixel_fraction = 0.02;
constexpr std::uint32_t width = 320U;
constexpr std::uint32_t height = 200U;

// 색상환을 한 바퀴 돌고 밝기를 훑습니다 — 색상 앵커·중성 빈·채도 밴드가 전부
// 자기 구간을 지나가야 의미가 있습니다. 도메인 게이트(0.02/0.98)의 안팎도 지납니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float hue = static_cast<float>(x) / static_cast<float>(width);
            const float level = static_cast<float>(y) / static_cast<float>(height - 1U);
            const float angle = hue * 6.2831853F;
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                std::clamp(level * (0.5F + (0.5F * std::sin(angle))), 0.0F, 1.0F),
                std::clamp(level * (0.5F + (0.5F * std::sin(angle + 2.0944F))), 0.0F, 1.0F),
                std::clamp(level * (0.5F + (0.5F * std::sin(angle + 4.1888F))), 0.0F, 1.0F),
                1.0F};
        }
    }
    return pixels;
}

void grade_matches_cpu(
    const char* const label,
    const ScannerTargetStyle style,
    const bool monochrome,
    const bool positive,
    // 참이면 장치 질감이 얹히고, 그 하드 게이트가 경계 화소를 뒤집습니다.
    const bool has_texture) {
    const std::vector<Rgba32F> pixels = make_pattern();

    std::vector<Rgba32F> cpu = pixels;
    ScannerTargetGradeInfo cpu_info{};
    const negaflow::core::ImageView cpu_view{cpu.data(), cpu.size(), width, height, width};
    if (negaflow::imaging::apply_scanner_target_grade(
            cpu_view, style, monochrome, positive, {}, cpu_info) !=
        negaflow::core::KernelStatus::ok) {
        expect(false, "CPU target grade must succeed");
        return;
    }

    std::vector<Rgba32F> gpu = pixels;
    ScannerTargetGradeInfo gpu_info{};
    {
        // 근사 가속은 이 스코프 안에서만 돕니다 — 프리뷰·검출 경로와 같습니다.
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        const negaflow::core::ImageView gpu_view{gpu.data(), gpu.size(), width, height, width};
        if (negaflow::imaging::apply_scanner_target_grade(
                gpu_view, style, monochrome, positive, {}, gpu_info) !=
            negaflow::core::KernelStatus::ok) {
            expect(false, "GPU target grade must succeed");
            return;
        }
    }
    expect(cpu_info.applied == gpu_info.applied, "applied flag must match");
    expect(
        cpu_info.texture_applied == gpu_info.texture_applied,
        "texture flag must match");

    float worst = 0.0F;
    std::size_t worst_index = 0U;
    std::size_t outliers = 0U;
    for (std::size_t index = 0U; index < gpu.size(); ++index) {
        const float here = std::max(
            {std::abs(cpu[index].red - gpu[index].red),
             std::abs(cpu[index].green - gpu[index].green),
             std::abs(cpu[index].blue - gpu[index].blue),
             std::abs(cpu[index].alpha - gpu[index].alpha)});
        if (here > worst) {
            worst = here;
            worst_index = index;
        }
        if (here > 1.0e-4F) {
            ++outliers;
        }
    }
    // ☠️ 최악 화소의 **입력 밝기**를 같이 찍습니다. 이 사슬은 암부에서 조건수가 큽니다 —
    //    노리츠 장치 질감의 `gain = srgb_decode(y_new) / luma` 가 luma 로 나누기
    //    때문입니다. 어디서 커졌는지 모르면 허용치만 올리게 됩니다.
    const Rgba32F& source_pixel = pixels[worst_index];
    const float source_luma = (0.2126F * source_pixel.red) +
        (0.7152F * source_pixel.green) + (0.0722F * source_pixel.blue);
    const float limit = has_texture ? gate_flip_tolerance : accumulation_tolerance;
    const double fraction =
        static_cast<double>(outliers) / static_cast<double>(gpu.size());
    bool failed = false;
    if (worst > limit) {
        std::cerr << "FAIL: " << label << " target grade delta " << worst << " exceeds "
                  << limit << " at source luma " << source_luma << '\n';
        failed = true;
    }
    // 질감이 없는 스타일은 게이트가 없으므로 이탈 화소가 **하나도 없어야** 합니다.
    // 질감이 있는 쪽은 게이트 경계 등고선만큼만 허용합니다.
    const double allowed_fraction = has_texture ? gate_flip_pixel_fraction : 0.0;
    if (fraction > allowed_fraction) {
        std::cerr << "FAIL: " << label << " target grade has " << outliers << " / "
                  << gpu.size() << " pixels above 1e-4 (allowed fraction "
                  << allowed_fraction << ")\n";
        failed = true;
    }
    if (failed) {
        ++failures;
    } else {
        std::cout << label << " target grade max delta " << worst << " (source luma "
                  << source_luma << ", >1e-4 pixels " << outliers << " / " << gpu.size()
                  << ")\n";
    }
}

}  // namespace

int main() {
    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — target grade test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    grade_matches_cpu("noritsu", ScannerTargetStyle::noritsu, false, false, true);
    grade_matches_cpu("sp3000", ScannerTargetStyle::sp3000, false, false, false);
    grade_matches_cpu("f135", ScannerTargetStyle::f135, false, false, false);
    grade_matches_cpu("hr", ScannerTargetStyle::hr, false, false, false);
    // 포지티브는 세기가 절반입니다. 흑백은 색 항목이 통째로 꺼집니다.
    grade_matches_cpu("noritsu positive", ScannerTargetStyle::noritsu, false, true, true);
    grade_matches_cpu("sp3000 mono", ScannerTargetStyle::sp3000, true, false, false);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu scanner target grade tests passed\n";
    return 0;
}
