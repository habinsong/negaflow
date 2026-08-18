#include "negaflow/gpu/gpu_device.h"

#include <cstdint>
#include <iostream>
#include <string_view>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuDeviceStatus;
using negaflow::gpu::GpuDriverKind;

// 11_0 원값입니다. 하한이 내려가면 이 시험이 먼저 깨져야 합니다.
constexpr std::uint32_t feature_level_11_0 = 0xb000U;
constexpr std::uint32_t texture_dimension_11_0 = 16384U;

// WARP 는 Windows 에 항상 있습니다. 하드웨어가 없는 CI 에서도 이 경로로 커널 정합성을 봅니다.
void warp_device_is_always_available() {
    const GpuDevice device = GpuDevice::create(GpuDevicePreference::warp_only);
    expect(device.status() == GpuDeviceStatus::ok, "warp device must be creatable");
    expect(device.is_usable(), "warp device must be usable");
    if (!device.is_usable()) {
        return;
    }
    expect(device.capability().driver == GpuDriverKind::warp, "warp driver kind");
    expect(device.capability().compute_shaders, "warp must report compute shaders");
    expect(
        device.capability().feature_level >= feature_level_11_0,
        "warp must reach feature level 11_0");
    expect(
        device.capability().max_texture_dimension == texture_dimension_11_0,
        "11_0 texture dimension is 16384");
    // WARP 는 시스템 메모리를 씁니다. 타일 크기 결정이 내장과 같아야 합니다.
    expect(device.capability().adapter.is_integrated, "warp counts as integrated memory");
    expect(device.device() != nullptr, "warp exposes a device");
    expect(device.context() != nullptr, "warp exposes an immediate context");
}

// 하드웨어가 있으면 규격을 지켜야 하고, 없으면 그 사실을 상태로 말해야 합니다.
// **어느 쪽이든 시험은 통과합니다** — 이 시험은 GPU 유무가 아니라 판정의 일관성을 봅니다.
void hardware_device_is_consistent_when_present() {
    const GpuDevice device = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (!device.is_usable()) {
        expect(
            device.status() == GpuDeviceStatus::no_compatible_adapter,
            "missing hardware must say no_compatible_adapter");
        std::cout << "[gpu] hardware: none (" << negaflow::gpu::gpu_device_status_name(device.status())
                  << ")\n";
        return;
    }
    expect(device.capability().driver == GpuDriverKind::hardware, "hardware driver kind");
    expect(device.capability().compute_shaders, "hardware must report compute shaders");
    expect(
        device.capability().feature_level >= feature_level_11_0,
        "hardware below 11_0 must be rejected, not accepted");
    // 벤더로 거르지 않으므로 벤더 ID 를 단정하지 않습니다. 다만 실제 어댑터라면 0 이 아닙니다.
    expect(device.capability().adapter.vendor_id != 0U, "hardware adapter reports a vendor id");
    expect(
        device.capability().adapter.description[0] != '\0',
        "hardware adapter reports a description");

    const auto& adapter = device.capability().adapter;
    std::cout << "[gpu] hardware: " << adapter.description.data() << " vendor=0x" << std::hex
              << adapter.vendor_id << " device=0x" << adapter.device_id << std::dec
              << " fl=0x" << std::hex << device.capability().feature_level << std::dec
              << (adapter.is_integrated ? " integrated" : " discrete") << " vram="
              << (adapter.dedicated_video_memory / (1024ULL * 1024ULL)) << "MB\n";
}

// 앱이 쓰는 경로입니다. 하드웨어가 없어도 WARP 로 떨어지므로 **항상** 쓸 수 있어야 합니다.
void automatic_always_produces_a_device() {
    const GpuDevice device = GpuDevice::create(GpuDevicePreference::automatic);
    expect(device.is_usable(), "automatic must always yield a device (hardware or warp)");
    if (!device.is_usable()) {
        return;
    }
    expect(
        device.capability().driver == GpuDriverKind::hardware ||
            device.capability().driver == GpuDriverKind::warp,
        "automatic picks hardware or warp");
    expect(device.capability().compute_shaders, "automatic device supports compute");
}

// macOS 가 `sharedRenderContext` 하나를 쓰는 것과 같습니다. 두 번 물어도 같은 것이어야
// 합니다 — 장치가 둘이면 GPU 작업이 두 큐로 갈라져 동기화 버블이 생깁니다.
void shared_device_is_one_instance() {
    const GpuDevice& first = GpuDevice::shared();
    const GpuDevice& second = GpuDevice::shared();
    expect(&first == &second, "shared() must return the same instance");
    expect(first.is_usable(), "shared device must be usable on Windows");
    if (first.is_usable()) {
        expect(first.device() == second.device(), "shared device pointer is stable");
    }
}

// 이동한 뒤 원본이 살아 있으면 COM 참조를 두 번 놓습니다.
void moved_from_device_is_empty() {
    GpuDevice source = GpuDevice::create(GpuDevicePreference::warp_only);
    expect(source.is_usable(), "source must start usable");
    const GpuDevice moved = std::move(source);
    expect(moved.is_usable(), "moved-to device keeps the handles");
    expect(!source.is_usable(), "moved-from device must be empty");  // NOLINT(bugprone-use-after-move)
    expect(source.device() == nullptr, "moved-from device pointer is null");
    expect(source.context() == nullptr, "moved-from context pointer is null");
}

void status_names_are_stable() {
    using negaflow::gpu::gpu_device_status_name;
    using negaflow::gpu::gpu_driver_kind_name;
    expect(std::string_view{gpu_device_status_name(GpuDeviceStatus::ok)} == "ok", "ok name");
    expect(
        std::string_view{gpu_device_status_name(GpuDeviceStatus::no_compatible_adapter)} ==
            "no_compatible_adapter",
        "no_compatible_adapter name");
    expect(
        std::string_view{gpu_device_status_name(GpuDeviceStatus::compute_unsupported)} ==
            "compute_unsupported",
        "compute_unsupported name");
    expect(
        std::string_view{gpu_driver_kind_name(GpuDriverKind::hardware)} == "hardware",
        "hardware kind name");
    expect(std::string_view{gpu_driver_kind_name(GpuDriverKind::warp)} == "warp", "warp kind name");
    expect(std::string_view{gpu_driver_kind_name(GpuDriverKind::none)} == "none", "none kind name");
}

}  // namespace

int main() {
    warp_device_is_always_available();
    hardware_device_is_consistent_when_present();
    automatic_always_produces_a_device();
    shared_device_is_one_instance();
    moved_from_device_is_empty();
    status_names_are_stable();

    if (failures != 0) {
        std::cerr << failures << " gpu device check(s) failed\n";
        return 1;
    }
    std::cout << "gpu device checks passed\n";
    return 0;
}
