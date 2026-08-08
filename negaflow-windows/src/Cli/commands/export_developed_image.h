#pragma once

#include <cstdint>

namespace negaflow::cli {

enum class DevelopedExportFormat : std::uint8_t {
    png16 = 0,
    tiff16,
};

int run_export_developed_image(
    int argument_count,
    const wchar_t* const arguments[],
    DevelopedExportFormat format);

}  // namespace negaflow::cli
