#include "probe_image.h"

#include "negaflow/imageio/libraw_image_decoder.h"
#include "negaflow/imageio/wic_standard_image_decoder.h"

#include <filesystem>
#include <iostream>
#include <string_view>

namespace negaflow::cli {
namespace {

int print_error(const std::string_view code) {
    std::cerr << "{\"schema_version\":1,\"status\":\"error\",\"error\":{\"code\":\""
              << code << "\"}}\n";
    return 2;
}

}  // namespace

int run_probe_image(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count != 3) {
        return print_error("invalid_argument_count");
    }

    const std::filesystem::path path{arguments[2]};
    const auto wic_only = negaflow::imageio::decode_standard_image_with_wic_only(path);
    const auto decoded = negaflow::imageio::decode_standard_image_with_wic(path);

    if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
        std::cerr << "{\"schema_version\":1,\"status\":\"error\",\"error\":{\"code\":\""
                  << negaflow::imageio::wic_standard_image_decode_status_name(decoded.status)
                  << "\"},\"wic_only_status\":\""
                  << negaflow::imageio::wic_standard_image_decode_status_name(wic_only.status)
                  << "\",\"libraw_available\":"
                  << (negaflow::imageio::libraw_decoder_available() ? "true" : "false")
                  << "}\n";
        return 2;
    }

    // 크기만 보고 "열렸다" 라고 적으면 안 됩니다. 전부 0인 검은 판도 크기는 나옵니다.
    // 채널별 최소·최대와 fnv1a 지문을 함께 내서 실제 화소가 들어왔음을 증거로 남깁니다.
    std::uint16_t minimum[4] = {65'535U, 65'535U, 65'535U, 65'535U};
    std::uint16_t maximum[4] = {0U, 0U, 0U, 0U};
    std::uint64_t fingerprint = 1'469'598'103'934'665'603ULL;
    const std::size_t channels = negaflow::imageio::channel_count(decoded.image.layout);
    for (std::size_t index = 0U; index < decoded.image.samples.size(); ++index) {
        const std::uint16_t sample = decoded.image.samples[index];
        const std::size_t channel = channels == 0U ? 0U : index % channels;
        minimum[channel] = sample < minimum[channel] ? sample : minimum[channel];
        maximum[channel] = sample > maximum[channel] ? sample : maximum[channel];
        fingerprint = (fingerprint ^ sample) * 1'099'511'628'211ULL;
    }

    std::cout << "{\"schema_version\":1,\"status\":\"ok\",\"operation\":\"probe_image\""
              << ",\"width\":" << decoded.image.width
              << ",\"height\":" << decoded.image.height
              << ",\"layout\":\""
              << negaflow::imageio::decoded_pixel_layout_name(decoded.image.layout) << '"'
              << ",\"alpha_mode\":\""
              << negaflow::imageio::alpha_mode_name(decoded.image.alpha_mode) << '"'
              << ",\"decoded_pixel_bytes\":" << decoded.info.decoded_pixel_bytes
              << ",\"raw_development_used\":"
              << (decoded.info.raw_development_used ? "true" : "false")
              // 이 줄이 이 명령의 요점입니다. 같은 파일이 기계마다 다른 디코더로 열립니다.
              << ",\"libraw_fallback_used\":"
              << (decoded.info.libraw_fallback_used ? "true" : "false")
              << ",\"libraw_available\":"
              << (negaflow::imageio::libraw_decoder_available() ? "true" : "false")
              << ",\"libraw_version\":\"" << negaflow::imageio::libraw_decoder_version() << '"'
              << ",\"wic_only_status\":\""
              << negaflow::imageio::wic_standard_image_decode_status_name(wic_only.status) << '"'
              << ",\"exif_orientation\":" << decoded.info.exif_orientation
              << ",\"icc_profile_bytes\":" << decoded.image.icc_profile.size()
              << ",\"channel_min\":[" << minimum[0] << ',' << minimum[1] << ','
              << minimum[2] << ',' << minimum[3] << ']'
              << ",\"channel_max\":[" << maximum[0] << ',' << maximum[1] << ','
              << maximum[2] << ',' << maximum[3] << ']'
              << ",\"fingerprint_fnv1a64\":\"" << std::hex << fingerprint << std::dec << '"'
              << "}\n";
    return 0;
}

}  // namespace negaflow::cli
