#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "input_gamma_edge_sampler.h"
#include "negaflow/imageio/image_file_observation.h"

#include <algorithm>
#include <mutex>
#include <condition_variable>
#include <vector>

namespace negaflow::imaging {
bool supports_input_gamma_layout(const negaflow::core::TiffProbeInfo& info) noexcept {
    if (info.samples_per_pixel != 3U || info.photometric_interpretation != 2U || info.extra_samples_count != 0U ||
        (info.bits_per_sample_count != 1U && info.bits_per_sample_count != 3U) ||
        (info.sample_format_count != 1U && info.sample_format_count != 3U)) { return false; }
    const auto bits = info.bits_per_sample[0];
    return (bits == 8U || bits == 16U) &&
        std::all_of(info.bits_per_sample.begin(), info.bits_per_sample.begin() + info.bits_per_sample_count,
                    [bits](auto value) { return value == bits; }) &&
        std::all_of(info.sample_format.begin(), info.sample_format.begin() + info.sample_format_count,
                    [](auto value) { return value == 1U; });
}

namespace {
class InputProfileProbe final : public negaflow::imageio::WicTiffRowSink {
public:
    InputGammaSourceInfo info{};
    bool began{false};
    bool layout_supported{false};
    InputGammaEdgeSampler sampler{};
    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        began = true;
        info.supported = frame.layout == negaflow::imageio::DecodedPixelLayout::rgb16 &&
            (frame.icc_profile.empty() || negaflow::color::make_input_gamma_profile(frame.icc_profile, {1U, 1.0}).status
                == negaflow::color::InputGammaProfileStatus::ok);
        if (!frame.icc_profile.empty()) {
            const auto power = negaflow::color::recorded_input_gamma(frame.icc_profile);
            info.curve = power ? 1U : 2U;
            info.gamma = power.value_or(0.0);
        }
        return layout_supported && info.supported && frame.icc_profile.empty() && sampler.begin(frame);
    }
    bool write(const negaflow::imageio::WicTiffRowChunk& chunk) noexcept override { return sampler.write(chunk); }
    void complete(negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        if (status != negaflow::imageio::WicTiffDecodeStatus::ok) { return; }
        if (const auto estimate = sampler.estimate()) {
            info.curve = 5U; info.gamma = estimate->gamma;
            info.evidence = estimate->evidence; info.edge_count = estimate->edge_count;
        }
    }
};
struct SourceInfoEntry {
    std::filesystem::path path;
    negaflow::imageio::ImageFileObservation observation;
    InputGammaSourceInfo info;
};
std::mutex source_info_mutex;
std::condition_variable source_info_ready;
std::vector<SourceInfoEntry> source_infos;
std::vector<SourceInfoEntry> pending_source_infos;
bool same_source(const SourceInfoEntry& entry, const std::filesystem::path& path,
                 const negaflow::imageio::ImageFileObservation& observation) noexcept {
    return entry.path == path && negaflow::imageio::same_image_file_observation(entry.observation, observation);
}
struct CompleteSourceInfo {
    const std::filesystem::path& path;
    const negaflow::imageio::ImageFileObservation& observation;
    ~CompleteSourceInfo() {
        const std::lock_guard lock(source_info_mutex);
        std::erase_if(pending_source_infos, [&](const auto& entry) { return same_source(entry, path, observation); });
        source_info_ready.notify_all();
    }
};
}  // namespace
bool is_input_gamma_source_supported(const std::filesystem::path& path) noexcept {
    return inspect_input_gamma_source(path).supported;
}

negaflow::color::InputGammaInterpretation resolve_input_gamma_source(
    const std::filesystem::path& path, negaflow::color::InputGammaInterpretation requested) noexcept {
    if (!requested.valid() || requested.mode != 0U) { return requested; }
    const auto info = inspect_input_gamma_source(path);
    if (info.supported && info.curve == 5U) { return {1U, info.gamma}; }
    return requested;
}

InputGammaSourceInfo inspect_input_gamma_source(const std::filesystem::path& path) noexcept {
    try {
        const auto observed = negaflow::imageio::observe_image_file(path);
        if (observed.status != negaflow::imageio::ImageFileObservationStatus::ok) { return {}; }
        std::unique_lock lock(source_info_mutex);
        source_info_ready.wait(lock, [&] {
            return std::none_of(pending_source_infos.begin(), pending_source_infos.end(),
                [&](const auto& entry) { return same_source(entry, path, observed.observation); });
        });
        for (const auto& entry : source_infos) {
            if (entry.path == path && negaflow::imageio::same_image_file_observation(entry.observation, observed.observation)) { return entry.info; }
        }
        pending_source_infos.push_back({path, observed.observation, {}});
        lock.unlock();
        const CompleteSourceInfo completed{path, observed.observation};
        const auto probe = negaflow::core::probe_tiff_file(path);
        if (probe.status != negaflow::core::TiffProbeStatus::ok) { return {}; }
        negaflow::imaging::InputProfileProbe sink;
        sink.layout_supported = supports_input_gamma_layout(probe.info);
        sink.info.curve = probe.info.bits_per_sample[0] >= 16U ? 3U : 4U;
        negaflow::imageio::WicTiffDecodeControl control{};
        control.rows_per_copy = 32U;
        control.validate_compressed_streams = false;
        (void)negaflow::imageio::decode_tiff_rows_with_wic(path, sink, {}, control);
        if (!sink.began) { return {}; }
        sink.info.supported = sink.info.supported && supports_input_gamma_layout(probe.info);
        const auto after = negaflow::imageio::observe_image_file(path);
        if (after.status != negaflow::imageio::ImageFileObservationStatus::ok ||
            !negaflow::imageio::same_image_file_observation(observed.observation, after.observation)) { return {}; }
        {
            const std::lock_guard store_lock(source_info_mutex);
            if (source_infos.size() >= 64U) { source_infos.clear(); }
            source_infos.push_back({path, observed.observation, sink.info});
        }
        return sink.info;
    } catch (...) { return {}; }
}

}  // namespace negaflow::imaging
