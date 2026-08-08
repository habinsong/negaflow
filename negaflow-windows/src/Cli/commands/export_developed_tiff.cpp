#include "export_developed_tiff.h"

#include "export_developed_image.h"

namespace negaflow::cli {

int run_export_developed_tiff(
    const int argument_count,
    const wchar_t* const arguments[]) {
    return run_export_developed_image(
        argument_count,
        arguments,
        DevelopedExportFormat::tiff16);
}

}  // namespace negaflow::cli
