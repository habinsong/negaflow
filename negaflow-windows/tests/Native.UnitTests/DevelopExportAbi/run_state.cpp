#include "synthetic_wic_tiff.h"
#include <atomic>
#include <cstring>
#include <iostream>
#include <thread>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

void test_v22_run_state() {
    constexpr std::uint32_t width = 64U;
    constexpr std::uint32_t height = 64U;
    const std::filesystem::path temporary = std::filesystem::temp_directory_path();
    const std::filesystem::path source =
        temporary / L"negaflow-abi-v22-run-state-source.tif";
    const std::filesystem::path cancelled_output =
        temporary / L"negaflow-abi-v22-cancelled.png";
    const std::filesystem::path completed_output =
        temporary / L"negaflow-abi-v22-completed.png";
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    std::filesystem::remove(cancelled_output, ignored);
    std::filesystem::remove(completed_output, ignored);

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "v22 synthetic TIFF is written");
    if (!std::filesystem::exists(source)) {
        return;
    }

    const std::wstring source_text = source.wstring();
    const std::wstring cancelled_text = cancelled_output.wstring();
    const std::wstring completed_text = completed_output.wstring();

    // A run state already latched before the call must stop at the first poll and leave
    // no artifact. This is the shape a superseded preview request takes.
    nf_develop_export_request_v21 cancelled_request = make_request_v21(
        source_text.c_str(),
        cancelled_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    cancelled_request.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_run_state_v1 cancelled_state = make_run_state();
    cancelled_state.cancel_requested = 1U;
    nf_develop_export_result_v3 cancelled_result = make_result_v3();
    expect(
        nf_develop_export_v22(
            &cancelled_request,
            &cancelled_state,
            &cancelled_result) == NF_STATUS_OK &&
            cancelled_result.succeeded == 0U &&
            cancelled_result.cancelled == 1U &&
            std::strcmp(cancelled_result.failure_name, "cancelled") == 0,
        "v22 reports a cancelled run rather than a failure");
    expect(
        !std::filesystem::exists(cancelled_output),
        "a cancelled export publishes no destination file");

    // The same latch must stop a preview without writing display pixels.
    std::vector<std::uint8_t> cancelled_pixels(
        static_cast<std::size_t>(width) * height * 4U,
        0xABU);
    nf_develop_run_state_v1 cancelled_preview_state = make_run_state();
    cancelled_preview_state.cancel_requested = 1U;
    nf_develop_export_result_v3 cancelled_preview_result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &cancelled_request,
            width,
            height,
            cancelled_pixels.data(),
            static_cast<std::uint32_t>(cancelled_pixels.size()),
            &cancelled_preview_state,
            &cancelled_preview_result) == NF_STATUS_OK &&
            cancelled_preview_result.succeeded == 0U &&
            cancelled_preview_result.cancelled == 1U,
        "v22 preview honours the cancel latch");
    bool preview_untouched = true;
    for (const std::uint8_t value : cancelled_pixels) {
        preview_untouched = preview_untouched && value == 0xABU;
    }
    expect(preview_untouched, "a cancelled preview leaves the caller buffer alone");

    // An untouched run state reaches completion and reports it, and the progress figure
    // is only allowed to say "complete" when the run actually succeeded.
    nf_develop_export_request_v21 completed_request = make_request_v21(
        source_text.c_str(),
        completed_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    completed_request.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;
    nf_develop_run_state_v1 completed_state = make_run_state();
    nf_develop_export_result_v3 completed_result = make_result_v3();
    expect(
        nf_develop_export_v22(
            &completed_request,
            &completed_state,
            &completed_result) == NF_STATUS_OK &&
            completed_result.succeeded == 1U &&
            completed_result.cancelled == 0U,
        "v22 completes a run whose state was never latched");
    expect(
        completed_state.progress_permille == NF_DEVELOP_PROGRESS_COMPLETE,
        "a successful run leaves progress at complete");
    expect(
        completed_state.stage == NF_DEVELOP_STAGE_OUTPUT,
        "the last stage a successful run reports is the publish");
    expect(
        std::filesystem::exists(completed_output),
        "an uncancelled export publishes its destination file");

    // A null run state keeps the pre-v22 behaviour: the call simply runs to the end.
    std::filesystem::remove(completed_output, ignored);
    nf_develop_export_result_v3 stateless_result = make_result_v3();
    expect(
        nf_develop_export_v22(
            &completed_request,
            nullptr,
            &stateless_result) == NF_STATUS_OK &&
            stateless_result.succeeded == 1U &&
            stateless_result.cancelled == 0U,
        "v22 accepts a null run state and behaves as before");

    // A run state the caller under-declared is refused outright: writing four words into
    // three would corrupt whatever follows it.
    nf_develop_run_state_v1 short_state = make_run_state();
    short_state.struct_size = 4U;
    nf_develop_export_result_v3 short_result = make_result_v3();
    expect(
        nf_develop_export_v22(&completed_request, &short_state, &short_result) ==
            NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized run state is refused");

    std::filesystem::remove(source, ignored);
    std::filesystem::remove(cancelled_output, ignored);
    std::filesystem::remove(completed_output, ignored);
}

// The synthetic checks prove the latch is honoured before the first stage. This one runs
// against a real scan and latches from another thread once the engine reports it has
// started, which is the only way to show the mid-run poll points actually fire.
void test_v22_cancel_during_run(const std::filesystem::path& source) {
    const std::filesystem::path destination =
        std::filesystem::temp_directory_path() / L"negaflow-abi-v22-mid-run.png";
    std::error_code ignored{};
    std::filesystem::remove(destination, ignored);

    const std::wstring source_text = source.wstring();
    const std::wstring destination_text = destination.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(),
        destination_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    nf_develop_run_state_v1 state = make_run_state();
    nf_develop_export_result_v3 result = make_result_v3();

    std::atomic<bool> finished{false};
    std::atomic<bool> observed_start{false};
    std::thread watcher{[&state, &finished, &observed_start]() noexcept {
        while (!finished.load(std::memory_order_relaxed)) {
            const std::uint32_t stage =
                std::atomic_ref<std::uint32_t>(state.stage).load(std::memory_order_relaxed);
            if (stage != NF_DEVELOP_STAGE_NONE) {
                observed_start.store(true, std::memory_order_relaxed);
                std::atomic_ref<std::uint32_t>(state.cancel_requested)
                    .store(1U, std::memory_order_relaxed);
                return;
            }
            std::this_thread::yield();
        }
    }};

    const nf_status_t status = nf_develop_export_v22(&request, &state, &result);
    finished.store(true, std::memory_order_relaxed);
    watcher.join();

    expect(status == NF_STATUS_OK, "v22 mid-run export returns a well formed call");
    if (!observed_start.load(std::memory_order_relaxed)) {
        // The run beat the watcher to the finish. Nothing was cancelled, so the only
        // thing to check is that it behaved like an ordinary successful export.
        expect(
            result.succeeded == 1U && result.cancelled == 0U,
            "an uncancelled real export succeeds");
        std::filesystem::remove(destination, ignored);
        return;
    }

    // Reported so the run log shows which branch was taken rather than leaving the
    // reader to guess whether the interesting one ever executed.
    std::cout << "{\"note\":\"v22_cancelled_mid_run\",\"stage\":"
              << result.failed_stage << ",\"wall_microseconds\":"
              << result.wall_microseconds << "}\n";
    expect(
        result.cancelled == 1U && result.succeeded == 0U,
        "a latch set while the run is in flight stops it");
    expect(
        result.failed_stage != NF_DEVELOP_STAGE_NONE,
        "a cancelled run names the stage it was interrupted in");
    expect(
        !std::filesystem::exists(destination),
        "a run cancelled mid-flight publishes no file");
    std::filesystem::remove(destination, ignored);

    // GrainMend is the one stage long enough that stopping only at its boundary would
    // still leave the user waiting seconds. This latches once the run reports it has
    // reached that stage, which exercises the checks inside detection rather than the
    // boundary check in front of it.
    nf_develop_export_request_v21 defect_request = make_request_v21(
        source_text.c_str(),
        destination_text.c_str(),
        NF_BASE_ESTIMATION_MANUAL);
    defect_request.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
        .defect_removal_strength = 1.0;
    // The interactive case is a preview, not a publish, so the comparison is measured on
    // previews: the same GrainMend-enabled render, once left alone and once cancelled.
    std::vector<std::uint8_t> defect_pixels(
        static_cast<std::size_t>(512U) * 512U * 4U,
        0U);
    nf_develop_run_state_v1 baseline_state = make_run_state();
    nf_develop_export_result_v3 baseline_result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &defect_request,
            512U,
            512U,
            defect_pixels.data(),
            static_cast<std::uint32_t>(defect_pixels.size()),
            &baseline_state,
            &baseline_result) == NF_STATUS_OK &&
            baseline_result.succeeded == 1U,
        "a GrainMend preview completes when nothing cancels it");
    std::cout << "{\"note\":\"v22_grain_mend_preview_baseline\",\"wall_microseconds\":"
              << baseline_result.wall_microseconds << "}\n";

    nf_develop_run_state_v1 defect_state = make_run_state();
    nf_develop_export_result_v3 defect_result = make_result_v3();

    std::atomic<bool> defect_finished{false};
    std::atomic<bool> reached_grain_mend{false};
    std::thread defect_watcher{[&defect_state, &defect_finished, &reached_grain_mend]() noexcept {
        while (!defect_finished.load(std::memory_order_relaxed)) {
            const std::uint32_t stage =
                std::atomic_ref<std::uint32_t>(defect_state.stage)
                    .load(std::memory_order_relaxed);
            if (stage == NF_DEVELOP_STAGE_GRAIN_MEND) {
                reached_grain_mend.store(true, std::memory_order_relaxed);
                std::atomic_ref<std::uint32_t>(defect_state.cancel_requested)
                    .store(1U, std::memory_order_relaxed);
                return;
            }
            std::this_thread::yield();
        }
    }};

    const nf_status_t defect_status =
        nf_develop_export_v22(&defect_request, &defect_state, &defect_result);
    defect_finished.store(true, std::memory_order_relaxed);
    defect_watcher.join();
    expect(defect_status == NF_STATUS_OK, "the GrainMend run is a well formed call");

    if (reached_grain_mend.load(std::memory_order_relaxed)) {
        std::cout << "{\"note\":\"v22_cancelled_inside_grain_mend\",\"stage\":"
                  << defect_result.failed_stage << ",\"wall_microseconds\":"
                  << defect_result.wall_microseconds << "}\n";
        expect(
            defect_result.cancelled == 1U &&
                defect_result.failed_stage == NF_DEVELOP_STAGE_GRAIN_MEND,
            "a cancel arriving during GrainMend stops inside that stage");
        expect(
            !std::filesystem::exists(destination),
            "a GrainMend cancellation publishes no file");
    }
    std::filesystem::remove(destination, ignored);
}

}  // namespace negaflow::develop_export_abi_tests
