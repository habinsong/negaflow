#include "negaflow/gpu/gpu_device.h"

#include <d3d11.h>
#include <dxgi1_6.h>

#include <cstring>
#include <string>

namespace negaflow::gpu {
namespace {

// 하한입니다. 10.x 컴퓨트는 UAV 1개·RWTexture2D 불가·768스레드·Z=1 제약이라 쓰지 않습니다.
constexpr D3D_FEATURE_LEVEL minimum_feature_level = D3D_FEATURE_LEVEL_11_0;

constexpr D3D_FEATURE_LEVEL requested_levels[] = {
    D3D_FEATURE_LEVEL_11_1,
    D3D_FEATURE_LEVEL_11_0,
};

// 11_0 의 Texture2D 한 변 상한입니다. 11_1 도 같습니다.
constexpr std::uint32_t feature_level_11_texture_dimension = 16384U;

void copy_description(const wchar_t* source, std::array<char, 160>& destination) noexcept {
    destination.fill('\0');
    if (source == nullptr) {
        return;
    }
    const int needed = ::WideCharToMultiByte(
        CP_UTF8, 0, source, -1, nullptr, 0, nullptr, nullptr);
    if (needed <= 0 || static_cast<std::size_t>(needed) > destination.size()) {
        // 이름이 길면 진단 표시만 잘립니다. 판정에는 쓰지 않으므로 실패로 보지 않습니다.
        const int truncated = static_cast<int>(destination.size()) - 1;
        (void)::WideCharToMultiByte(
            CP_UTF8, 0, source, -1, destination.data(), truncated, nullptr, nullptr);
        destination[destination.size() - 1U] = '\0';
        return;
    }
    (void)::WideCharToMultiByte(
        CP_UTF8, 0, source, -1, destination.data(), needed, nullptr, nullptr);
}

GpuAdapterInfo describe(IDXGIAdapter1* adapter) noexcept {
    GpuAdapterInfo info{};
    if (adapter == nullptr) {
        return info;
    }
    DXGI_ADAPTER_DESC1 description{};
    if (FAILED(adapter->GetDesc1(&description))) {
        return info;
    }
    copy_description(description.Description, info.description);
    info.vendor_id = description.VendorId;
    info.device_id = description.DeviceId;
    info.dedicated_video_memory = static_cast<std::uint64_t>(description.DedicatedVideoMemory);
    info.shared_system_memory = static_cast<std::uint64_t>(description.SharedSystemMemory);
    // 전용 VRAM 이 없으면 내장으로 봅니다. 벤더 ID 로 판정하지 않습니다 — Intel 외장(Arc)도
    // 있고 AMD 는 내장·외장이 같은 벤더 ID 라 벤더로는 가릴 수 없습니다.
    info.is_integrated = description.DedicatedVideoMemory == 0U;
    return info;
}

// 어댑터가 소프트웨어 렌더러이거나 표시 전용 가상 어댑터인지 봅니다.
// Parsec/원격 데스크톱의 가상 디스플레이 어댑터가 여기 걸립니다 — 그것으로 컴퓨트를 돌리면 안 됩니다.
[[nodiscard]] bool is_software_adapter(IDXGIAdapter1* adapter) noexcept {
    DXGI_ADAPTER_DESC1 description{};
    if (adapter == nullptr || FAILED(adapter->GetDesc1(&description))) {
        return true;
    }
    return (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0U;
}

struct CreatedDevice final {
    ID3D11Device* device{nullptr};
    ID3D11DeviceContext* context{nullptr};
    D3D_FEATURE_LEVEL level{};
};

[[nodiscard]] bool create_on(
    IDXGIAdapter1* adapter,
    D3D_DRIVER_TYPE driver_type,
    CreatedDevice& created) noexcept {
    // 어댑터를 명시하면 드라이버 종류는 UNKNOWN 이어야 합니다(D3D11CreateDevice 규칙).
    const D3D_DRIVER_TYPE effective =
        adapter != nullptr ? D3D_DRIVER_TYPE_UNKNOWN : driver_type;

    // BGRA 지원을 요구하지 않습니다 — 컴퓨트만 쓰므로 필요 없고, 요구하면 되는 어댑터가 줄어듭니다.
    UINT flags = 0U;
    const HRESULT created_result = ::D3D11CreateDevice(
        adapter,
        effective,
        nullptr,
        flags,
        requested_levels,
        static_cast<UINT>(std::size(requested_levels)),
        D3D11_SDK_VERSION,
        &created.device,
        &created.level,
        &created.context);
    if (FAILED(created_result) || created.device == nullptr) {
        return false;
    }
    if (created.level < minimum_feature_level) {
        if (created.context != nullptr) {
            created.context->Release();
            created.context = nullptr;
        }
        created.device->Release();
        created.device = nullptr;
        return false;
    }
    return true;
}

[[nodiscard]] bool supports_compute(ID3D11Device* device, D3D_FEATURE_LEVEL level) noexcept {
    if (device == nullptr) {
        return false;
    }
    if (level >= D3D_FEATURE_LEVEL_11_0) {
        // 11_0 이상은 컴퓨트 셰이더 5.0 이 규격상 필수입니다.
        return true;
    }
    // 여기 오면 하한 판정이 깨진 것입니다. 그래도 물어봅니다.
    D3D11_FEATURE_DATA_D3D10_X_HARDWARE_OPTIONS options{};
    if (FAILED(device->CheckFeatureSupport(
            D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS, &options, sizeof(options)))) {
        return false;
    }
    return options.ComputeShaders_Plus_RawAndStructuredBuffers_Via_Shader_4_x != FALSE;
}

[[nodiscard]] IDXGIAdapter3* adapter3_for_device(ID3D11Device* const device) noexcept {
    if (device == nullptr) {
        return nullptr;
    }
    IDXGIDevice* dxgi_device = nullptr;
    if (FAILED(device->QueryInterface(
            __uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgi_device))) ||
        dxgi_device == nullptr) {
        return nullptr;
    }
    IDXGIAdapter* adapter = nullptr;
    const HRESULT got_adapter = dxgi_device->GetAdapter(&adapter);
    dxgi_device->Release();
    if (FAILED(got_adapter) || adapter == nullptr) {
        return nullptr;
    }
    IDXGIAdapter3* adapter3 = nullptr;
    (void)adapter->QueryInterface(
        __uuidof(IDXGIAdapter3), reinterpret_cast<void**>(&adapter3));
    adapter->Release();
    return adapter3;
}

// DXGI 어댑터를 훑습니다. `IDXGIFactory6` 가 있으면 OS 의 고성능 선호 순서를 그대로 받고,
// 없으면 열거 순서를 씁니다. **어느 경로에서도 벤더로 거르지 않습니다.**
[[nodiscard]] bool create_hardware(CreatedDevice& created, GpuAdapterInfo& info) noexcept {
    IDXGIFactory1* factory1 = nullptr;
    if (FAILED(::CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory1)))) {
        return false;
    }

