#include "negaflow/gpu/gpu_working_image.h"

#include <cstdint>
#include <iostream>
#include <string_view>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_image_pool.h"

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuStagingRing;
using negaflow::gpu::GpuWorkingImage;

// 화소마다 다른 값을 넣어 행·열이 뒤바뀌면 시험이 잡도록 합니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels) {
    std::vector<Rgba32F> pixels(
        static_cast<std::size_t>(stride_pixels) * height, Rgba32F{-1.0F, -1.0F, -1.0F, -1.0F});
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const auto index = (static_cast<std::size_t>(y) * stride_pixels) + x;
            pixels[index] = Rgba32F{
                static_cast<float>(x) * 0.125F,
                static_cast<float>(y) * 0.25F,
                static_cast<float>(x + y) * 0.5F,
                1.0F};
        }
    }
    return pixels;
}

[[nodiscard]] bool same_pixel(const Rgba32F& left, const Rgba32F& right) noexcept {
    // 왕복은 무손실이어야 합니다 — float32 를 float32 텍스처에 넣었다 빼는 것이라
    // 오차가 있으면 포맷이나 행 피치를 잘못 다룬 것입니다.
    return left.red == right.red && left.green == right.green && left.blue == right.blue &&
        left.alpha == right.alpha;
}

// 이 왕복이 정확해야 이후 커널 동치 시험(허용 오차 1e-5)이 의미를 갖습니다.
// 여기서 값이 흔들리면 커널이 맞아도 결과가 틀립니다.
void round_trip_is_lossless(const GpuDevice& device, const char* const label) {
    constexpr std::uint32_t width = 61U;
    constexpr std::uint32_t height = 37U;
    // 폭과 다른 stride 를 일부러 씁니다. GPU 행 피치는 드라이버가 정하므로(256바이트 정렬이
    // 흔합니다) 양쪽 피치를 모두 제대로 다루는지 봅니다.
    constexpr std::uint32_t stride = width + 7U;

    const std::vector<Rgba32F> source = make_pattern(width, height, stride);
    GpuWorkingImage image{};
    const GpuImageStatus uploaded =
        GpuWorkingImage::upload(device, source.data(), width, height, stride, image);
    expect(uploaded == GpuImageStatus::ok, "upload must succeed");
    if (uploaded != GpuImageStatus::ok) {
        return;
    }
    expect(image.is_valid(), "uploaded image is valid");
    expect(image.width() == width && image.height() == height, "uploaded extent matches");
    expect(image.srv() != nullptr, "image exposes an SRV");
    expect(image.uav() != nullptr, "image exposes a UAV");

    std::vector<Rgba32F> destination(
        static_cast<std::size_t>(stride) * height, Rgba32F{-2.0F, -2.0F, -2.0F, -2.0F});
    const GpuImageStatus downloaded = image.download(device, destination.data(), stride);
    expect(downloaded == GpuImageStatus::ok, "download must succeed");
    if (downloaded != GpuImageStatus::ok) {
        return;
    }

    bool identical = true;
    bool padding_untouched = true;
    for (std::uint32_t y = 0U; y < height && identical; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const auto index = (static_cast<std::size_t>(y) * stride) + x;
            if (!same_pixel(source[index], destination[index])) {
                identical = false;
                std::cerr << "  first mismatch at (" << x << ',' << y << ") on " << label << '\n';
                break;
            }
        }
        // 행 여백은 건드리지 않아야 합니다 — 건드리면 stride 계산이 틀린 것입니다.
        for (std::uint32_t x = width; x < stride; ++x) {
            const auto index = (static_cast<std::size_t>(y) * stride) + x;
            if (destination[index].red != -2.0F) {
                padding_untouched = false;
            }
        }
    }
    expect(identical, "round trip must be bit-exact");
    expect(padding_untouched, "row padding must not be written");
}

