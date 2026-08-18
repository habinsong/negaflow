#pragma once

// GPU 에 올라간 작업 이미지입니다. `negaflow::imaging::WorkingImage` 의 화소 배열과 같은
// 레이아웃(`core::Rgba32F` = float32 RGBA)을 `DXGI_FORMAT_R32G32B32A32_FLOAT` 로 담습니다.
//
// 왜 float32 인가 — macOS 는 `CIContext` 에 `.workingFormat` 을 주지 않아 Core Image 기본인
// half float 로 돕니다. Windows CPU 파이프라인은 이미 float32 이고, **그 차이는 이 작업이
// 만드는 것이 아닙니다.** GPU 를 float32 로 두어야 CPU 결과와 `1e-5` 로 묶어 "정확히 옮겼다"를
// 시험으로 증명할 수 있습니다. half 로 내리면 이식 실수와 반올림을 못 가립니다.
//
// 왜 GPU 에 머무는가 — Core Image 는 `CIImage` 체인을 지연 합성해 마지막에 한 번 평가합니다.
// 중간 결과가 호스트로 내려오지 않습니다. Windows 파이프라인은 단계마다 호스트 `WorkingImage&`
// 를 넘기므로, 단계마다 왕복하면 전송이 커널 이득을 먹습니다. 그래서 올리기 1회·내리기 1회입니다.

#include <cstddef>
#include <cstdint>
#include <vector>

#include "negaflow/core/pixel.h"

struct ID3D11Texture2D;
struct ID3D11ShaderResourceView;
struct ID3D11UnorderedAccessView;

namespace negaflow::gpu {

class GpuDevice;

enum class GpuImageStatus : std::uint8_t {
    ok = 0,
    // 장치가 없습니다. 호출부는 CPU 경로로 가야 합니다.
    device_unavailable,
    // 폭·높이가 0 이거나 stride 가 폭보다 작습니다.
    invalid_dimensions,
    // 기능 수준 11_0 의 Texture2D 한 변 상한(16384)을 넘었습니다. 타일로 잘라야 합니다.
    dimension_limit_exceeded,
    // 화소 배열 크기가 stride×height 와 맞지 않습니다.
    buffer_size_mismatch,
    // 텍스처·뷰 생성 실패. 대개 메모리 부족입니다(내장 GPU 에서 잘 납니다).
    allocation_failed,
    // 스테이징 매핑 실패.
    map_failed,
};

[[nodiscard]] const char* gpu_image_status_name(GpuImageStatus status) noexcept;

// SRV(읽기) 와 UAV(쓰기) 를 함께 가진 float32 RGBA 텍스처 한 장입니다.
// 컴퓨트 패스는 한 장을 읽고 다른 장에 씁니다 — 같은 자원을 SRV·UAV 로 동시에 묶을 수 없습니다.
class GpuWorkingImage final {
public:
    GpuWorkingImage() noexcept = default;
    ~GpuWorkingImage();

    GpuWorkingImage(const GpuWorkingImage&) = delete;
    GpuWorkingImage& operator=(const GpuWorkingImage&) = delete;
    GpuWorkingImage(GpuWorkingImage&& other) noexcept;
    GpuWorkingImage& operator=(GpuWorkingImage&& other) noexcept;

    // 빈 텍스처를 만듭니다. 내용은 정해지지 않습니다.
    [[nodiscard]] static GpuImageStatus create(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height,
        GpuWorkingImage& image) noexcept;

    // 호스트 화소를 올립니다. `stride_pixels` 가 `width` 보다 크면 행 여백을 건너뜁니다.
    // 현상 1회당 한 번 부르는 경로라 `UpdateSubresource` 로 충분합니다. 매 프레임 올리는
    // 경로가 생기면 그때 DYNAMIC 업로드 텍스처 + `CopyResource` 로 바꾸십시오
    // (DYNAMIC 텍스처에는 UAV 를 걸 수 없어서 별도 자원이 필요합니다).
    [[nodiscard]] static GpuImageStatus upload(
        const GpuDevice& device,
        const core::Rgba32F* pixels,
        std::uint32_t width,
        std::uint32_t height,
        std::uint32_t stride_pixels,
        GpuWorkingImage& image) noexcept;

    // 이미 만들어 둔 텍스처에 호스트 화소를 **덮어씁니다.** 위 정적 판과 달리 자원을
    // 다시 만들지 않으므로, 텍스처를 풀로 들고 재사용하는 경로가 쓸 수 있습니다
    // (사슬 오케스트레이터가 그렇습니다 — 프레임마다 여섯 장을 다시 만들면 그 비용이
    // 커널보다 큽니다).
    [[nodiscard]] GpuImageStatus upload_into(
        const GpuDevice& device,
        const core::Rgba32F* pixels,
        std::uint32_t stride_pixels) const noexcept;

