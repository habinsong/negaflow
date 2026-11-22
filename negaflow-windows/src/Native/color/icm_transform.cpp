#include "negaflow/color/icm_transform.h"

namespace negaflow::color {

HTRANSFORM create_icm_transform(
    HPROFILE* const profiles,
    const DWORD profile_count,
    const bool round_trip_proof,
    std::uint32_t& native_error_code) noexcept {
    native_error_code = 0U;
    if (profiles == nullptr || profile_count < 2U || profile_count > 3U) {
        return nullptr;
    }

    DWORD primary_intents[3]{
        INTENT_RELATIVE_COLORIMETRIC,
        INTENT_RELATIVE_COLORIMETRIC,
        INTENT_RELATIVE_COLORIMETRIC};
    const DWORD primary_flags = round_trip_proof
        ? (USE_RELATIVE_COLORIMETRIC | BEST_MODE)
        : BEST_MODE;
    const DWORD primary_intent_count = round_trip_proof ? profile_count : 1U;
    SetLastError(ERROR_SUCCESS);
    if (HTRANSFORM transform = CreateMultiProfileTransform(
            profiles,
            profile_count,
            primary_intents,
            primary_intent_count,
            primary_flags,
            INDEX_DONT_CARE);
        transform != nullptr) {
        return transform;
    }
    const std::uint32_t primary_error = static_cast<std::uint32_t>(GetLastError());

    struct Attempt final {
        DWORD intent;
        DWORD flags;
    };
    const Attempt fallbacks[]{
        {INTENT_PERCEPTUAL, BEST_MODE},
        {INTENT_RELATIVE_COLORIMETRIC, WCS_ALWAYS | BEST_MODE},
        {INTENT_PERCEPTUAL, WCS_ALWAYS | BEST_MODE},
    };
    for (const Attempt& attempt : fallbacks) {
        DWORD intent = attempt.intent;
        SetLastError(ERROR_SUCCESS);
        if (HTRANSFORM transform = CreateMultiProfileTransform(
                profiles, profile_count, &intent, 1U, attempt.flags, INDEX_DONT_CARE);
            transform != nullptr) {
            return transform;
        }
    }
    const std::uint32_t fallback_error = static_cast<std::uint32_t>(GetLastError());
    native_error_code = primary_error != 0U ? primary_error : fallback_error;
    return nullptr;
}

}  // namespace negaflow::color
