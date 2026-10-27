#include "negaflow/output/dng_linear_export.h"

#include "atomic_output_file.h"
#include "dng_tiff_block.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace negaflow::output {
namespace {

using namespace negaflow::output::detail;

// DNG·TIFF 태그 번호(규격 표기).
constexpr std::uint16_t tag_new_subfile_type = 254U;
constexpr std::uint16_t tag_image_width = 256U;
constexpr std::uint16_t tag_image_length = 257U;
constexpr std::uint16_t tag_bits_per_sample = 258U;
constexpr std::uint16_t tag_compression = 259U;
constexpr std::uint16_t tag_photometric = 262U;
constexpr std::uint16_t tag_make = 271U;
constexpr std::uint16_t tag_model = 272U;
constexpr std::uint16_t tag_strip_offsets = 273U;
constexpr std::uint16_t tag_orientation = 274U;
constexpr std::uint16_t tag_samples_per_pixel = 277U;
constexpr std::uint16_t tag_rows_per_strip = 278U;
constexpr std::uint16_t tag_strip_byte_counts = 279U;
constexpr std::uint16_t tag_x_resolution = 282U;
constexpr std::uint16_t tag_y_resolution = 283U;
constexpr std::uint16_t tag_planar_configuration = 284U;
constexpr std::uint16_t tag_resolution_unit = 296U;
constexpr std::uint16_t tag_software = 305U;
constexpr std::uint16_t tag_date_time = 306U;
constexpr std::uint16_t tag_artist = 315U;
constexpr std::uint16_t tag_copyright = 33432U;
// EXIF IFD 안
constexpr std::uint16_t tag_exif_version = 36864U;
constexpr std::uint16_t tag_date_time_original = 36867U;
constexpr std::uint16_t tag_date_time_digitized = 36868U;
constexpr std::uint16_t tag_offset_time = 36880U;
constexpr std::uint16_t tag_offset_time_original = 36881U;
constexpr std::uint16_t tag_offset_time_digitized = 36882U;
constexpr std::uint16_t tag_user_comment = 37510U;
// DNG
constexpr std::uint16_t tag_dng_version = 50706U;
constexpr std::uint16_t tag_dng_backward_version = 50707U;
constexpr std::uint16_t tag_unique_camera_model = 50708U;
constexpr std::uint16_t tag_white_level = 50717U;
constexpr std::uint16_t tag_color_matrix1 = 50721U;
constexpr std::uint16_t tag_as_shot_neutral = 50728U;
constexpr std::uint16_t tag_calibration_illuminant1 = 50778U;
constexpr std::uint16_t tag_colorimetric_reference = 50879U;
constexpr std::uint16_t tag_profile_name = 50936U;
constexpr std::uint16_t tag_profile_tone_curve = 50940U;
constexpr std::uint16_t tag_profile_embed_policy = 50941U;
constexpr std::uint16_t tag_default_black_render = 51110U;

constexpr std::uint16_t photometric_linear_raw = 34892U;
// EXIF LightSource 코드로 적은 D65. DNG CalibrationIlluminant1 이 같은 코드를 씁니다.
constexpr std::uint16_t light_source_d65 = 21U;

[[nodiscard]] const char* color_space_label(const negaflow::color::OutputColorSpace space) noexcept {
    switch (space) {
        case negaflow::color::OutputColorSpace::display_p3: return "Display P3";
        case negaflow::color::OutputColorSpace::adobe_rgb: return "Adobe RGB";
        case negaflow::color::OutputColorSpace::srgb: break;
    }
    return "sRGB";
}

/// macOS `FilmType: x; FilmStock: y` 와 같은 문자열.
[[nodiscard]] std::wstring film_comment(const ExportMetadataFields& fields, const bool include_stock) {
    std::wstring comment;
    if (!fields.film_type.empty()) {
        comment.append(L"FilmType: ").append(fields.film_type);
    }
    if (include_stock && !fields.film_stock.empty()) {
        if (!comment.empty()) {
            comment.append(L"; ");
        }
        comment.append(L"FilmStock: ").append(fields.film_stock);
    }
    return comment;
}

/// 정책에 따라 싣는 IFD0 쪽 메타데이터 항목. Windows TIFF 내보내기와 같은 규칙입니다: 저작권 표시는
/// 어느 정책에서도 남기고, 저작권만 남기는 정책은 장비·소프트웨어·날짜·해상도를 적지 않습니다.
[[nodiscard]] std::vector<TiffEntry> metadata_entries(const DngExportLimits& limits) {
    const ExportMetadataFields& fields = limits.metadata;
    std::vector<TiffEntry> entries{};
    if (!fields.artist.empty()) entries.push_back(tiff_ascii(tag_artist, fields.artist));
    if (!fields.copyright.empty()) entries.push_back(tiff_ascii(tag_copyright, fields.copyright));
    if (limits.metadata_policy == ExportMetadataPolicy::copyright_only) {
        return entries;
    }
    if (!fields.make.empty()) entries.push_back(tiff_ascii(tag_make, fields.make));
    if (!fields.model.empty()) entries.push_back(tiff_ascii(tag_model, fields.model));
    if (!fields.software.empty()) entries.push_back(tiff_ascii(tag_software, fields.software));
    if (!fields.captured_at.empty()) entries.push_back(tiff_ascii(tag_date_time, fields.captured_at));
    if (limits.output_dpi > 0U) {
        entries.push_back(tiff_rationals(tag_x_resolution, {{limits.output_dpi, 1U}}));
        entries.push_back(tiff_rationals(tag_y_resolution, {{limits.output_dpi, 1U}}));
        entries.push_back(tiff_shorts(tag_resolution_unit, {2U}));  // 인치
    }
    return entries;
}

/// EXIF IFD 항목: 촬영일과 필름 기록. 쓸 것이 없으면 비어 있어 IFD 를 만들지 않습니다.
[[nodiscard]] std::vector<TiffEntry> exif_entries(const DngExportLimits& limits) {
    std::vector<TiffEntry> entries{};
    if (limits.metadata_policy == ExportMetadataPolicy::copyright_only) {
        return entries;
    }
    const ExportMetadataFields& fields = limits.metadata;
    if (!fields.captured_at.empty()) {
        entries.push_back(tiff_ascii(tag_date_time_original, fields.captured_at));
        entries.push_back(tiff_ascii(tag_date_time_digitized, fields.captured_at));
        // 시각은 UTC 로 적으므로 오프셋도 함께 적는다. 오프셋 없는 EXIF 시각은 읽는 쪽이
        // 제 시간대로 해석해 몇 시간씩 어긋납니다.
        entries.push_back(tiff_ascii(tag_offset_time, std::string{"+00:00"}));
        entries.push_back(tiff_ascii(tag_offset_time_original, std::string{"+00:00"}));
        entries.push_back(tiff_ascii(tag_offset_time_digitized, std::string{"+00:00"}));
    }
    const std::wstring comment =
        film_comment(fields, limits.metadata_policy != ExportMetadataPolicy::minimal);
    if (!comment.empty()) {
        // EXIF UserComment: 앞 8바이트가 문자 코드 표시("ASCII" + 널 세 개)입니다.
        std::vector<std::uint8_t> value{'A', 'S', 'C', 'I', 'I', 0U, 0U, 0U};
        const std::vector<std::uint8_t> text = ascii_bytes(comment);
        value.insert(value.end(), text.begin(), text.end());
        entries.push_back(tiff_undefined(tag_user_comment, value));
    }
    if (!entries.empty()) {
        entries.push_back(tiff_undefined(tag_exif_version, {'0', '2', '3', '1'}));
    }
    return entries;
}

/// IFD0 전체. 줄 오프셋만 호출 때마다 다릅니다.
[[nodiscard]] std::vector<TiffEntry> ifd0_entries(
    const DngExportLimits& limits,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t rows_per_strip,
    const std::vector<std::uint32_t>& strip_offsets,
    const std::vector<std::uint32_t>& strip_byte_counts) {
    const std::array<double, 9> matrix = negaflow::color::d65_xyz_to_linear_rgb(limits.color_space);
    std::vector<std::pair<std::int32_t, std::int32_t>> color_matrix{};
    color_matrix.reserve(9U);
    for (const double value : matrix) {
        color_matrix.emplace_back(static_cast<std::int32_t>(std::lround(value * 1'000'000.0)), 1'000'000);
    }
    const std::string camera_model =
        std::string{"Negaflow Developed "} + color_space_label(limits.color_space);

    std::vector<TiffEntry> entries{
        tiff_longs(tag_new_subfile_type, {0U}),
        tiff_longs(tag_image_width, {width}),
        tiff_longs(tag_image_length, {height}),
        tiff_shorts(tag_bits_per_sample, {16U, 16U, 16U}),
        tiff_shorts(tag_compression, {1U}),
        tiff_shorts(tag_photometric, {photometric_linear_raw}),
        tiff_longs(tag_strip_offsets, strip_offsets),
        tiff_shorts(tag_orientation, {1U}),  // 변형은 화소에 구워져 있다
        tiff_shorts(tag_samples_per_pixel, {3U}),
        tiff_longs(tag_rows_per_strip, {rows_per_strip}),
        tiff_longs(tag_strip_byte_counts, strip_byte_counts),
        tiff_shorts(tag_planar_configuration, {1U}),
        tiff_bytes(tag_dng_version, {1U, 4U, 0U, 0U}),
        tiff_bytes(tag_dng_backward_version, {1U, 1U, 0U, 0U}),
        tiff_ascii(tag_unique_camera_model, camera_model),
        tiff_shorts(tag_white_level, {65535U, 65535U, 65535U}),
        tiff_signed_rationals(tag_color_matrix1, color_matrix),
        tiff_rationals(tag_as_shot_neutral, {{1U, 1U}, {1U, 1U}, {1U, 1U}}),
        tiff_shorts(tag_calibration_illuminant1, {light_source_d65}),
        tiff_shorts(tag_colorimetric_reference, {1U}),
        tiff_ascii(tag_profile_name, std::string{"Negaflow Linear Output"}),
        tiff_floats(tag_profile_tone_curve, {0.0F, 0.0F, 1.0F, 1.0F}),
        tiff_longs(tag_profile_embed_policy, {3U}),
        tiff_longs(tag_default_black_render, {1U}),
    };
    std::vector<TiffEntry> metadata = metadata_entries(limits);
    entries.insert(
        entries.end(),
        std::make_move_iterator(metadata.begin()),
        std::make_move_iterator(metadata.end()));
    return entries;
}

[[nodiscard]] DngExportStatus map_atomic_status(const AtomicOutputStatus status) noexcept {
    switch (status) {
        case AtomicOutputStatus::ok: return DngExportStatus::ok;
        case AtomicOutputStatus::destination_exists: return DngExportStatus::destination_exists;
        case AtomicOutputStatus::flush_failed: return DngExportStatus::flush_failed;
        case AtomicOutputStatus::published_file_invalid: return DngExportStatus::published_file_invalid;
        case AtomicOutputStatus::publish_failed: return DngExportStatus::publish_failed;
        case AtomicOutputStatus::allocation_failed: return DngExportStatus::allocation_failed;
        case AtomicOutputStatus::invalid_path:
        case AtomicOutputStatus::destination_query_failed:
        case AtomicOutputStatus::parent_unavailable:
        case AtomicOutputStatus::staging_create_failed: break;
    }
    return DngExportStatus::staging_create_failed;
}

/// 화상 배치만 확인합니다. 화소 값 검사(유한 값)는 줄 변환이 줄마다 하므로 전체를 한 번 더 훑지 않습니다.
[[nodiscard]] WorkingToSrgb16Status validate_layout(
    const negaflow::imaging::WorkingImage& working) noexcept {
    if (working.width == 0U || working.height == 0U) {
        return WorkingToSrgb16Status::invalid_dimensions;
    }
    if (working.stride_pixels < working.width) {
        return WorkingToSrgb16Status::invalid_stride;
    }
    const std::uint64_t pixel_count = static_cast<std::uint64_t>(working.stride_pixels) * working.height;
    if (pixel_count > std::numeric_limits<std::size_t>::max()) {
        return WorkingToSrgb16Status::size_overflow;
    }
    return working.pixels.size() == static_cast<std::size_t>(pixel_count)
        ? WorkingToSrgb16Status::ok
        : WorkingToSrgb16Status::buffer_size_mismatch;
}

/// 스트림에 바이트를 끝까지 씁니다.
[[nodiscard]] bool write_all(
    IStream* const stream,
    const void* const data,
    const std::size_t byte_count,
    std::uint32_t& native_error_code) noexcept {
    const auto* cursor = static_cast<const std::uint8_t*>(data);
    std::size_t remaining = byte_count;
    while (remaining != 0U) {
        const ULONG chunk = static_cast<ULONG>(std::min<std::size_t>(remaining, 64U * 1024U * 1024U));
        ULONG written = 0U;
        const HRESULT status = stream->Write(cursor, chunk, &written);
        if (FAILED(status) || written == 0U) {
            native_error_code = static_cast<std::uint32_t>(status);
            return false;
        }
        cursor += written;
        remaining -= written;
    }
    return true;
}

/// 줄 데이터를 다른 스레드에서 순서대로 씁니다. 변환(여러 코어)이 다음 묶음을 만드는 동안 이
/// 스레드가 앞 묶음을 파일에 쓰므로, 변환과 쓰기가 겹칩니다. 버퍼는 둘이며 쓰기가 끝나야 되돌아옵니다.
/// 쓰기 오류는 첫 것만 기억하고, 호출한 쪽이 다음 묶음 앞(`acquire`)이나 끝(`finish`)에서 받습니다.
class StripWriter final {
public:
    StripWriter(IStream* const stream, const std::size_t samples_per_buffer) : stream_(stream) {
        for (std::vector<std::uint16_t>& buffer : buffers_) {
            buffer.resize(samples_per_buffer);
        }
        thread_ = std::thread([this]() noexcept { run(); });
    }

