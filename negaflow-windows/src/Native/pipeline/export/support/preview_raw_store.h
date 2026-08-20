#pragma once

#include "export/support/preview_proxy.h"

#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>
#include <filesystem>
#include <memory>

namespace negaflow::pipeline::develop_export_detail {

// macOS `ScanFrame.cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw` 자리입니다.
//
// ☠️ macOS 는 이 두 슬롯을 **프레임(`ScanFrame`)에 붙여** 둡니다. Windows 앞 판은
//    번역 단위의 **프로세스 전역 두 개**로 옮겼는데, 그 순간 두 가지가 깨졌습니다.
//    ① 썸네일 렌더(`ThumbnailService`, 상자 360)도 같은 `develop_preview` 를 지나므로
//       현상 슬라이더가 쓰는 슬롯을 계속 덮어썼습니다 — 캐시가 매번 빗나가 슬라이더 한
//       칸마다 원본 재디코드 + 원본 해상도 베이스 해석 + Lanczos 를 다시 했습니다.
//    ② 그 전역에 잠금이 없어, 썸네일 스레드의 슬롯 교체와 프리뷰 스레드의 읽기가 겹쳐
//       use-after-free 가 났습니다(이벤트 로그 0xc0000374 힙 손상 · 0xc0000409 abort).
//
// 그래서 프레임 키로 나누고, 잠금을 걸고, 화상은 `shared_ptr<const>` 로 넘깁니다 —
// 꺼내 간 쪽이 참조를 들고 있는 동안 그 버퍼는 절대 해제되지 않습니다.
using PreviewRawImage = std::shared_ptr<const negaflow::imaging::WorkingImage>;

// 슬롯을 무효로 만드는 것 전부입니다. macOS `cleanRawRevision` 대응이 관측이고,
// 나머지는 베이스 해석 결과가 달라지는 입력입니다.
struct PreviewRawKey final {
    std::filesystem::path path{};
    negaflow::imageio::ImageFileObservation observation{};
    NegativeBaseEstimationMode base_mode{NegativeBaseEstimationMode::manual};
    negaflow::imaging::NegativeFilmType film_type{
        negaflow::imaging::NegativeFilmType::color};
    FilmPolarity polarity{FilmPolarity::negative};
    bool has_preset{false};
    std::array<float, 3> preset_dmin{};
    std::array<float, 3> preset_dmax{};
    std::array<float, 3> preset_light_gain{};
};

[[nodiscard]] bool same_preview_raw_key(
    const PreviewRawKey& left,
    const PreviewRawKey& right) noexcept;

// macOS `cachedSettledPreviewRaw(for:)`.
[[nodiscard]] bool preview_raw_take_settled(
    const PreviewRawKey& key,
    PreviewRawImage& image,
    PreviewProxyHint& hint) noexcept;

// macOS `cachedPreviewRaw(for:maxDimension:)` 의 인터랙티브 갈래 —
// **같은 치수로 만들었던** 슬롯만 씁니다(`cachedInteractivePreviewRawDimension`).
[[nodiscard]] bool preview_raw_take_interactive(
    const PreviewRawKey& key,
    std::uint32_t box_width,
    std::uint32_t box_height,
    PreviewRawImage& image,
    PreviewProxyHint& hint) noexcept;

// macOS `applyPreviewRawCache(_:to:maxDimension:)`.
void preview_raw_put_settled(
    const PreviewRawKey& key,
    PreviewRawImage image,
    const PreviewProxyHint& hint) noexcept;

void preview_raw_put_interactive(
    const PreviewRawKey& key,
    std::uint32_t box_width,
    std::uint32_t box_height,
    PreviewRawImage image,
    const PreviewProxyHint& hint) noexcept;

// 시험이 캐시를 비우고 시작할 수 있게 열어 둡니다.
void preview_raw_store_reset() noexcept;

// 지금 상주 중인 바이트. 예산이 지켜지는지 시험이 확인합니다.
[[nodiscard]] std::uint64_t preview_raw_store_resident_bytes() noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
