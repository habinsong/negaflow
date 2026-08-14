#include "negaflow/color/gamut_check.h"

#include <Windows.h>
#include <icm.h>

#include <new>

namespace negaflow::color {
namespace {

/// 메모리에 있는 ICC 바이트로 프로파일을 엽니다. 파일을 만들지 않습니다 — 내보내기 도중
/// 임시 파일을 남기면 실패했을 때 치울 것이 늘어납니다.
class MemoryProfile final {
public:
    explicit MemoryProfile(std::vector<std::uint8_t>& bytes) noexcept {
        if (bytes.empty()) {
            return;
        }
        PROFILE profile{};
        profile.dwType = PROFILE_MEMBUFFER;
        profile.pProfileData = bytes.data();
        profile.cbDataSize = static_cast<DWORD>(bytes.size());
        handle_ = OpenColorProfileW(&profile, PROFILE_READ, FILE_SHARE_READ, OPEN_EXISTING);
        if (handle_ == nullptr) {
            error_ = static_cast<std::uint32_t>(GetLastError());
        }
    }

    MemoryProfile(const MemoryProfile&) = delete;
    MemoryProfile& operator=(const MemoryProfile&) = delete;

    ~MemoryProfile() noexcept {
        if (handle_ != nullptr) {
            static_cast<void>(CloseColorProfile(handle_));
        }
    }

    [[nodiscard]] HPROFILE get() const noexcept { return handle_; }
    [[nodiscard]] std::uint32_t error() const noexcept { return error_; }

private:
    HPROFILE handle_{nullptr};
    std::uint32_t error_{0U};
};

class Transform final {
public:
    Transform(HPROFILE source, HPROFILE destination) noexcept {
        HPROFILE profiles[]{source, destination};
        DWORD intents[]{INTENT_PERCEPTUAL, INTENT_PERCEPTUAL};
        // ENABLE_GAMUT_CHECKING 이 이 변환의 전부입니다. 이것 없이는 CheckBitmapBits 가
        // 무엇을 판정해야 하는지 모릅니다.
        handle_ = CreateMultiProfileTransform(
            profiles,
            2U,
            intents,
            2U,
            ENABLE_GAMUT_CHECKING | USE_RELATIVE_COLORIMETRIC,
            INDEX_DONT_CARE);
        if (handle_ == nullptr) {
            error_ = static_cast<std::uint32_t>(GetLastError());
        }
    }

    Transform(const Transform&) = delete;
    Transform& operator=(const Transform&) = delete;

    ~Transform() noexcept {
        if (handle_ != nullptr) {
            static_cast<void>(DeleteColorTransform(handle_));
        }
    }

    [[nodiscard]] HTRANSFORM get() const noexcept { return handle_; }
    [[nodiscard]] std::uint32_t error() const noexcept { return error_; }

private:
    HTRANSFORM handle_{nullptr};
    std::uint32_t error_{0U};
};

/// 원본은 언제나 sRGB 입니다 — 판정하는 화소가 화면에 보이는 sRGB 화소이기 때문입니다.
[[nodiscard]] std::vector<std::uint8_t> source_profile_bytes() {
    return build_icc_profile(OutputColorSpace::srgb);
}

}  // namespace

bool gamut_check_supported(const OutputColorSpace destination) noexcept {
    try {
        std::vector<std::uint8_t> source_bytes = source_profile_bytes();
        std::vector<std::uint8_t> destination_bytes = build_icc_profile(destination);
        const MemoryProfile source(source_bytes);
        const MemoryProfile target(destination_bytes);
        if (source.get() == nullptr || target.get() == nullptr) {
            return false;
        }
        const Transform transform(source.get(), target.get());
        return transform.get() != nullptr;
    } catch (const std::bad_alloc&) {
        return false;
    }
}

GamutCheckResult check_gamut_bgr8(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    const OutputColorSpace destination) {
    GamutCheckResult result{};
    if (pixels == nullptr || width == 0U || height == 0U ||
        stride_bytes < static_cast<std::uint64_t>(width) * 3ULL) {
        result.status = GamutCheckStatus::invalid_input;
        return result;
    }

    std::vector<std::uint8_t> source_bytes;
    std::vector<std::uint8_t> destination_bytes;
    // ICM 은 같은 RGB 색역의 수학적 경계(정확한 0/255)를 반올림 때문에 바깥으로 판정합니다.
    // 그대로 두면 sRGB 그림을 sRGB 로 프루프할 때 흰색과 검정이 전부 경고로 뜹니다.
    // **판정 전용 사본만** 1 LSB 안쪽으로 밀어 그 거짓 경고를 막습니다 — 화면·현상·내보내기
    // 화소는 건드리지 않습니다. macOS 도 같은 이유로 같은 일을 합니다.
    std::vector<std::uint8_t> probe;
    try {
        source_bytes = source_profile_bytes();
        destination_bytes = build_icc_profile(destination);
        result.out_of_gamut.assign(
            static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0U);
        probe.assign(
            static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 3U, 0U);
    } catch (const std::bad_alloc&) {
        result.status = GamutCheckStatus::invalid_input;
        return result;
    }

    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint8_t* const row = pixels + (static_cast<std::size_t>(y) * stride_bytes);
        std::uint8_t* const target_row =
            probe.data() + (static_cast<std::size_t>(y) * width * 3U);
        for (std::uint32_t x = 0U; x < width * 3U; ++x) {
            const std::uint8_t value = row[x];
            target_row[x] = value < 1U ? 1U : (value > 254U ? 254U : value);
        }
    }

    const MemoryProfile source(source_bytes);
    const MemoryProfile target(destination_bytes);
    if (source.get() == nullptr || target.get() == nullptr) {
        result.status = GamutCheckStatus::profile_unavailable;
        result.native_error_code = source.get() == nullptr ? source.error() : target.error();
        result.out_of_gamut.clear();
        return result;
    }

    const Transform transform(source.get(), target.get());
    if (transform.get() == nullptr) {
        result.status = GamutCheckStatus::transform_unavailable;
        result.native_error_code = transform.error();
        result.out_of_gamut.clear();
        return result;
    }

    if (CheckBitmapBits(
            transform.get(),
            probe.data(),
            BM_BGRTRIPLETS,
            width,
            height,
            width * 3U,
            result.out_of_gamut.data(),
            nullptr,
            0U) == FALSE) {
        result.status = GamutCheckStatus::check_failed;
        result.native_error_code = static_cast<std::uint32_t>(GetLastError());
        result.out_of_gamut.clear();
        return result;
    }

    for (const std::uint8_t flag : result.out_of_gamut) {
        if (flag != 0U) {
            ++result.out_of_gamut_count;
        }
    }
    return result;
}

}  // namespace negaflow::color