    StripWriter(const StripWriter&) = delete;
    StripWriter& operator=(const StripWriter&) = delete;
    ~StripWriter() { static_cast<void>(finish()); }

    /// 비어 있는 버퍼를 하나 빌립니다. 앞의 쓰기가 실패했으면 nullptr 입니다.
    [[nodiscard]] std::uint16_t* acquire() {
        std::unique_lock lock(mutex_);
        changed_.wait(lock, [this] { return failed_ || !free_.empty(); });
        if (failed_) {
            return nullptr;
        }
        const std::size_t index = free_.front();
        free_.pop_front();
        return buffers_[index].data();
    }

    /// `acquire` 한 버퍼의 앞 `byte_count` 바이트를 쓰도록 넘깁니다.
    void submit(std::uint16_t* const buffer, const std::size_t byte_count) {
        {
            const std::lock_guard lock(mutex_);
            pending_.push_back({buffer == buffers_[0].data() ? 0U : 1U, byte_count});
        }
        changed_.notify_all();
    }

    /// 걸려 있는 쓰기를 모두 마치고 스레드를 접습니다. 성공했는지를 돌려줍니다.
    [[nodiscard]] bool finish() noexcept {
        {
            const std::lock_guard lock(mutex_);
            closed_ = true;
        }
        changed_.notify_all();
        if (thread_.joinable()) {
            thread_.join();
        }
        const std::lock_guard lock(mutex_);
        return !failed_;
    }

