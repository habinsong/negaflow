#include "negaflow/gpu/gpu_kernel_timing.h"

#include <d3d11.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>

#include "negaflow/gpu/gpu_device.h"

namespace negaflow::gpu {
namespace {

struct AtomicTiming final {
    std::atomic<std::uint32_t> dispatches{0U};
    std::atomic<std::uint64_t> gpu_microseconds{0U};
    std::atomic<std::uint32_t> disjoint_drops{0U};
};

AtomicTiming timings[static_cast<std::size_t>(GpuTimedKernel::count)]{};

[[nodiscard]] bool environment_set() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_GPU_TIMING") == 0 && length > 0U;
}

} // namespace

struct GpuKernelTimer::Queries final {
    ID3D11Query* disjoint{nullptr};
    ID3D11Query* begin{nullptr};
    ID3D11Query* end{nullptr};

    ~Queries() {
        if (end != nullptr) { end->Release(); }
        if (begin != nullptr) { begin->Release(); }
        if (disjoint != nullptr) { disjoint->Release(); }
    }
};

bool gpu_kernel_timing_enabled() noexcept {
    // 한 번만 봅니다. 매 디스패치마다 환경 변수를 읽으면 그 자체가 계측을 왜곡합니다.
    static const bool enabled = environment_set();
    return enabled;
}

const char* gpu_timed_kernel_name(const GpuTimedKernel kernel) noexcept {
    switch (kernel) {
        case GpuTimedKernel::morphology_horizontal: return "morphology_horizontal";
        case GpuTimedKernel::morphology_vertical: return "morphology_vertical";
        case GpuTimedKernel::count: break;
    }
    return "unknown";
}

GpuKernelTimer::GpuKernelTimer(const GpuDevice& device, const GpuTimedKernel kernel) noexcept {
    if (!gpu_kernel_timing_enabled() || !device.is_usable() ||
        kernel == GpuTimedKernel::count) {
        return;
    }
    auto* const created = new (std::nothrow) Queries{};
    if (created == nullptr) {
        return;
    }
    D3D11_QUERY_DESC disjoint_description{};
    disjoint_description.Query = D3D11_QUERY_TIMESTAMP_DISJOINT;
    D3D11_QUERY_DESC stamp_description{};
    stamp_description.Query = D3D11_QUERY_TIMESTAMP;
    if (FAILED(device.device()->CreateQuery(&disjoint_description, &created->disjoint)) ||
        FAILED(device.device()->CreateQuery(&stamp_description, &created->begin)) ||
        FAILED(device.device()->CreateQuery(&stamp_description, &created->end))) {
        delete created;
        return;
    }
    context_ = device.context();
    queries_ = created;
    kernel_ = kernel;
    context_->Begin(queries_->disjoint);
    context_->End(queries_->begin);
}

GpuKernelTimer::~GpuKernelTimer() {
    if (queries_ == nullptr) {
        return;
    }
    context_->End(queries_->end);
    context_->End(queries_->disjoint);

    // GPU 를 기다립니다. 켠 상태에서만 하는 일이고, 그래서 이 모드의 벽시계는 제품 성능이
    // 아닙니다.
    D3D11_QUERY_DATA_TIMESTAMP_DISJOINT disjoint{};
    while (context_->GetData(queries_->disjoint, &disjoint, sizeof(disjoint), 0U) == S_FALSE) {
    }
    std::uint64_t begin_stamp = 0U;
    std::uint64_t end_stamp = 0U;
    while (context_->GetData(queries_->begin, &begin_stamp, sizeof(begin_stamp), 0U) == S_FALSE) {
    }
    while (context_->GetData(queries_->end, &end_stamp, sizeof(end_stamp), 0U) == S_FALSE) {
    }

    AtomicTiming& slot = timings[static_cast<std::size_t>(kernel_)];
    slot.dispatches.fetch_add(1U, std::memory_order_relaxed);
    // `Disjoint` 는 그 구간의 타임스탬프를 믿을 수 없다는 뜻입니다(전원 상태 변화 등).
    // 그때는 버립니다 — 섞으면 표가 거짓말을 합니다.
    if (disjoint.Disjoint != FALSE || disjoint.Frequency == 0U || end_stamp <= begin_stamp) {
        slot.disjoint_drops.fetch_add(1U, std::memory_order_relaxed);
    } else {
        const std::uint64_t ticks = end_stamp - begin_stamp;
        slot.gpu_microseconds.fetch_add(
            (ticks * 1'000'000ULL) / disjoint.Frequency, std::memory_order_relaxed);
    }
    delete queries_;
}

GpuKernelTiming gpu_kernel_timing(const GpuTimedKernel kernel) noexcept {
    if (kernel == GpuTimedKernel::count) {
        return {};
    }
    const AtomicTiming& slot = timings[static_cast<std::size_t>(kernel)];
    return {
        slot.dispatches.load(std::memory_order_relaxed),
        slot.gpu_microseconds.load(std::memory_order_relaxed),
        slot.disjoint_drops.load(std::memory_order_relaxed)};
}

void reset_gpu_kernel_timings() noexcept {
    for (AtomicTiming& slot : timings) {
        slot.dispatches.store(0U, std::memory_order_relaxed);
        slot.gpu_microseconds.store(0U, std::memory_order_relaxed);
        slot.disjoint_drops.store(0U, std::memory_order_relaxed);
    }
}

void dump_gpu_kernel_timings() noexcept {
    if (!gpu_kernel_timing_enabled()) {
        return;
    }
    // 디스패치가 0이어도 줄을 냅니다. 아무 줄도 안 나오면 "계측이 꺼졌다" 와 "그 커널이
    // 안 돌았다" 를 구분할 수 없어서, 실제로 그것 때문에 한 번 헤맸습니다.
    for (std::size_t index = 0U; index < static_cast<std::size_t>(GpuTimedKernel::count); ++index) {
        const GpuTimedKernel kernel = static_cast<GpuTimedKernel>(index);
        const GpuKernelTiming timing = gpu_kernel_timing(kernel);
        (void)std::fprintf(
            stderr,
            "[gpu kernel timing] %s dispatches=%u gpu_us=%llu drops=%u\n",
            gpu_timed_kernel_name(kernel),
            timing.dispatches,
            static_cast<unsigned long long>(timing.gpu_microseconds),
            timing.disjoint_drops);
    }
}

} // namespace negaflow::gpu
