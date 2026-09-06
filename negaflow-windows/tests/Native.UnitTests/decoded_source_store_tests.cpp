#include "export/support/decoded_source_store.h"
#include <iostream>
#include <thread>
#include <vector>

namespace {
int failures = 0;
void expect(bool value, const char* label) {
    if (!value) { std::cerr << "FAIL: " << label << '\n'; ++failures; }
}
}

int main() {
    using namespace negaflow::pipeline::develop_export_detail;
    using negaflow::imageio::DecodedImage;
    using negaflow::imaging::WorkingImage;
    decoded_source_store_reset();
    auto codes = std::make_shared<DecodedImage>();
    codes->width = 8U; codes->height = 8U; codes->stride_bytes = 48U;
    codes->samples.assign(8U * 8U * 3U, std::uint16_t{12345});
    const std::filesystem::path path{"input.tiff"};
    negaflow::imageio::ImageFileObservation observed{1U, 2U, 384U, 4U};
    encoded_source_put(path, observed, 0U, 0U, codes);
    auto lease = encoded_source_try_take(path, observed, 0U, 0U);
    expect(lease == codes, "source code cache returns immutable shared storage");
    for (int step = 1; step <= 40; ++step) {
        auto working = std::make_shared<WorkingImage>();
        working->width = 8U; working->height = 8U; working->stride_pixels = 8U;
        working->pixels.resize(64U);
        const negaflow::color::InputGammaInterpretation gamma{1U, static_cast<double>(step) / 10.0};
        decoded_source_put(path, observed, 0U, 0U, working, gamma);
        expect(decoded_source_try_take(path, observed, 0U, 0U, gamma) == working, "latest interpreted pixels are retained");
        expect(encoded_source_try_take(path, observed, 0U, 0U) == lease, "gamma edits reuse original RGB codes");
        expect(decoded_source_store_resident_bytes() == 384U + 64U * sizeof(negaflow::core::Rgba32F),
            "forty gamma values do not retain forty decoded buffers");
    }
    expect(!encoded_source_try_take(path, observed, 3600U, 3600U), "proxy cache cannot stand in for full resolution");
    auto changed = observed; ++changed.file_index;
    expect(!encoded_source_try_take(path, changed, 0U, 0U), "replaced source cannot reuse old code values");
    auto replacement = std::make_shared<DecodedImage>(*codes);
    replacement->samples[0] = 4321U;
    encoded_source_put(path, changed, 0U, 0U, replacement);
    expect(!decoded_source_try_take(path, changed, 0U, 0U, {1U, 4.0}), "replacement invalidates interpreted pixels");
    expect(lease->samples[0] == 12345U, "in-flight old source stays alive after replacement");
    std::vector<std::thread> workers;
    for (unsigned i = 0; i < 8U; ++i) {
        workers.emplace_back([&, i] {
            for (unsigned iteration = 0; iteration < 64U; ++iteration) {
                const std::filesystem::path key{std::to_string(i) + ".tiff"};
                encoded_source_put(key, changed, 0U, 0U, replacement);
                const auto held = encoded_source_try_take(key, changed, 0U, 0U);
                if (held && held->samples[0] != 4321U) { std::terminate(); }
            }
        });
    }
    for (auto& worker : workers) { worker.join(); }
    decoded_source_store_reset();
    expect(decoded_source_store_resident_bytes() == 0U, "reset releases all resident slots");
    expect(lease->samples[0] == 12345U, "reset cannot invalidate a reader lease");
    std::cout << "decoded source store failures=" << failures << '\n';
    return failures == 0 ? 0 : 1;
}
