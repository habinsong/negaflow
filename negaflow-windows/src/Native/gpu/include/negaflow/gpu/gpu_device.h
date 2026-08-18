#pragma once

// Direct3D 11 컴퓨트 장치입니다. macOS 의 `DevelopFrameRenderer.sharedRenderContext`
// (Metal command queue 하나로 만든 CIContext) 에 해당합니다. 큐를 하나로 두는 이유도 같습니다 —
// macOS 주석 원문: "단일 큐로 GPU 작업이 정렬돼, 빠른 반복 렌더에서 GPU 쓰기 완료 전에 결과를
// 읽어 빈/검은 프레임이 나오는 동기화 버블을 없앤다."
//
// 벤더 중립 — 다음 규칙을 깨지 마십시오.
//  * 벤더 ID 로 어댑터를 고르거나 거르지 않습니다. Intel 내장·AMD 내장·Intel/NVIDIA/AMD 외장을
//    똑같이 취급합니다.
//  * 기능 수준 하한은 `D3D_FEATURE_LEVEL_11_0` 하나입니다. 10.x 컴퓨트(CS 4.x)는 UAV 1개,
//    `RWTexture2D` 불가, 스레드 768개, Z=1 제약이라 이 파이프라인 설계와 맞지 않습니다.
//    (Microsoft "Compute Shaders on Downlevel Hardware")
//  * 벤더 확장·웨이브 인트린식·SM 6.0 을 쓰지 않습니다. D3D11 은 셰이더 모델 5.0 입니다.
//  * 하드웨어가 없으면 WARP(소프트웨어 래스터라이저)로, 그것도 없으면 CPU 경로로 떨어집니다.
//    폴백은 기능 축소가 아니라 지금 있는 스칼라 경로 그대로입니다.

#include <array>
#include <cstdint>

struct ID3D11Device;
struct ID3D11DeviceContext;

namespace negaflow::gpu {

enum class GpuDeviceStatus : std::uint8_t {
    ok = 0,
    // DXGI 팩토리를 못 만들었습니다. d3d11/dxgi 자체가 없는 환경입니다.
    dxgi_unavailable,
    // 어댑터는 있으나 기능 수준 11_0 으로 장치를 만들지 못했습니다.
    no_compatible_adapter,
    // 장치는 만들었는데 컴퓨트 셰이더를 못 씁니다. 11_0 이면 나올 수 없지만 확인은 합니다.
    compute_unsupported,
    // 즉시 컨텍스트가 없습니다.
    context_unavailable,
};

[[nodiscard]] const char* gpu_device_status_name(GpuDeviceStatus status) noexcept;

enum class GpuDriverKind : std::uint8_t {
    none = 0,
    // 실제 GPU 입니다. 내장인지 외장인지는 `GpuAdapterInfo::is_integrated` 로 봅니다.
    hardware,
    // WARP — Microsoft 소프트웨어 래스터라이저. CI 에서 하드웨어 없이 정합성을 보는 용도입니다.
    warp,
};

[[nodiscard]] const char* gpu_driver_kind_name(GpuDriverKind kind) noexcept;

// 어느 장치를 고를지에 대한 요청입니다. 벤더가 아니라 종류만 고릅니다.
enum class GpuDevicePreference : std::uint8_t {
    // 하드웨어를 먼저 찾고, 없으면 WARP 로 갑니다. 앱이 쓰는 값입니다.
    automatic = 0,
    // 하드웨어만. 없으면 실패합니다. "이 기계에 진짜 GPU 가 있는가" 를 볼 때 씁니다.
    hardware_only,
    // WARP 만. CPU/GPU 동치 시험이 하드웨어 없이도 돌아야 하므로 필요합니다.
    warp_only,
};

struct GpuAdapterInfo final {
    // DXGI 가 준 이름을 UTF-8 로 옮긴 것입니다. 진단 표시용이며 판정에 쓰지 마십시오.
    std::array<char, 160> description{};
    std::uint32_t vendor_id{0};
    std::uint32_t device_id{0};
    std::uint64_t dedicated_video_memory{0};
    std::uint64_t shared_system_memory{0};
    // 전용 비디오 메모리가 없으면 내장으로 봅니다. 내장은 시스템 메모리를 나눠 쓰므로
    // 타일 크기와 캐시 상한을 이 값으로 다르게 잡아야 합니다.
    bool is_integrated{false};
};

struct GpuCapability final {
    GpuDriverKind driver{GpuDriverKind::none};
    // D3D_FEATURE_LEVEL 원값입니다. 11_0 은 0xb000.
    std::uint32_t feature_level{0};
    bool compute_shaders{false};
    // Texture2D 한 변의 상한입니다. 11_0 이면 16384. 이보다 큰 스캔은 타일로 잘라야 합니다.
    std::uint32_t max_texture_dimension{0};
    GpuAdapterInfo adapter{};
};

// D3D11 장치와 즉시 컨텍스트를 소유합니다. 복사 불가, 이동 가능.
class GpuDevice final {
public:
    GpuDevice() noexcept = default;
    ~GpuDevice();

    GpuDevice(const GpuDevice&) = delete;
    GpuDevice& operator=(const GpuDevice&) = delete;
    GpuDevice(GpuDevice&& other) noexcept;
    GpuDevice& operator=(GpuDevice&& other) noexcept;

    // 장치를 하나 만듭니다. 실패해도 예외를 던지지 않습니다 — `status()` 로 판정하십시오.
    [[nodiscard]] static GpuDevice create(
        GpuDevicePreference preference = GpuDevicePreference::automatic) noexcept;

    // 프로세스 공유 장치입니다. macOS 가 `sharedRenderContext` 하나를 쓰는 것과 같습니다.
    // 첫 호출에서 한 번 만들고 이후는 같은 것을 돌려줍니다. 만들기에 실패했으면
    // 실패한 상태 그대로 돌려줍니다 — 매번 다시 시도하지 않습니다(느린 실패를 반복하지 않기 위해).
    [[nodiscard]] static const GpuDevice& shared() noexcept;

    [[nodiscard]] GpuDeviceStatus status() const noexcept { return status_; }
    [[nodiscard]] const GpuCapability& capability() const noexcept { return capability_; }
    [[nodiscard]] bool is_usable() const noexcept {
        return status_ == GpuDeviceStatus::ok && device_ != nullptr;
    }

    [[nodiscard]] ID3D11Device* device() const noexcept { return device_; }
    [[nodiscard]] ID3D11DeviceContext* context() const noexcept { return context_; }

private:
    void reset() noexcept;

    ID3D11Device* device_{nullptr};
    ID3D11DeviceContext* context_{nullptr};
    GpuCapability capability_{};
    GpuDeviceStatus status_{GpuDeviceStatus::dxgi_unavailable};
};

}  // namespace negaflow::gpu