    [[nodiscard]] std::uint32_t native_error_code() const noexcept {
        const std::lock_guard lock(mutex_);
        return error_code_;
    }

private:
    struct Job final {
        std::size_t index{0U};
        std::size_t byte_count{0U};
    };

    void run() noexcept {
        for (;;) {
            Job job{};
            {
                std::unique_lock lock(mutex_);
                changed_.wait(lock, [this] { return closed_ || !pending_.empty(); });
                if (pending_.empty()) {
                    return;  // 닫혔고 남은 일이 없다
                }
                job = pending_.front();
                pending_.pop_front();
            }
            std::uint32_t error = 0U;
            const bool ok = write_all(stream_, buffers_[job.index].data(), job.byte_count, error);
            {
                const std::lock_guard lock(mutex_);
                if (!ok && !failed_) {
                    failed_ = true;
                    error_code_ = error;
                }
                free_.push_back(job.index);
            }
            changed_.notify_all();
        }
    }

    IStream* stream_;
    std::array<std::vector<std::uint16_t>, 2U> buffers_{};
    mutable std::mutex mutex_{};
    std::condition_variable changed_{};
    std::deque<std::size_t> free_{0U, 1U};
    std::deque<Job> pending_{};
    bool closed_{false};
    bool failed_{false};
    std::uint32_t error_code_{0U};
    std::thread thread_{};
};

}  // namespace