    IDXGIFactory6* factory6 = nullptr;
    (void)factory1->QueryInterface(__uuidof(IDXGIFactory6), reinterpret_cast<void**>(&factory6));

    bool made = false;
    for (UINT index = 0U; !made; ++index) {
        IDXGIAdapter1* adapter = nullptr;
        HRESULT enumerated = E_FAIL;
        if (factory6 != nullptr) {
            enumerated = factory6->EnumAdapterByGpuPreference(
                index,
                DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,
                __uuidof(IDXGIAdapter1),
                reinterpret_cast<void**>(&adapter));
        } else {
            enumerated = factory1->EnumAdapters1(index, &adapter);
        }
        if (enumerated == DXGI_ERROR_NOT_FOUND || FAILED(enumerated) || adapter == nullptr) {
            break;
        }
        if (!is_software_adapter(adapter) && create_on(adapter, D3D_DRIVER_TYPE_HARDWARE, created)) {
            info = describe(adapter);
            made = true;
        }
        adapter->Release();
    }

    if (factory6 != nullptr) {
        factory6->Release();
    }
    factory1->Release();
    return made;
}

[[nodiscard]] bool create_warp(CreatedDevice& created, GpuAdapterInfo& info) noexcept {
    if (!create_on(nullptr, D3D_DRIVER_TYPE_WARP, created)) {
        return false;
    }
    info = GpuAdapterInfo{};
    const char warp_name[] = "Microsoft Basic Render Driver (WARP)";
    std::memcpy(info.description.data(), warp_name, sizeof(warp_name));
    // WARP 는 시스템 메모리를 씁니다. 내장과 같은 취급을 받아야 타일 크기가 맞습니다.
    info.is_integrated = true;
    return true;
}

}  // namespace

const char* gpu_device_status_name(const GpuDeviceStatus status) noexcept {
    switch (status) {
        case GpuDeviceStatus::ok:
            return "ok";
        case GpuDeviceStatus::dxgi_unavailable:
            return "dxgi_unavailable";
        case GpuDeviceStatus::no_compatible_adapter:
            return "no_compatible_adapter";
        case GpuDeviceStatus::compute_unsupported:
            return "compute_unsupported";
        case GpuDeviceStatus::context_unavailable:
            return "context_unavailable";
    }
    return "unknown_status";
}

const char* gpu_driver_kind_name(const GpuDriverKind kind) noexcept {
    switch (kind) {
        case GpuDriverKind::none:
            return "none";
        case GpuDriverKind::hardware:
            return "hardware";
        case GpuDriverKind::warp:
            return "warp";
    }
    return "unknown_driver";
}

