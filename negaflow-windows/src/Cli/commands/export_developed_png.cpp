#include "export_developed_png.h"

#include "export_developed_image.h"

namespace negaflow::cli {

int run_export_developed_png(
    const int argument_count,
    const wchar_t* const arguments[]) {
    return run_export_developed_image(
        argument_count,
        arguments,
        DevelopedExportFormat::png16);
}

}  // namespace negaflow::cli