void rejects_bad_input(const GpuDevice& device) {
    GpuWorkingImage image{};
    expect(
        GpuWorkingImage::create(device, 0U, 8U, image) == GpuImageStatus::invalid_dimensions,
        "zero width is rejected");
    expect(
        GpuWorkingImage::create(device, 8U, 0U, image) == GpuImageStatus::invalid_dimensions,
        "zero height is rejected");

    const std::vector<Rgba32F> pixels(64U, Rgba32F{0.0F, 0.0F, 0.0F, 1.0F});
    expect(
        GpuWorkingImage::upload(device, pixels.data(), 8U, 8U, 4U, image) ==
            GpuImageStatus::invalid_dimensions,
        "stride smaller than width is rejected");
    expect(
        GpuWorkingImage::upload(device, nullptr, 8U, 8U, 8U, image) ==
            GpuImageStatus::buffer_size_mismatch,
        "null pixels are rejected");

    // 상한을 넘으면 조용히 자르지 않고 그렇게 말해야 합니다. 호출부가 타일로 나눕니다.
    const std::uint32_t limit = device.capability().max_texture_dimension;
    expect(limit != 0U, "capability reports a texture dimension limit");
    if (limit != 0U) {
        expect(
            GpuWorkingImage::create(device, limit + 1U, 8U, image) ==
                GpuImageStatus::dimension_limit_exceeded,
            "over-limit width is reported, not truncated");
    }
}

// 링은 첫 회전에서 아직 내놓을 것이 없고, 두 번째부터 프레임을 냅니다.
void staging_ring_defers_the_first_frame(const GpuDevice& device) {
    constexpr std::uint32_t width = 16U;
    constexpr std::uint32_t height = 9U;
    const std::vector<Rgba32F> source = make_pattern(width, height, width);

    GpuWorkingImage image{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, image) !=
        GpuImageStatus::ok) {
        expect(false, "ring test needs an uploaded image");
        return;
    }

    GpuStagingRing ring{};
    const GpuImageStatus created =
        GpuStagingRing::create(device, width, height, GpuStagingRing::default_depth, ring);
    expect(created == GpuImageStatus::ok, "ring must be creatable");
    if (created != GpuImageStatus::ok) {
        return;
    }
    expect(ring.depth() == GpuStagingRing::default_depth, "ring keeps the requested depth");

    std::vector<Rgba32F> destination(
        static_cast<std::size_t>(width) * height, Rgba32F{-3.0F, -3.0F, -3.0F, -3.0F});

    bool produced = true;
    expect(
        ring.rotate(device, image, destination.data(), width, produced) == GpuImageStatus::ok,
        "first rotate succeeds");
    expect(!produced, "first rotate has nothing to hand back yet");

    expect(
        ring.rotate(device, image, destination.data(), width, produced) == GpuImageStatus::ok,
        "second rotate succeeds");
    expect(produced, "second rotate hands back a frame");
    if (produced) {
        expect(same_pixel(source[0], destination[0]), "ring frame matches the source");
        const auto last = (static_cast<std::size_t>(height - 1U) * width) + (width - 1U);
        expect(same_pixel(source[last], destination[last]), "ring frame last pixel matches");
    }

    // 깊이를 1로 달라고 해도 링이 되도록 올려 줍니다 — 한 장이면 매번 GPU 를 기다립니다.
    GpuStagingRing shallow{};
    expect(
        GpuStagingRing::create(device, width, height, 1U, shallow) == GpuImageStatus::ok,
        "depth 1 is accepted");
    expect(shallow.depth() >= 2U, "depth 1 is raised to a real ring");
}

void status_names_are_stable() {
    using negaflow::gpu::gpu_image_status_name;
    expect(std::string_view{gpu_image_status_name(GpuImageStatus::ok)} == "ok", "ok name");
    expect(
        std::string_view{gpu_image_status_name(GpuImageStatus::dimension_limit_exceeded)} ==
            "dimension_limit_exceeded",
        "dimension_limit_exceeded name");
    expect(
        std::string_view{gpu_image_status_name(GpuImageStatus::device_unavailable)} ==
            "device_unavailable",
        "device_unavailable name");
}