GpuDevice::~GpuDevice() { reset(); }

GpuDevice::GpuDevice(GpuDevice&& other) noexcept
    : device_(other.device_),
      context_(other.context_),
      adapter3_(other.adapter3_),
      capability_(other.capability_),
      status_(other.status_) {
    other.device_ = nullptr;
    other.context_ = nullptr;
    other.adapter3_ = nullptr;
    other.capability_ = GpuCapability{};
    other.status_ = GpuDeviceStatus::dxgi_unavailable;
}

GpuDevice& GpuDevice::operator=(GpuDevice&& other) noexcept {
    if (this != &other) {
        reset();
        device_ = other.device_;
        context_ = other.context_;
        adapter3_ = other.adapter3_;
        capability_ = other.capability_;
        status_ = other.status_;
        other.device_ = nullptr;
        other.context_ = nullptr;
        other.adapter3_ = nullptr;
        other.capability_ = GpuCapability{};
        other.status_ = GpuDeviceStatus::dxgi_unavailable;
    }
    return *this;
}

void GpuDevice::reset() noexcept {
    if (context_ != nullptr) {
        context_->ClearState();
        context_->Release();
        context_ = nullptr;
    }
    if (device_ != nullptr) {
        device_->Release();
        device_ = nullptr;
    }
    if (adapter3_ != nullptr) {
        adapter3_->Release();
        adapter3_ = nullptr;
    }
    capability_ = GpuCapability{};
    status_ = GpuDeviceStatus::dxgi_unavailable;
}

GpuDevice GpuDevice::create(const GpuDevicePreference preference) noexcept {
    GpuDevice made{};
    CreatedDevice created{};
    GpuAdapterInfo info{};
    GpuDriverKind kind = GpuDriverKind::none;

    if (preference != GpuDevicePreference::warp_only && create_hardware(created, info)) {
        kind = GpuDriverKind::hardware;
    } else if (preference != GpuDevicePreference::hardware_only && create_warp(created, info)) {
        kind = GpuDriverKind::warp;
    }

    if (kind == GpuDriverKind::none) {
        made.status_ = GpuDeviceStatus::no_compatible_adapter;
        return made;
    }
    if (created.context == nullptr) {
        created.device->Release();
        made.status_ = GpuDeviceStatus::context_unavailable;
        return made;
    }
    if (!supports_compute(created.device, created.level)) {
        created.context->Release();
        created.device->Release();
        made.status_ = GpuDeviceStatus::compute_unsupported;
        return made;
    }

    made.device_ = created.device;
    made.context_ = created.context;
    made.adapter3_ = adapter3_for_device(created.device);
    made.capability_.driver = kind;
    made.capability_.feature_level = static_cast<std::uint32_t>(created.level);
    made.capability_.compute_shaders = true;
    made.capability_.max_texture_dimension = feature_level_11_texture_dimension;
    made.capability_.adapter = info;
    made.status_ = GpuDeviceStatus::ok;
    return made;
}

const GpuDevice& GpuDevice::shared() noexcept {
    // 함수 지역 static 이라 첫 호출에서 한 번만 만듭니다(C++11 스레드 안전 초기화).
    // 실패해도 다시 시도하지 않습니다 — 장치가 없는 기계에서 매 프레임 수십 ms 를 태우지 않기 위해서입니다.
    static GpuDevice instance = GpuDevice::create(GpuDevicePreference::automatic);
    return instance;
}

bool GpuDevice::query_local_video_memory_info(GpuVideoMemoryInfo& info) const noexcept {
    info = GpuVideoMemoryInfo{};
    if (!is_usable() || adapter3_ == nullptr) {
        return false;
    }

    DXGI_QUERY_VIDEO_MEMORY_INFO queried{};
    const HRESULT result = adapter3_->QueryVideoMemoryInfo(
        0U, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &queried);
    if (FAILED(result) || queried.Budget == 0U) {
        return false;
    }

    info.budget = queried.Budget;
    info.current_usage = queried.CurrentUsage;
    info.available_for_reservation = queried.AvailableForReservation;
    info.current_reservation = queried.CurrentReservation;
    return true;
}

bool GpuDevice::trim_idle() const noexcept {
    if (!is_usable() || context_ == nullptr || device_ == nullptr) {
        return false;
    }
    IDXGIDevice3* dxgi_device = nullptr;
    if (FAILED(device_->QueryInterface(
            __uuidof(IDXGIDevice3),
            reinterpret_cast<void**>(&dxgi_device))) ||
        dxgi_device == nullptr) {
        return false;
    }
    context_->ClearState();
    context_->Flush();
    dxgi_device->Trim();
    dxgi_device->Release();
    return true;
}

}  // namespace negaflow::gpu
