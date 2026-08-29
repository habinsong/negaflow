#include "stage_trace.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>

#include <windows.h>
#include <shlobj.h>

#include "negaflow/pipeline/gpu_accelerator.h"

namespace negaflow::pipeline::develop_export_detail {
namespace {

std::mutex& trace_mutex() noexcept {
    static std::mutex mutex{};
    return mutex;
}

// 추적 파일은 `%LOCALAPPDATA%\Negaflow\Logs\stage-trace.txt` 입니다. 관리 쪽
// 추적기들과 같은 자리에 모읍니다.
const std::string& trace_path() noexcept {
    static const std::string path = [] {
        PWSTR folder = nullptr;
        std::string resolved{};
        if (SUCCEEDED(::SHGetKnownFolderPath(
                FOLDERID_LocalAppData, 0, nullptr, &folder)) &&
            folder != nullptr) {
            const int needed = ::WideCharToMultiByte(
                CP_UTF8, 0, folder, -1, nullptr, 0, nullptr, nullptr);
            if (needed > 0) {
                std::string narrow(static_cast<std::size_t>(needed), '\0');
                ::WideCharToMultiByte(
                    CP_UTF8, 0, folder, -1, narrow.data(), needed, nullptr, nullptr);
                narrow.resize(static_cast<std::size_t>(needed) - 1U);
                resolved = narrow + "\\Negaflow\\Logs";
            }
        }
        if (folder != nullptr) {
            ::CoTaskMemFree(folder);
        }
        if (resolved.empty()) {
            return std::string{};
        }
        ::CreateDirectoryA((resolved).c_str(), nullptr);
        return resolved + "\\stage-trace.txt";
    }();
    return path;
}

void write_line(const std::string& line) noexcept {
    const std::string& path = trace_path();
    if (path.empty()) {
        return;
    }
    const std::lock_guard<std::mutex> guard{trace_mutex()};
    std::FILE* file = nullptr;
    if (::fopen_s(&file, path.c_str(), "ab") != 0 || file == nullptr) {
        return;
    }
    std::fwrite(line.data(), 1U, line.size(), file);
    std::fputc('\n', file);
    std::fclose(file);
}

} // namespace

bool stage_trace_enabled() noexcept {
    static const bool enabled = [] {
        char buffer[8]{};
        std::size_t length = 0U;
        if (::getenv_s(&length, buffer, sizeof(buffer), "NEGAFLOW_STAGE_TRACE") != 0) {
            return false;
        }
        return length > 1U && buffer[0] == '1';
    }();
    return enabled;
}

void stage_trace_begin(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    const DetectTarget* const detect) noexcept {
    if (!stage_trace_enabled()) {
        return;
    }
    const std::string_view route =
        preview != nullptr ? "preview" : (detect != nullptr ? "detect" : "export");
    const std::uint32_t develop_target =
        static_cast<std::uint32_t>(request.develop_target);
    const bool negative_source = request.film_polarity != FilmPolarity::positive;
    const std::wstring_view scanner_profile_id = request.scanner_profile_id;
    std::string profile{};
    if (!scanner_profile_id.empty()) {
        const int needed = ::WideCharToMultiByte(
            CP_UTF8,
            0,
            scanner_profile_id.data(),
            static_cast<int>(scanner_profile_id.size()),
            nullptr,
            0,
            nullptr,
            nullptr);
        if (needed > 0) {
            profile.resize(static_cast<std::size_t>(needed));
            ::WideCharToMultiByte(
                CP_UTF8,
                0,
                scanner_profile_id.data(),
                static_cast<int>(scanner_profile_id.size()),
                profile.data(),
                needed,
                nullptr,
                nullptr);
        }
    }
    char line[512]{};
    const int written = std::snprintf(
        line,
        sizeof(line),
        "--- route=%.*s target=%u negative_source=%d profile=%.*s",
        static_cast<int>(route.size()),
        route.data(),
        develop_target,
        negative_source ? 1 : 0,
        static_cast<int>(profile.size()),
        profile.empty() ? "" : profile.data());
    if (written > 0) {
        write_line(std::string{line});
    }
}

void stage_trace_image(
    const std::string_view stage,
    const negaflow::imaging::WorkingImage& image) noexcept {
    if (!stage_trace_enabled()) {
        return;
    }
    // GPU 에 머문 화소는 호스트 버퍼가 옛것입니다. 진단이 거짓말을 하지 않도록
    // 먼저 내립니다.
    GpuAccelerator::shared().flush_resident();
    if (image.width == 0U || image.height == 0U || image.pixels.empty()) {
        char empty[256]{};
        const int written = std::snprintf(
            empty,
            sizeof(empty),
            "    %-22.*s (empty %ux%u)",
            static_cast<int>(stage.size()),
            stage.data(),
            image.width,
            image.height);
        if (written > 0) {
            write_line(std::string{empty});
        }
        return;
    }

    // 64×64 격자로 성깁니다. 전체를 읽으면 진단이 실행 시간을 바꿉니다.
    constexpr std::uint32_t samples = 64U;
    const std::uint32_t step_x = image.width > samples ? image.width / samples : 1U;
    const std::uint32_t step_y = image.height > samples ? image.height / samples : 1U;
    double sum_r = 0.0;
    double sum_g = 0.0;
    double sum_b = 0.0;
    float min_v = 1e30F;
    float max_v = -1e30F;
    std::uint64_t count = 0U;
    for (std::uint32_t y = 0U; y < image.height; y += step_y) {
        const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; x += step_x) {
            const std::size_t index = row + x;
            if (index >= image.pixels.size()) {
                break;
            }
            const negaflow::core::Rgba32F pixel = image.pixels[index];
            sum_r += static_cast<double>(pixel.red);
            sum_g += static_cast<double>(pixel.green);
            sum_b += static_cast<double>(pixel.blue);
            min_v = pixel.red < min_v ? pixel.red : min_v;
            max_v = pixel.red > max_v ? pixel.red : max_v;
            ++count;
        }
    }
    if (count == 0U) {
        return;
    }
    char line[512]{};
    const int written = std::snprintf(
        line,
        sizeof(line),
        "    %-22.*s %ux%u mean=(%.4f, %.4f, %.4f) r[min=%.4f max=%.4f] n=%llu",
        static_cast<int>(stage.size()),
        stage.data(),
        image.width,
        image.height,
        sum_r / static_cast<double>(count),
        sum_g / static_cast<double>(count),
        sum_b / static_cast<double>(count),
        static_cast<double>(min_v),
        static_cast<double>(max_v),
        static_cast<unsigned long long>(count));
    if (written > 0) {
        write_line(std::string{line});
    }
}

