#include "hash_image.h"

#include "negaflow/imageio/image_content_hash.h"

#include <chrono>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <string_view>

namespace negaflow::cli {
namespace {

int print_error(const negaflow::imageio::ImageContentHashResult& result) {
    std::cerr << "{\"schema_version\":1,\"status\":\"error\","
                 "\"error\":{\"code\":\""
              << negaflow::imageio::image_content_hash_status_name(result.status) << '"';
    if (result.native_error_code != 0U) {
        std::cerr << ",\"native_error_code\":\"0x" << std::hex << std::setw(8)
                  << std::setfill('0') << result.native_error_code << std::dec << '"';
    }
    std::cerr << "}}\n";
    return 2;
}

}  // namespace

int run_hash_image(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count != 3) {
        std::cerr << "{\"schema_version\":1,\"status\":\"error\","
                     "\"error\":{\"code\":\"invalid_argument_count\"}}\n";
        return 2;
    }

    negaflow::imageio::ImageContentHashControl control{};
    control.mode = negaflow::imageio::ImageContentHashMode::sha256;
    const auto started = std::chrono::steady_clock::now();
    const auto result = negaflow::imageio::hash_image_content(
        std::filesystem::path{arguments[2]},
        control);
    const auto finished = std::chrono::steady_clock::now();
    if (result.status != negaflow::imageio::ImageContentHashStatus::ok) {
        return print_error(result);
    }

    const double seconds = std::chrono::duration<double>(finished - started).count();
    const double throughput_mib_per_second = seconds > 0.0
        ? static_cast<double>(result.bytes_hashed) / (1024.0 * 1024.0) / seconds
        : 0.0;
    std::cout << "{\"schema_version\":1,\"status\":\"ok\","
                 "\"operation\":\"sha256_image\",\"algorithm\":\"sha-256\","
                 "\"file_bytes\":"
              << result.file_bytes << ",\"bytes_hashed\":" << result.bytes_hashed
              << ",\"read_buffer_bytes\":" << control.read_buffer_bytes
              << ",\"throughput_mib_per_second\":" << std::setprecision(6)
              << throughput_mib_per_second << ",\"sha256\":\""
              << negaflow::imageio::image_sha256_hex(result.sha256) << "\"}\n";
    return 0;
}

}  // namespace negaflow::cli
