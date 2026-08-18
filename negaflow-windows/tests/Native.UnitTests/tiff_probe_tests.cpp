#include "TiffProbe/tiff_probe_test_support.h"

#include <iostream>

using namespace tiff_probe_tests;

int main() {
    TempDirectory temporary{};
    test_random_access_reader_contract();
    test_valid_classic_and_original_unchanged(temporary.path());
    test_valid_big_endian_variants(temporary.path());
    test_valid_tiled(temporary.path());
    test_extra_samples(temporary.path());
    test_multi_directory_selection(temporary.path());
    test_malformed_and_limits(temporary.path());

    if (failures != 0) {
        std::cerr << failures << " TIFF probe test(s) failed\n";
        return 1;
    }
    std::cout << "TIFF probe tests passed\n";
    return 0;
}