void stage_trace_note(
    const std::string_view stage,
    const std::string_view note) noexcept {
    if (!stage_trace_enabled()) {
        return;
    }
    char line[512]{};
    const int written = std::snprintf(
        line,
        sizeof(line),
        "    %-22.*s %.*s",
        static_cast<int>(stage.size()),
        stage.data(),
        static_cast<int>(note.size()),
        note.data());
    if (written > 0) {
        write_line(std::string{line});
    }
}

void stage_trace_invert(const InvertStageOutput& invert) noexcept {
    if (!stage_trace_enabled()) {
        return;
    }
    const std::uint32_t base_source = static_cast<std::uint32_t>(invert.base_source);
    const auto& applied_dmin = invert.developed_info.applied_dmin;
    const auto& dmax_normalized = invert.developed_info.dmax_normalized;
    const bool use_preset_response = invert.negative.use_preset_response;
    const std::uint32_t kernel_status =
        static_cast<std::uint32_t>(invert.developed_info.kernel_status);
    char note[384]{};
    const int written = std::snprintf(
        note,
        sizeof(note),
        "base_source=%u applied_dmin=(%.5f, %.5f, %.5f) "
        "dmax_norm=(%.5f, %.5f, %.5f) preset=%d kernel=%u",
        base_source,
        static_cast<double>(applied_dmin[0]),
        static_cast<double>(applied_dmin[1]),
        static_cast<double>(applied_dmin[2]),
        static_cast<double>(dmax_normalized[0]),
        static_cast<double>(dmax_normalized[1]),
        static_cast<double>(dmax_normalized[2]),
        use_preset_response ? 1 : 0,
        kernel_status);
    if (written > 0) {
        stage_trace_note("invert.params", note);
    }
}

void stage_trace_defect(
    const DevelopExportRequest& request,
    const DefectRecipeStageResult& defect_recipe) noexcept {
    if (!stage_trace_enabled()) {
        return;
    }
    const auto& info = defect_recipe.info;
    const std::size_t order_count = request.defect_recipe.order.size();
    const bool region_applied = info.region_applied;
    const std::size_t region_edits = info.region_applied_edit_count;
    const std::size_t region_pixels = info.region_repaired_pixels;
    const bool clone_applied = info.clone_applied;
    const std::size_t clone_edits = info.clone_applied_edit_count;
    const std::size_t clone_pixels = info.clone_patched_pixels;
    const bool brush_applied = info.brush_applied;
    const std::size_t brush_edits = info.brush_applied_edit_count;
    const std::size_t brush_pixels = info.brush_healed_pixels;
    const std::size_t infrared_count = request.defect_recipe.infrared.size();
    const std::uint32_t status = static_cast<std::uint32_t>(defect_recipe.status);
    char note[384]{};
    const int written = std::snprintf(
        note,
        sizeof(note),
        "order=%zu region=%d/%zu(px %zu) clone=%d/%zu(px %zu) "
        "brush=%d/%zu(px %zu) infrared=%zu status=%u",
        order_count,
        region_applied ? 1 : 0,
        region_edits,
        region_pixels,
        clone_applied ? 1 : 0,
        clone_edits,
        clone_pixels,
        brush_applied ? 1 : 0,
        brush_edits,
        brush_pixels,
        infrared_count,
        status);
    if (written > 0) {
        stage_trace_note("defect.recipe", note);
    }
}

void stage_trace_grain_mend(const GrainStageOutput& grain) noexcept {
    if (!stage_trace_enabled()) {
        return;
    }
    const bool applied = grain.applied.info.applied;
    const std::size_t candidate_pixels = grain.applied.info.candidate_pixels;
    const std::size_t repaired_pixels = grain.applied.info.repaired_pixels;
    char note[256]{};
    const int written = std::snprintf(
        note,
        sizeof(note),
        "applied=%d candidate_px=%zu repaired_px=%zu",
        applied ? 1 : 0,
        candidate_pixels,
        repaired_pixels);
    if (written > 0) {
        stage_trace_note("grain.mend", note);
    }
}

} // namespace negaflow::pipeline::develop_export_detail
