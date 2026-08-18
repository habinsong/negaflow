#include "negaflow/imaging/kernel_accelerator.h"

#include <atomic>

namespace negaflow::imaging {
namespace {

// 설치는 프로세스당 한 번이지만, 읽는 쪽은 여러 스레드입니다. 원자로 둡니다.
std::atomic<const KernelAccelerator*> installed{nullptr};

// 스레드마다 따로입니다. 한 스레드가 스코프를 열어도 다른 스레드의 내보내기 경로는
// 영향을 받지 않습니다.
thread_local int approximate_depth = 0;

}  // namespace

void install_kernel_accelerator(const KernelAccelerator* const table) noexcept {
    installed.store(table, std::memory_order_release);
}

const KernelAccelerator* kernel_accelerator() noexcept {
    return installed.load(std::memory_order_acquire);
}

ApproximateAcceleratorScope::ApproximateAcceleratorScope() noexcept { ++approximate_depth; }

ApproximateAcceleratorScope::~ApproximateAcceleratorScope() { --approximate_depth; }

bool approximate_acceleration_allowed() noexcept { return approximate_depth > 0; }

}  // namespace negaflow::imaging