    // GPU → 호스트. 스테이징 텍스처를 거칩니다(D3D11 은 이것 말고 읽는 길이 없습니다).
    // ☠️ D3D11 의 `Map` 은 **동기화합니다** — 밀린 GPU 작업이 끝날 때까지 CPU 가 멈춥니다.
    //    매 프레임 내리는 경로에서는 `GpuStagingRing` 을 쓰십시오.
    [[nodiscard]] GpuImageStatus download(
        const GpuDevice& device,
        core::Rgba32F* pixels,
        std::uint32_t stride_pixels) const noexcept;

    // 같은 크기의 다른 텍스처 내용을 그대로 가져옵니다. CPU 커널들이 "변화 없음" 일 때
    // `copy_validated_rows` 로 원본을 그대로 내보내는 것과 같은 자리입니다 — 그때 커널을
    // 돌리면 클램프 같은 부수효과가 붙어 CPU 와 값이 갈립니다.
    [[nodiscard]] GpuImageStatus copy_from(
        const GpuDevice& device,
        const GpuWorkingImage& source) noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return texture_ != nullptr; }
    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }

    [[nodiscard]] ID3D11Texture2D* texture() const noexcept { return texture_; }
    [[nodiscard]] ID3D11ShaderResourceView* srv() const noexcept { return srv_; }
    [[nodiscard]] ID3D11UnorderedAccessView* uav() const noexcept { return uav_; }

private:
    void reset() noexcept;

    ID3D11Texture2D* texture_{nullptr};
    ID3D11ShaderResourceView* srv_{nullptr};
    ID3D11UnorderedAccessView* uav_{nullptr};
    // ☠️ 회수용 스테이징을 **들고 있습니다.** 앞 판은 `download` 마다 만들고 지웠는데,
    //    24MP 에서 그것이 264 MB 할당·해제입니다. 실측으로 다운로드가 76~133 ms 였고
    //    업로드는 45 ms 였습니다 — 그 차이의 큰 몫이 이 할당이었습니다.
    //    `mutable` 인 이유는 `download` 가 `const` 이기 때문입니다(이미지 내용은 안 바뀝니다).
    mutable ID3D11Texture2D* staging_{nullptr};
    // 올리기용 스테이징. 읽기용과 나눠 두는 이유는 CPU 접근 플래그가 반대이고,
    // 한 텍스처에 READ|WRITE 를 같이 주면 드라이버가 읽기 쪽 캐시 정책을 낮추기 때문입니다.
    mutable ID3D11Texture2D* upload_staging_{nullptr};
    std::uint32_t width_{0};
    std::uint32_t height_{0};
};

// 스테이징 텍스처를 여러 장 돌려 씁니다. N 프레임을 GPU 가 쓰는 동안 N−1 프레임을 CPU 가 읽어
// `Map` 의 동기화 정지를 피합니다. 한 장만 쓰면 프리뷰가 매 프레임 GPU 를 기다립니다.
class GpuStagingRing final {
public:
    // 두 장이 하한입니다. 더 늘리면 지연이 늘고 메모리를 더 씁니다.
    static constexpr std::size_t default_depth = 2U;

    GpuStagingRing() noexcept = default;
    ~GpuStagingRing();

    GpuStagingRing(const GpuStagingRing&) = delete;
    GpuStagingRing& operator=(const GpuStagingRing&) = delete;
    GpuStagingRing(GpuStagingRing&& other) noexcept;
    GpuStagingRing& operator=(GpuStagingRing&& other) noexcept;

    [[nodiscard]] static GpuImageStatus create(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height,
        std::size_t depth,
        GpuStagingRing& ring) noexcept;

    // 다음 칸으로 복사를 걸고, **직전 칸**을 읽어 냅니다. 첫 호출은 읽을 것이 없으므로
    // `ok` 와 함께 `produced=false` 를 돌려줍니다 — 호출부는 그 프레임을 건너뜁니다.
    [[nodiscard]] GpuImageStatus rotate(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        core::Rgba32F* pixels,
        std::uint32_t stride_pixels,
        bool& produced) noexcept;

    [[nodiscard]] std::size_t depth() const noexcept { return slots_.size(); }

private:
    void reset() noexcept;

    std::vector<ID3D11Texture2D*> slots_{};
    std::vector<bool> pending_{};
    std::size_t next_{0};
    std::uint32_t width_{0};
    std::uint32_t height_{0};
};

}  // namespace negaflow::gpu
