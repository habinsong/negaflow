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

namespace {

/// 목적지 프로파일 바이트를 받아 판정합니다. 두 진입점이 같은 몸통을 씁니다.
[[nodiscard]] GamutCheckResult check_with_destination(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    std::vector<std::uint8_t>&& destination_profile) {
    GamutCheckResult result{};
    if (pixels == nullptr || width == 0U || height == 0U ||
        stride_bytes < static_cast<std::uint64_t>(width) * 3ULL) {
        result.status = GamutCheckStatus::invalid_input;
        return result;
    }

    std::vector<std::uint8_t> source_bytes;
    std::vector<std::uint8_t> destination_bytes = std::move(destination_profile);
    // ICM 은 같은 RGB 색역의 수학적 경계(정확한 0/255)를 반올림 때문에 바깥으로 판정합니다.
    // 그대로 두면 sRGB 그림을 sRGB 로 프루프할 때 흰색과 검정이 전부 경고로 뜹니다.
    // **판정 전용 사본만** 1 LSB 안쪽으로 밀어 그 거짓 경고를 막습니다 — 화면·현상·내보내기
    // 화소는 건드리지 않습니다. macOS 도 같은 이유로 같은 일을 합니다.
    std::vector<std::uint8_t> probe;
    const std::uint32_t probe_stride = ((width * 3U) + 3U) & ~3U;
    try {
        source_bytes = source_profile_bytes();
        result.out_of_gamut.assign(
            static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0U);
        // ICM 의 비트맵 함수는 각 행이 4바이트 경계에서 시작하기를 요구합니다. `너비 × 3`
        // 을 그대로 쓰면 너비가 4의 배수가 아닐 때 행이 조금씩 밀려, 위쪽 몇 줄만 맞고
        // 아래로 갈수록 엉뚱한 화소를 판정합니다.
        probe.assign(static_cast<std::size_t>(probe_stride) * height, 0U);
    } catch (const std::bad_alloc&) {
        result.status = GamutCheckStatus::invalid_input;
        return result;
    }

    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint8_t* const row = pixels + (static_cast<std::size_t>(y) * stride_bytes);
        std::uint8_t* const target_row =
            probe.data() + (static_cast<std::size_t>(y) * probe_stride);
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

    // 한 줄씩 판정합니다.
    //
    // 여러 줄을 한 번에 넘기면 ICM 이 <b>도중에 멈추고도 성공을 돌려줍니다</b>. 실측(900x602,
    // 인화소 프로파일): 한 번에 넘기면 341행까지만 표시되고 그 아래는 한 점도 없는데,
    // 한 줄씩 넘기면 602행 전부에 표시가 납니다(61,685 대 146,226). 그래서 "사진 윗부분만
    // 빨갛다" 로 보였습니다. 변환은 한 번만 만들어 두고 줄만 돌립니다.
    for (std::uint32_t y = 0U; y < height; ++y) {
        if (CheckBitmapBits(
                transform.get(),
                probe.data() + (static_cast<std::size_t>(y) * probe_stride),
                BM_BGRTRIPLETS,
                width,
                1U,
                probe_stride,
                result.out_of_gamut.data() + (static_cast<std::size_t>(y) * width),
                nullptr,
                0U) == FALSE) {
            result.status = GamutCheckStatus::check_failed;
            result.native_error_code = static_cast<std::uint32_t>(GetLastError());
            result.out_of_gamut.clear();
            return result;
        }
    }


    for (const std::uint8_t flag : result.out_of_gamut) {
        if (flag != 0U) {
            ++result.out_of_gamut_count;
        }
    }
    return result;
}

}  // namespace

GamutCheckResult check_gamut_bgr8(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    const OutputColorSpace destination) {
    try {
        return check_with_destination(
            pixels, width, height, stride_bytes, build_icc_profile(destination));
    } catch (const std::bad_alloc&) {
        GamutCheckResult result{};
        result.status = GamutCheckStatus::invalid_input;
        return result;
    }
}

