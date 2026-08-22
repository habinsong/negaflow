#pragma once

// 스캐너 타겟 프로파일 그레이드의 GPU 판입니다.
//
// macOS : `ScannerTargetGrade+Apply.swift` — 64³ `CIColorCubeWithColorSpace` +
// `boundedRelativeGrade`(`ChromabaseMetalKernels.swift:531`)
// CPU 판 : `imaging/scanner_target_grade.cpp` `apply_profile_grade`
// 셰이더 : `shaders/scanner_target_grade.hlsl`
//
// **엔진에서 가장 비싼 화소별 커널입니다.** 노리츠 프리뷰 실측(5088×3401):
// 직렬 58,995 ms → 행 병렬 16,201 ms. 그 다음이 GPU 입니다.
//
// **macOS 와 알고리즘이 다릅니다.** macOS 는 같은 수식을 64³ 격자에서 262,144번만
// 풀어 큐브를 만들고 보간합니다. Windows 는 화소마다 풉니다 — 24MP 에서 66배입니다.
// 이 클래스는 **Windows 의 셈을 옮긴 것**이고, 큐브로 바꾸는 것은 값이 달라지는 별건입니다.
//
// **근사한 것입니다.** CPU 는 Lab 왕복과 hue/chroma 응답을 `double` 로 돌고 GPU 는
// float 입니다. sRGB 왕복은 CPU 도 이미 float 로 내려서 돕니다.

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/scanner_target_grade.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuScannerTargetGrade final {
public:
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuScannerTargetGrade& kernel) noexcept;

    // `setup` 은 CPU 가 화소 루프 밖에서 만든 것을 그대로 받습니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const imaging::ScannerTargetGradeSetup& setup) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

} // namespace negaflow::gpu
