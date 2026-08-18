#include "ManualNegative/manual_negative_test_support.h"

#include <iostream>

using namespace manual_negative_tests;

int main() {
    test_muted_scene_vibrance();
    test_film_stock_presets();
    test_manual_negative_development();
    test_auto_negative_base_resolution();
    test_invalid_manual_inputs_fail_closed();

    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"manual_negative_developer\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
