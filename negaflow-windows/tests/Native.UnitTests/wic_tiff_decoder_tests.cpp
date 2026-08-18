#include "WicTiffDecoder/wic_tiff_decoder_test_support.h"

#include <filesystem>
#include <iostream>
#include <string>

using namespace wic_tiff_decoder_tests;

int main(const int argument_count, const char* const arguments[]) {
    if (argument_count > 2) {
        std::cerr << "expected zero or one TIFF fixture path\n";
        return 2;
    }

    TempDirectory temporary{};
    test_valid_lzw(temporary.path());
    test_gray16_companion(temporary.path());
    test_eight_bit_widens_by_bit_replication(temporary.path());
    test_lzw_code_width_transition(temporary.path());
    test_lzw_dictionary_limit_and_forward_reference(temporary.path());
    test_row_copy_progress_and_cancellation(temporary.path());
    test_malformed_lzw(temporary.path());
    test_semantically_invalid_lzw(temporary.path());
    test_deflate_preflight(temporary.path());
    test_decoded_byte_limit(temporary.path());
    if (argument_count == 2) {
        test_repository_fixture(std::filesystem::path{arguments[1]});
    }

    if (failures != 0) {
        std::cerr << failures << " WIC TIFF decoder test(s) failed\n";
        return 1;
    }
    std::cout << "WIC TIFF decoder tests passed\n";
    return 0;
}