// 장치가 없으면 조용히 성공하면 안 됩니다 — 호출부가 CPU 로 가야 하기 때문입니다.
void same_size_upload_keeps_the_texture(const GpuDevice& device) {
    constexpr std::uint32_t width = 32U;
    constexpr std::uint32_t height = 24U;
    const std::vector<Rgba32F> first = make_pattern(width, height, width);
    const std::vector<Rgba32F> second = make_pattern(width, height, width);
    GpuWorkingImage image{};
    expect(
        GpuWorkingImage::upload(device, first.data(), width, height, width, image) ==
            GpuImageStatus::ok,
        "first upload succeeds");
    ID3D11Texture2D* const kept = image.texture();
    expect(kept != nullptr, "first upload created a texture");
    expect(
        GpuWorkingImage::upload(device, second.data(), width, height, width, image) ==
            GpuImageStatus::ok,
        "second same-size upload succeeds");
    expect(image.texture() == kept, "same-size upload must not recreate the texture");

    const std::vector<Rgba32F> smaller = make_pattern(16U, 16U, 16U);
    expect(
        GpuWorkingImage::upload(device, smaller.data(), 16U, 16U, 16U, image) ==
            GpuImageStatus::ok,
        "resized upload succeeds");
    expect(image.texture() != kept, "a new size must allocate a new texture");
}

void pool_follows_the_adapter_memory_budget(const GpuDevice& device) {
    using negaflow::gpu::GpuImagePool;
    GpuImagePool pool{};
    expect(pool.ensure(device, 64U, 48U), "first pool size");
    ID3D11Texture2D* const first = pool.images()[0].texture();
    expect(first != nullptr, "pool created textures");
    expect(pool.ensure(device, 32U, 24U), "second pool size");
    ID3D11Texture2D* const second = pool.images()[0].texture();
    expect(second != nullptr, "new size has a texture");

    negaflow::gpu::GpuVideoMemoryInfo memory{};
    const bool expected_retention =
        !device.capability().adapter.is_integrated &&
        device.query_local_video_memory_info(memory) &&
        memory.current_usage <= memory.budget;
    expect(
        pool.has_retained_size(64U, 48U) == expected_retention,
        "previous size residency follows adapter architecture and DXGI budget");
    if (expected_retention) {
        expect(second != first, "retained and current sizes use different textures");
    }

    expect(pool.ensure(device, 64U, 48U), "return to first size");
    if (expected_retention) {
        expect(
            pool.images()[0].texture() == first,
            "discrete GPU reuses the retained size while inside budget");
    } else {
        expect(
            !pool.has_retained_size(32U, 24U),
            "shared or unbudgeted GPU keeps only one texture size");
    }
    expect(pool.ensure(device, 32U, 24U), "return to second size");
    if (expected_retention) {
        expect(
            pool.images()[0].texture() == second,
            "discrete GPU reuses the other retained size while inside budget");
    } else {
        expect(
            !pool.has_retained_size(64U, 48U),
            "shared or unbudgeted GPU still keeps one size after another switch");
    }
}

void unusable_device_is_reported() {
    const GpuDevice empty{};
    expect(!empty.is_usable(), "default-constructed device is unusable");
    GpuWorkingImage image{};
    expect(
        GpuWorkingImage::create(empty, 8U, 8U, image) == GpuImageStatus::device_unavailable,
        "create on an unusable device reports device_unavailable");
}

}  // namespace

int main() {
    // WARP 로 먼저 돕니다. 하드웨어가 없는 CI 에서도 이 시험 전체가 의미를 갖게 하기 위해서입니다.
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    round_trip_is_lossless(warp, "warp");
    rejects_bad_input(warp);
    staging_ring_defers_the_first_frame(warp);
    same_size_upload_keeps_the_texture(warp);
    pool_follows_the_adapter_memory_budget(warp);

    // 하드웨어가 있으면 같은 것을 하드웨어에서도 봅니다. 없으면 건너뜁니다 —
    // 이 시험은 GPU 유무가 아니라 왕복의 정확성을 봅니다.
    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] also checking on: " << hardware.capability().adapter.description.data()
                  << '\n';
        round_trip_is_lossless(hardware, "hardware");
        rejects_bad_input(hardware);
        staging_ring_defers_the_first_frame(hardware);
        same_size_upload_keeps_the_texture(hardware);
        pool_follows_the_adapter_memory_budget(hardware);
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    status_names_are_stable();
    unusable_device_is_reported();

    if (failures != 0) {
        std::cerr << failures << " gpu working image check(s) failed\n";
        return 1;
    }
    std::cout << "gpu working image checks passed\n";
    return 0;
}
