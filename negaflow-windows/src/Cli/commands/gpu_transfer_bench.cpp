#include "gpu_transfer_bench.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_negative_invert.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::cli {
namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuNegativeInvert;
using negaflow::gpu::GpuWorkingImage;

[[nodiscard]] double milliseconds_since(
    const std::chrono::steady_clock::time_point started) noexcept {
    return static_cast<double>(
               std::chrono::duration_cast<std::chrono::microseconds>(
                   std::chrono::steady_clock::now() - started)
                   .count()) /
           1000.0;
}

[[nodiscard]] bool parse_dimension(
    const std::wstring_view text,
    std::uint32_t& value) noexcept {
    try {
        const std::wstring copy{text};
        std::size_t consumed = 0U;
        const unsigned long parsed = std::stoul(copy, &consumed);
        if (consumed != copy.size() || parsed == 0UL || parsed > 20000UL) {
            return false;
        }
        value = static_cast<std::uint32_t>(parsed);
        return true;
    } catch (...) {
        return false;
    }
}

int usage() {
    std::cerr << "usage: negaflow-cli --gpu-transfer-bench [width] [height] [repeats]\n"
                 "  기본은 5088x3401 (실제 OpticFilm 스캔 크기), 5회입니다.\n";
    return 2;
}

}  // namespace

int run_gpu_transfer_bench(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count > 5) {
        return usage();
    }
    // 사용자의 실제 스캔 크기입니다. 문서의 24MP 산술과 견주려면 여기서 재야 합니다.
    std::uint32_t width = 5088U;
    std::uint32_t height = 3401U;
    int repeats = 5;
    if (argument_count >= 4) {
        if (!parse_dimension(arguments[2], width) || !parse_dimension(arguments[3], height)) {
            return usage();
        }
    }
    if (argument_count == 5) {
        std::uint32_t parsed = 0U;
        if (!parse_dimension(arguments[4], parsed) || parsed > 50U) {
            return usage();
        }
        repeats = static_cast<int>(parsed);
    }

    const GpuDevice device = GpuDevice::create(GpuDevicePreference::automatic);
    if (!device.is_usable()) {
        std::cerr << "gpu unavailable\n";
        return 1;
    }

    const std::size_t count = static_cast<std::size_t>(width) * height;
    const double megabytes =
        static_cast<double>(count * sizeof(Rgba32F)) / (1024.0 * 1024.0);
    std::vector<Rgba32F> host(count, Rgba32F{0.25F, 0.5F, 0.75F, 1.0F});
    std::vector<Rgba32F> readback(count);

    GpuWorkingImage source{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::create(device, width, height, source) != GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, destination) != GpuImageStatus::ok) {
        std::cerr << "texture creation failed\n";
        return 1;
    }
    // 커널 하나를 같이 돌려 "전송 대 커널" 비율을 함께 봅니다. 반전은 현상에서 가장
    // 비싼 화소별 커널입니다(채널마다 `log10`·`pow`·`exp`).
    GpuNegativeInvert invert{};
    const bool has_kernel = GpuNegativeInvert::create(device, invert) == GpuKernelStatus::ok;
    negaflow::gpu::GpuNegativeInvertParameters parameters{};
    for (int channel = 0; channel < 3; ++channel) {
        parameters.dmin[channel] = 0.9F;
        parameters.dmax_normalized[channel] = 1.8F;
    }
    parameters.response_y_ceiling = 0.0F;
    parameters.response_amplitude = 2.0F;
    parameters.response_rate = 1.2F;
    parameters.response_shape = 1.4F;

    std::cout << "{\"schema_version\":1,\"operation\":\"gpu_transfer_bench\",\"adapter\":\""
              << device.capability().adapter.description.data() << "\",\"width\":" << width
              << ",\"height\":" << height << ",\"megabytes\":" << megabytes << ",\"runs\":[";

    for (int run = 0; run < repeats; ++run) {
        const auto upload_started = std::chrono::steady_clock::now();
        if (source.upload_into(device, host.data(), width) != GpuImageStatus::ok) {
            std::cerr << "upload failed\n";
            return 1;
        }
        // ☠️ `UpdateSubresource` 는 비동기입니다. 바로 뒤 시각을 재면 드라이버 큐에 넣는
        //    시간만 재게 됩니다. 그래서 커널과 회수까지 묶어서 재고, 그 합을 나눠 봅니다.
        const double upload_ms = milliseconds_since(upload_started);

        double kernel_ms = 0.0;
        if (has_kernel) {
            const auto kernel_started = std::chrono::steady_clock::now();
            if (invert.dispatch(device, source, destination, parameters) !=
                GpuKernelStatus::ok) {
                std::cerr << "dispatch failed\n";
                return 1;
            }
            kernel_ms = milliseconds_since(kernel_started);
        }

        // 다운로드는 스테이징 + `Map` 이라 **동기화합니다** — 밀린 작업이 여기서 드러납니다.
        const auto download_started = std::chrono::steady_clock::now();
        const GpuWorkingImage& readback_source = has_kernel ? destination : source;
        if (readback_source.download(device, readback.data(), width) != GpuImageStatus::ok) {
            std::cerr << "download failed\n";
            return 1;
        }
        const double download_ms = milliseconds_since(download_started);

        const double total = upload_ms + kernel_ms + download_ms;
        if (run != 0) {
            std::cout << ',';
        }
        std::cout << "{\"upload_ms\":" << upload_ms << ",\"dispatch_ms\":" << kernel_ms
                  << ",\"download_ms\":" << download_ms << ",\"total_ms\":" << total
                  << ",\"round_trip_gigabytes_per_second\":"
                  << (total > 0.0 ? (megabytes * 2.0) / (1024.0 * (total / 1000.0)) : 0.0)
                  << '}';
    }
    std::cout << "]}\n";
    return 0;
}

}  // namespace negaflow::cli