GamutCheckResult check_gamut_bgr8_icc(
    const std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    const std::uint8_t* const destination_icc,
    const std::uint32_t destination_icc_size) {
    GamutCheckResult result{};
    if (destination_icc == nullptr || destination_icc_size == 0U) {
        result.status = GamutCheckStatus::profile_unavailable;
        return result;
    }
    try {
        std::vector<std::uint8_t> bytes(
            destination_icc, destination_icc + destination_icc_size);
        return check_with_destination(pixels, width, height, stride_bytes, std::move(bytes));
    } catch (const std::bad_alloc&) {
        result.status = GamutCheckStatus::invalid_input;
        return result;
    }
}

bool soft_proof_convert_bgra_icc(
    std::uint8_t* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    const std::uint8_t* const destination_icc,
    const std::uint32_t destination_icc_size) noexcept {
    if (pixels == nullptr || destination_icc == nullptr || destination_icc_size == 0U ||
        width == 0U || height == 0U ||
        stride_bytes < static_cast<std::uint64_t>(width) * 4ULL) {
        return false;
    }
    std::vector<std::uint8_t> source_bytes;
    std::vector<std::uint8_t> destination_bytes;
    std::vector<std::uint8_t> bgr;
    // ICM 은 행마다 4바이트 경계를 요구합니다.
    const std::uint32_t packed_stride = ((width * 3U) + 3U) & ~3U;
    try {
        source_bytes = source_profile_bytes();
        destination_bytes.assign(destination_icc, destination_icc + destination_icc_size);
        bgr.resize(static_cast<std::size_t>(packed_stride) * height);
    } catch (const std::bad_alloc&) {
        return false;
    }

    for (std::uint32_t y = 0U; y < height; ++y) {
        const std::uint8_t* const row = pixels + (static_cast<std::size_t>(y) * stride_bytes);
        std::uint8_t* const target = bgr.data() + (static_cast<std::size_t>(y) * packed_stride);
        for (std::uint32_t x = 0U; x < width; ++x) {
            target[(x * 3U)] = row[(x * 4U)];
            target[(x * 3U) + 1U] = row[(x * 4U) + 1U];
            target[(x * 3U) + 2U] = row[(x * 4U) + 2U];
        }
    }

    MemoryProfile display(source_bytes);
    MemoryProfile paper(destination_bytes);
    if (display.get() == nullptr || paper.get() == nullptr) {
        return false;
    }
    // 화면 -> 인화지 -> 화면. 가운데가 인화지라 그 색역 밖의 색이 눌립니다.
    HPROFILE profiles[]{display.get(), paper.get(), display.get()};
    DWORD intents[]{
        INTENT_RELATIVE_COLORIMETRIC,
        INTENT_RELATIVE_COLORIMETRIC,
        INTENT_RELATIVE_COLORIMETRIC};
    HTRANSFORM transform = CreateMultiProfileTransform(
        profiles, 3U, intents, 3U, USE_RELATIVE_COLORIMETRIC, INDEX_DONT_CARE);
    if (transform == nullptr) {
        return false;
    }
    const BOOL translated = TranslateBitmapBits(
        transform,
        bgr.data(),
        BM_BGRTRIPLETS,
        width,
        height,
        packed_stride,
        bgr.data(),
        BM_BGRTRIPLETS,
        packed_stride,
        nullptr,
        0);
    static_cast<void>(DeleteColorTransform(transform));
    if (translated == FALSE) {
        return false;
    }

    for (std::uint32_t y = 0U; y < height; ++y) {
        std::uint8_t* const row = pixels + (static_cast<std::size_t>(y) * stride_bytes);
        const std::uint8_t* const source =
            bgr.data() + (static_cast<std::size_t>(y) * packed_stride);
        for (std::uint32_t x = 0U; x < width; ++x) {
            row[(x * 4U)] = source[(x * 3U)];
            row[(x * 4U) + 1U] = source[(x * 3U) + 1U];
            row[(x * 4U) + 2U] = source[(x * 3U) + 2U];
        }
    }
    return true;
}
}  // namespace negaflow::color
