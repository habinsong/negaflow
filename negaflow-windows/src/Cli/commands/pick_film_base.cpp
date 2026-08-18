#include "pick_film_base.h"

#include "negaflow/imaging/film_base_picker.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

#include <array>
#include <charconv>
#include <cmath>
#include <cstddef>
#include <filesystem>
#include <iostream>
#include <string_view>

namespace negaflow::cli {
namespace {

[[nodiscard]] int print_error(const std::string_view code) {
    std::cout << "{\"status\":\"error\",\"code\":\"" << code << "\"}\n";
    return 2;
}

[[nodiscard]] bool parse_unit(const std::wstring_view text, double& value) noexcept {
    if (text.empty() || text.size() > 127U) {
        return false;
    }
    std::array<char, 128> ascii{};
    for (std::size_t index = 0; index < text.size(); ++index) {
        if (text[index] < 0 || text[index] > 127) {
            return false;
        }
        ascii[index] = static_cast<char>(text[index]);
    }
    const auto [end, error] =
        std::from_chars(ascii.data(), ascii.data() + text.size(), value);
    return error == std::errc{} && end == ascii.data() + text.size() &&
        std::isfinite(value);
}

}  // namespace

int run_pick_film_base(const int argument_count, const wchar_t* const arguments[]) {
    if (argument_count < 5 || argument_count > 6) {
        return print_error("invalid_argument_count");
    }
    double unit_x = 0.0;
    double unit_y = 0.0;
    if (!parse_unit(arguments[3], unit_x) || !parse_unit(arguments[4], unit_y)) {
        return print_error("invalid_unit");
    }
    const bool monochrome =
        argument_count == 6 && std::wstring_view{arguments[5]} == L"bw";

    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = 64U;
    auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
        std::filesystem::path{arguments[2]}, {}, {}, decode_control);
    if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        return print_error("decode_failed");
    }

    const negaflow::imaging::FilmBasePickResult picked =
        negaflow::imaging::sample_film_base(
            prepared.working.image,
            unit_x,
            unit_y,
            monochrome ? negaflow::imaging::NegativeFilmType::black_and_white
                       : negaflow::imaging::NegativeFilmType::color);

    std::cout << "{\"status\":\"ok\",\"operation\":\"pick_film_base\""
              << ",\"width\":" << prepared.working.image.width
              << ",\"height\":" << prepared.working.image.height
              << ",\"unit\":[" << unit_x << ',' << unit_y << ']'
              << ",\"pick\":\""
              << negaflow::imaging::film_base_pick_status_name(picked.status) << '"'
              << ",\"rgb\":[" << picked.rgb[0] << ',' << picked.rgb[1] << ','
              << picked.rgb[2] << "]}\n";
    return picked.status == negaflow::imaging::FilmBasePickStatus::ok ? 0 : 3;
}

}  // namespace negaflow::cli
