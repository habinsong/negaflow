#include "negaflow/core/machine_memory.h"

#include <windows.h>

namespace negaflow::core {
namespace {

// 설치 메모리를 못 읽을 때만 쓰는 값입니다. 예전에 모든 자리에 박혀 있던 상수라, 모르는
// 기계에서 예전보다 느슨해지지 않게 이 값으로 닫습니다.
constexpr std::uint64_t unknown_machine_limit_bytes = 512ULL * 1024ULL * 1024ULL;

}  // namespace

std::uint64_t installed_memory_bytes() noexcept {
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status) == 0) {
        return 0ULL;
    }
    return status.ullTotalPhys;
}

std::uint64_t default_max_pixel_bytes() noexcept {
    // 설치 메모리는 실행 중에 바뀌지 않습니다. 한 번만 셉니다 - 이 값은 화상을 열 때마다
    // 만들어지는 `Limits` 구조체의 기본값이라 뜨거운 자리입니다.
    static const std::uint64_t limit = [] {
        const std::uint64_t installed = installed_memory_bytes();
        return installed == 0ULL ? unknown_machine_limit_bytes : installed;
    }();
    return limit;
}

}  // namespace negaflow::core
