#include "TextureStage/texture_stage_test_support.h"

#include <filesystem>
#include <iostream>

using namespace texture_stage_tests;

int main(const int argc, char** argv) {
    test_identity_and_invalid_controls();
    test_grain_and_detail_controls();
    test_halation_and_vignette();
    test_output_sharpening();
    test_detail_enhancement();
    expect(argc == 1 || argc == 2, "an optional external golden directory is accepted");
    if (argc == 2) {
        test_coreimage_filter_goldens(argv[1]);
    }

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"texture_stage\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
