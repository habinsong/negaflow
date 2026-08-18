// CPU/GPU 동치 시험 — 색 커널. 진입점만 둡니다.
//
// 커널별 시험 표와 검사는 `GpuColorKernels/` 아래에 있습니다.

#include <iostream>

#include "GpuColorKernels/gpu_color_kernel_test_support.h"
#include "negaflow/gpu/gpu_device.h"

namespace {

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;

// 하드웨어가 있든 없든 같은 커널을 두 번 겁니다. WARP 는 CI 용이고, 하드웨어는 드라이버가
// 부동소수를 어떻게 다루는지 보기 위해서입니다 — 둘이 갈리면 거기서부터 봅니다.
void run_all(const GpuDevice& device, const char* const label) {
    gpu_color_kernel_tests::grade_matches_cpu(device, label);
    gpu_color_kernel_tests::mixer_matches_cpu(device, label);
    gpu_color_kernel_tests::primary_matches_cpu(device, label);
    gpu_color_kernel_tests::bw_matches_cpu(device, label);
    gpu_color_kernel_tests::digital_bw_matches_cpu(device, label);
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

    if (gpu_color_kernel_tests::failures != 0) {
        std::cerr << gpu_color_kernel_tests::failures
                  << " gpu color kernel check(s) failed\n";
        return 1;
    }
    std::cout << "gpu color kernel checks passed\n";
    return 0;
}
