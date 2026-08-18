// CPU/GPU 동치 시험 — 이웃 원시연산. 진입점만 둡니다.
//
// macOS 는 이 자리를 Apple 내장 필터가 채웁니다 — `CIBoxBlur` · `CIGaussianBlur` ·
// `CIMedianFilter` · `CIAreaAverage`. Windows 에는 없어서 우리가 만들어야 하고,
// 가이드 필터 4커널과 `filmScanShrink` 가 여기 물려 있습니다.
//
// 묶음별 참조와 검사는 `GpuNeighborhood/` 아래에 있습니다.

#include <iostream>

#include "GpuNeighborhood/gpu_box_blur_tests.h"
#include "GpuNeighborhood/gpu_gaussian_tests.h"
#include "GpuNeighborhood/gpu_guided_filter_tests.h"
#include "GpuNeighborhood/gpu_median3_tests.h"
#include "GpuNeighborhood/gpu_neighborhood_test_support.h"
#include "negaflow/gpu/gpu_device.h"

namespace {

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;

// 하드웨어가 있든 없든 같은 커널을 두 번 겁니다. WARP 는 CI 용이고, 하드웨어는 드라이버가
// 부동소수를 어떻게 다루는지 보기 위해서입니다 — 둘이 갈리면 거기서부터 봅니다.
void run_all(const GpuDevice& device, const char* const label) {
    gpu_neighborhood_tests::box_blur_matches_reference(device, label);
    gpu_neighborhood_tests::box_blur_alpha_matches_reference(device, label);
    gpu_neighborhood_tests::gaussian_matches_reference(device, label);
    gpu_neighborhood_tests::median3_matches_reference(device, label);
    gpu_neighborhood_tests::guided_filter_matches_reference(device, label);
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    run_all(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        run_all(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (gpu_neighborhood_tests::failures != 0) {
        std::cerr << gpu_neighborhood_tests::failures << " gpu neighborhood check(s) failed\n";
        return 1;
    }
    std::cout << "gpu neighborhood checks passed\n";
    return 0;
}
