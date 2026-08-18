#include "TextureStage/texture_stage_test_support.h"

#include <filesystem>
#include <iostream>

using namespace texture_stage_tests;

int main(const int argc, char** argv) {
    test_identity_and_invalid_controls();
    test_grain_and_detail_controls();
    test_halation_and_vignette();
    test_output_sharpening();
    expect(argc == 2, "texture-stage CTest receives the Core Image golden directory");
    if (argc == 2) {
        test_coreimage_filter_goldens(argv[1]);
    }

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"texture_stage\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
