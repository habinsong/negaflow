#pragma once

#include <atomic>
#include <cstdint>

namespace negaflow::core {

// A one-way latch the caller owns and only ever sets; the work only ever reads it.
//
// Passed by value into long stages so a cancel can take effect part way through instead
// of at the next stage boundary. A default-constructed flag never fires, which is what
// keeps every existing caller and every test unchanged.
struct CancelFlag final {
    const std::uint32_t* flag{nullptr};

    [[nodiscard]] bool requested() const noexcept {
        if (flag == nullptr) {
            return false;
        }
        return std::atomic_ref<std::uint32_t>(*const_cast<std::uint32_t*>(flag))
                   .load(std::memory_order_relaxed) != 0U;
    }
};

}  // namespace negaflow::core
