#pragma once

// GPU 커널이 **GPU 에서** 실제로 얼마나 걸렸는지 잽니다.
//
// 왜 따로 필요한가 — `pipeline/stage_timing.h` 는 **CPU 벽시계**입니다. GPU 디스패치는
// 비동기라 커널이 GPU 에서 쓴 시간은 그 숫자에 안 나옵니다. 2026-08-25 에 형태학 축 패스를
// 고쳐 보고 CPU 벽시계로 쟀더니 **같은 빌드를 두 번 돌린 편차 안이라 아무것도 증명하지
// 못했습니다**(체크포인트 §18.3). 커널을 고치고도 좋아졌는지 말할 수 없다는 뜻입니다.
//
// 그래서 `D3D11_QUERY_TIMESTAMP` 로 커널 구간만 따로 잽니다.
//
// **기본은 꺼져 있습니다.** `NEGA_GPU_TIMING=1` 일 때만 켜집니다. 켜면 타임스탬프를 읽기
// 위해 GPU 를 기다리므로 **파이프라인이 직렬화됩니다** — 그 상태의 벽시계는 제품 성능이
// 아닙니다. 커널 사이의 상대 비용을 보는 용도입니다.
//
// 값을 바꾸지 않습니다. 질의를 걸고 결과를 읽을 뿐입니다.

#include <cstdint>

struct ID3D11DeviceContext;

namespace negaflow::gpu {

class GpuDevice;

/// 잴 커널의 이름입니다. 이름 하나가 표의 한 줄입니다.
enum class GpuTimedKernel : std::uint8_t {
    morphology_horizontal = 0,
    morphology_vertical,
    count,
};

[[nodiscard]] bool gpu_kernel_timing_enabled() noexcept;

/// 한 디스패치를 감쌉니다. 꺼져 있으면 아무 일도 하지 않습니다.
///
/// 소멸자에서 GPU 를 기다려 결과를 읽습니다. 켠 상태에서만 그렇습니다.
class GpuKernelTimer final {
public:
    GpuKernelTimer(const GpuDevice& device, GpuTimedKernel kernel) noexcept;
    ~GpuKernelTimer();

    GpuKernelTimer(const GpuKernelTimer&) = delete;
    GpuKernelTimer& operator=(const GpuKernelTimer&) = delete;
    GpuKernelTimer(GpuKernelTimer&&) = delete;
    GpuKernelTimer& operator=(GpuKernelTimer&&) = delete;

private:
    struct Queries;

    ID3D11DeviceContext* context_{nullptr};
    Queries* queries_{nullptr};
    GpuTimedKernel kernel_{GpuTimedKernel::count};
};

struct GpuKernelTiming final {
    std::uint32_t dispatches{0U};
    // GPU 가 이 커널에 쓴 누적 시간입니다. CPU 벽시계가 아닙니다.
    std::uint64_t gpu_microseconds{0U};
    // 타임스탬프가 신뢰할 수 없다고 표시된 횟수(전원 상태 변화 등). 이만큼은 누적에서 뺐습니다.
    std::uint32_t disjoint_drops{0U};
};

[[nodiscard]] GpuKernelTiming gpu_kernel_timing(GpuTimedKernel kernel) noexcept;
void reset_gpu_kernel_timings() noexcept;
[[nodiscard]] const char* gpu_timed_kernel_name(GpuTimedKernel kernel) noexcept;

/// 켜져 있으면 표를 stderr 로 찍습니다.
void dump_gpu_kernel_timings() noexcept;

} // namespace negaflow::gpu