DngExportResult export_working_to_dng16(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const DngExportLimits& requested) noexcept {
    DngExportResult result{};
    try {
        DngExportLimits limits = requested;
        // 선형 값을 그대로 쓰되 출력 색공간 행렬은 적용합니다. 알파는 담지 않습니다.
        limits.conversion.encode_transfer = false;
        limits.conversion.preserve_alpha = false;
        limits.conversion.color_space = limits.color_space;
        limits.conversion.output_icc_profile = {};
        // 줄 단위로 흘려 쓰므로 전체 인코딩 크기는 메모리 한도가 아니라 파일 크기 한도가 정합니다.
        limits.conversion.max_encoded_pixel_bytes = limits.max_artifact_bytes;

        result.info.width = working.width;
        result.info.height = working.height;
        result.conversion_status = validate_layout(working);
        if (result.conversion_status != WorkingToSrgb16Status::ok) {
            result.status = DngExportStatus::working_conversion_failed;
            return result;
        }

        const std::uint64_t row_bytes = static_cast<std::uint64_t>(working.width) * 6U;
        const std::uint64_t pixel_bytes = row_bytes * working.height;
        const std::uint32_t rows_per_strip = static_cast<std::uint32_t>(std::clamp<std::uint64_t>(
            limits.strip_bytes / std::max<std::uint64_t>(row_bytes, 1U), 1U, working.height));
        const std::uint32_t strip_count = (working.height + rows_per_strip - 1U) / rows_per_strip;

        std::vector<std::uint32_t> byte_counts{};
        byte_counts.reserve(strip_count);
        for (std::uint32_t strip = 0U; strip < strip_count; ++strip) {
            const std::uint32_t rows = std::min(rows_per_strip, working.height - (strip * rows_per_strip));
            byte_counts.push_back(static_cast<std::uint32_t>(rows * row_bytes));
        }
        const std::vector<TiffEntry> exif = exif_entries(limits);
        // 블록 크기는 줄 오프셋 값이 아니라 항목 구성에만 달렸다. 임시 오프셋으로 한 번 만들어 크기를 잰다.
        const std::vector<std::uint8_t> sizing_block = make_tiff_header_block(
            ifd0_entries(limits, working.width, working.height, rows_per_strip,
                         std::vector<std::uint32_t>(strip_count, 0U), byte_counts),
            exif);
        const std::uint64_t pixel_start = (sizing_block.size() + 15U) & ~static_cast<std::uint64_t>(15U);
        if (pixel_start + pixel_bytes >= limits.max_artifact_bytes) {
            result.status = DngExportStatus::size_limit_exceeded;
            return result;
        }
        std::vector<std::uint32_t> offsets{};
        offsets.reserve(strip_count);
        for (std::uint32_t strip = 0U; strip < strip_count; ++strip) {
            offsets.push_back(static_cast<std::uint32_t>(
                pixel_start + (static_cast<std::uint64_t>(strip) * rows_per_strip * row_bytes)));
        }
        std::vector<std::uint8_t> block = make_tiff_header_block(
            ifd0_entries(limits, working.width, working.height, rows_per_strip, offsets, byte_counts), exif);
        if (block.size() != sizing_block.size()) {
            result.status = DngExportStatus::structure_verification_failed;
            return result;
        }
        block.resize(static_cast<std::size_t>(pixel_start), 0U);

        std::unique_ptr<AtomicOutputFile> output{};
        const AtomicOutputStatus create_status =
            AtomicOutputFile::create(destination, output, result.native_error_code);
        if (create_status != AtomicOutputStatus::ok) {
            result.status = map_atomic_status(create_status);
            return result;
        }
        const auto discard = [&]() noexcept { output->discard(result.cleanup_error_code); };

        if (!write_all(output->stream(), block.data(), block.size(), result.native_error_code)) {
            result.status = DngExportStatus::write_failed;
            discard();
            return result;
        }

        // 줄 묶음마다: 변환(출력 색공간의 선형 16비트, 여러 코어) → 파일에 이어 쓰기. 쓰기는 다른
        // 스레드가 하므로 변환이 다음 묶음을 만드는 동안 앞 묶음이 파일에 내려갑니다.
        const std::size_t samples_per_strip = static_cast<std::size_t>(rows_per_strip) * working.width * 3U;
        StripWriter writer(output->stream(), samples_per_strip);
        for (std::uint32_t strip = 0U; strip < strip_count; ++strip) {
            const std::uint32_t first_row = strip * rows_per_strip;
            const std::uint32_t rows = std::min(rows_per_strip, working.height - first_row);
            std::uint16_t* const samples = writer.acquire();
            if (samples == nullptr) {
                break;  // 앞의 쓰기가 실패했다. 아래에서 오류를 받는다.
            }
            const WorkingToSrgb16Status converted = convert_working_to_srgb16_rows(
                working, first_row, rows, samples, samples_per_strip,
                result.info.clipped_color_components, limits.conversion);
            if (converted != WorkingToSrgb16Status::ok) {
                static_cast<void>(writer.finish());  // 스트림을 놓은 뒤에 임시 파일을 버린다
                result.conversion_status = converted;
                result.status = DngExportStatus::working_conversion_failed;
                discard();
                return result;
            }
            writer.submit(samples, static_cast<std::size_t>(rows * row_bytes));
        }
        if (!writer.finish()) {
            result.native_error_code = writer.native_error_code();
            result.status = DngExportStatus::write_failed;
            discard();
            return result;
        }

        const AtomicOutputStatus flush_status = output->close_and_flush(result.native_error_code);
        if (flush_status != AtomicOutputStatus::ok) {
            result.status = map_atomic_status(flush_status);
            discard();
            return result;
        }
        const std::uint64_t expected_bytes = pixel_start + pixel_bytes;
        result.info.artifact_bytes = expected_bytes;
        result.info.strip_count = strip_count;
        // 게시 단계가 파일 크기가 기대와 같은지 확인한다(`expected_file_bytes`).
        const AtomicOutputStatus publish_status = output->publish(expected_bytes, result.native_error_code);
        result.info.published = publish_status == AtomicOutputStatus::ok ||
                                publish_status == AtomicOutputStatus::published_file_invalid;
        result.status = map_atomic_status(publish_status);
        if (!result.info.published) {
            discard();
        }
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DngExportStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = DngExportStatus::write_failed;
        return result;
    }
}

const char* dng_export_status_name(const DngExportStatus status) noexcept {
    switch (status) {
        case DngExportStatus::ok: return "ok";
        case DngExportStatus::working_conversion_failed: return "working_conversion_failed";
        case DngExportStatus::allocation_failed: return "allocation_failed";
        case DngExportStatus::size_limit_exceeded: return "size_limit_exceeded";
        case DngExportStatus::destination_exists: return "destination_exists";
        case DngExportStatus::staging_create_failed: return "staging_create_failed";
        case DngExportStatus::write_failed: return "write_failed";
        case DngExportStatus::flush_failed: return "flush_failed";
        case DngExportStatus::structure_verification_failed: return "structure_verification_failed";
        case DngExportStatus::publish_failed: return "publish_failed";
        case DngExportStatus::published_file_invalid: return "published_file_invalid";
    }
    return "unknown";
}

}  // namespace negaflow::output
