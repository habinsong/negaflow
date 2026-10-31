#include "negaflow/imageio/linear_dng_mapped.h"

#include "negaflow/core/parallel_rows.h"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <utility>
#include <vector>

namespace negaflow::imageio {
namespace {

constexpr std::uint16_t tag_new_subfile_type = 254U;
constexpr std::uint16_t tag_image_width = 256U;
constexpr std::uint16_t tag_image_length = 257U;
constexpr std::uint16_t tag_bits_per_sample = 258U;
constexpr std::uint16_t tag_compression = 259U;
constexpr std::uint16_t tag_photometric = 262U;
constexpr std::uint16_t tag_strip_offsets = 273U;
constexpr std::uint16_t tag_samples_per_pixel = 277U;
constexpr std::uint16_t tag_rows_per_strip = 278U;
constexpr std::uint16_t tag_strip_byte_counts = 279U;
constexpr std::uint16_t tag_planar_configuration = 284U;
constexpr std::uint16_t tag_tile_width = 322U;
constexpr std::uint16_t tag_sub_ifds = 330U;
constexpr std::uint16_t tag_linearization_table = 50712U;
constexpr std::uint32_t photometric_linear_raw = 34892U;

/// 매핑한 파일 한 벌입니다. 함수가 끝나면 반드시 닫습니다 — 파일을 붙잡지 않습니다.
class MappedFile final {
public:
    explicit MappedFile(const std::filesystem::path& path) noexcept {
        file_ = ::CreateFileW(path.c_str(), GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
        if (file_ == INVALID_HANDLE_VALUE) {
            return;
        }
        LARGE_INTEGER size{};
        if (!::GetFileSizeEx(file_, &size) || size.QuadPart <= 8) {
            return;
        }
        mapping_ = ::CreateFileMappingW(file_, nullptr, PAGE_READONLY, 0U, 0U, nullptr);
        if (mapping_ == nullptr) {
            return;
        }
        view_ = static_cast<const std::uint8_t*>(::MapViewOfFile(mapping_, FILE_MAP_READ, 0U, 0U, 0U));
        if (view_ != nullptr) {
            size_ = static_cast<std::uint64_t>(size.QuadPart);
        }
    }
    MappedFile(const MappedFile&) = delete;
    MappedFile& operator=(const MappedFile&) = delete;
    ~MappedFile() {
        if (view_ != nullptr) {
            ::UnmapViewOfFile(view_);
        }
        if (mapping_ != nullptr) {
            ::CloseHandle(mapping_);
        }
        if (file_ != INVALID_HANDLE_VALUE) {
            ::CloseHandle(file_);
        }
    }

    [[nodiscard]] const std::uint8_t* data() const noexcept { return view_; }
    [[nodiscard]] std::uint64_t size() const noexcept { return size_; }

private:
    HANDLE file_{INVALID_HANDLE_VALUE};
    HANDLE mapping_{nullptr};
    const std::uint8_t* view_{nullptr};
    std::uint64_t size_{0U};
};

/// TIFF 머리 읽기입니다. 범위를 벗어나는 읽기는 전부 실패로 돌립니다.
class TiffReader final {
public:
    TiffReader(const std::uint8_t* data, const std::uint64_t size, const bool little) noexcept
        : data_(data), size_(size), little_(little) {}

    [[nodiscard]] bool u16(const std::uint64_t at, std::uint16_t& value) const noexcept {
        if (at + 2U > size_) {
            return false;
        }
        value = little_ ? static_cast<std::uint16_t>(data_[at] | (data_[at + 1U] << 8U))
                        : static_cast<std::uint16_t>((data_[at] << 8U) | data_[at + 1U]);
        return true;
    }

    [[nodiscard]] bool u32(const std::uint64_t at, std::uint32_t& value) const noexcept {
        if (at + 4U > size_) {
            return false;
        }
        value = little_
            ? static_cast<std::uint32_t>(data_[at]) | (static_cast<std::uint32_t>(data_[at + 1U]) << 8U) |
                (static_cast<std::uint32_t>(data_[at + 2U]) << 16U) | (static_cast<std::uint32_t>(data_[at + 3U]) << 24U)
            : (static_cast<std::uint32_t>(data_[at]) << 24U) | (static_cast<std::uint32_t>(data_[at + 1U]) << 16U) |
                (static_cast<std::uint32_t>(data_[at + 2U]) << 8U) | static_cast<std::uint32_t>(data_[at + 3U]);
        return true;
    }

    /// SHORT·LONG 값 목록입니다. 다른 형식은 이 길에서 다루지 않습니다.
    [[nodiscard]] bool values(const std::uint64_t entry, std::vector<std::uint32_t>& out) const {
        std::uint16_t type = 0U;
        std::uint32_t count = 0U;
        if (!u16(entry + 2U, type) || !u32(entry + 4U, count) || (type != 3U && type != 4U) ||
            count == 0U || count > (1U << 20U)) {
            return false;
        }
        const std::uint64_t unit = type == 3U ? 2U : 4U;
        std::uint64_t at = entry + 8U;
        if (unit * count > 4U) {
            std::uint32_t offset = 0U;
            if (!u32(entry + 8U, offset)) {
                return false;
            }
            at = offset;
        }
        out.resize(count);
        for (std::uint32_t index = 0U; index < count; ++index) {
            if (type == 3U) {
                std::uint16_t value = 0U;
                if (!u16(at + index * unit, value)) {
                    return false;
                }
                out[index] = value;
            } else if (!u32(at + index * unit, out[index])) {
                return false;
            }
        }
        return true;
    }

private:
    const std::uint8_t* data_;
    std::uint64_t size_;
    bool little_;
};

struct RawIfd final {
    bool valid{false};
    std::uint32_t subfile{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<std::uint32_t> bits{};
    std::uint32_t compression{1U};
    std::uint32_t photometric{0U};
    std::uint32_t samples{1U};
    std::uint32_t rows_per_strip{std::numeric_limits<std::uint32_t>::max()};
    std::uint32_t planar{1U};
    bool tiled{false};
    bool linearized{false};
    std::vector<std::uint32_t> offsets{};
    std::vector<std::uint32_t> counts{};
    std::vector<std::uint32_t> sub_ifds{};
};

[[nodiscard]] RawIfd read_ifd(const TiffReader& tiff, const std::uint32_t offset) {
    RawIfd ifd{};
    std::uint16_t entries = 0U;
    if (!tiff.u16(offset, entries) || entries == 0U) {
        return ifd;
    }
    std::vector<std::uint32_t> values{};
    for (std::uint32_t index = 0U; index < entries; ++index) {
        const std::uint64_t entry = static_cast<std::uint64_t>(offset) + 2U + index * 12ULL;
        std::uint16_t tag = 0U;
        if (!tiff.u16(entry, tag)) {
            return ifd;
        }
        switch (tag) {
            case tag_tile_width:
                ifd.tiled = true;
                continue;
            case tag_linearization_table:
                ifd.linearized = true;
                continue;
            case tag_new_subfile_type:
            case tag_image_width:
            case tag_image_length:
            case tag_bits_per_sample:
            case tag_compression:
            case tag_photometric:
            case tag_strip_offsets:
            case tag_samples_per_pixel:
            case tag_rows_per_strip:
            case tag_strip_byte_counts:
            case tag_planar_configuration:
            case tag_sub_ifds:
                break;
            default:
                continue;
        }
        if (!tiff.values(entry, values)) {
            return ifd;
        }
        switch (tag) {
            case tag_new_subfile_type: ifd.subfile = values[0]; break;
            case tag_image_width: ifd.width = values[0]; break;
            case tag_image_length: ifd.height = values[0]; break;
            case tag_bits_per_sample: ifd.bits = values; break;
            case tag_compression: ifd.compression = values[0]; break;
            case tag_photometric: ifd.photometric = values[0]; break;
            case tag_strip_offsets: ifd.offsets = values; break;
            case tag_samples_per_pixel: ifd.samples = values[0]; break;
            case tag_rows_per_strip: ifd.rows_per_strip = values[0]; break;
            case tag_strip_byte_counts: ifd.counts = values; break;
            case tag_planar_configuration: ifd.planar = values[0]; break;
            case tag_sub_ifds: ifd.sub_ifds = values; break;
            default: break;
        }
    }
    ifd.valid = true;
    return ifd;
}

/// 면적 평균에 들고 다니는 값들입니다. `negaflow_libraw_make_linear_preview` 와 같은 가중치입니다.
struct ReduceJob final {
    const std::uint16_t* const* rows{nullptr};  // 원본 행 시작(표본 단위)
    bool swap_bytes{false};
    int flip{0};
    int source_width{0};   // 회전 전
    int source_height{0};
    int width{0};          // 회전 뒤(출력 방향)
    int height{0};
    int target_width{0};
    int target_height{0};
    double yscale{0.0};
    const int* start{nullptr};
    const int* end{nullptr};
    const float* first{nullptr};
    const float* last{nullptr};
    const float* span{nullptr};
    std::uint16_t* output{nullptr};
    std::atomic<bool>* failed{nullptr};
    const std::stop_token* stop{nullptr};
};

/// 출력 방향 (y, x) 의 원본 화소입니다(브리지의 `pixel` 과 같은 회전·뒤집기).
[[nodiscard]] inline const std::uint16_t* pixel(const ReduceJob& job, int y, int x) noexcept {
    if (job.flip & 4) {
        std::swap(y, x);
    }
    if (job.flip & 2) {
        y = job.source_height - 1 - y;
    }
    if (job.flip & 1) {
        x = job.source_width - 1 - x;
    }
    return job.rows[y] + static_cast<std::size_t>(x) * 3U;
}

[[nodiscard]] inline float value(const ReduceJob& job, const std::uint16_t raw) noexcept {
    return static_cast<float>(job.swap_bytes ? _byteswap_ushort(raw) : raw);
}

void reduce_rows(const ReduceJob& job, float* const accumulator, const int first_row, const int row_count) {
    for (int y = first_row; y < first_row + row_count; ++y) {
        if (job.stop->stop_requested() || job.failed->load(std::memory_order_relaxed)) {
            return;
        }
        const double top = y * job.yscale;
        const double bottom = std::min(static_cast<double>(job.height), (y + 1) * job.yscale);
        std::fill(accumulator, accumulator + static_cast<std::size_t>(job.target_width) * 3U, 0.f);
        for (int sy = static_cast<int>(top); static_cast<double>(sy) < bottom && sy < job.height; ++sy) {
            const float wy = static_cast<float>(
                std::min(static_cast<double>(sy + 1), bottom) - std::max(static_cast<double>(sy), top));
            for (int x = 0; x < job.target_width; ++x) {
                float r = 0, g = 0, b = 0;
                for (int sx = job.start[x]; sx < job.end[x]; ++sx) {
                    const float w = sx == job.start[x] ? job.first[x] : (sx == job.end[x] - 1 ? job.last[x] : 1.f);
                    const std::uint16_t* const p = pixel(job, sy, sx);
                    r += w * value(job, p[0]);
                    g += w * value(job, p[1]);
                    b += w * value(job, p[2]);
                }
                accumulator[x * 3] += wy * r;
                accumulator[x * 3 + 1] += wy * g;
                accumulator[x * 3 + 2] += wy * b;
            }
        }
        const float row_span = static_cast<float>(bottom - top);
        for (int x = 0; x < job.target_width; ++x) {
            const float norm = 1.f / (job.span[x] * row_span);
            std::uint16_t* const out = job.output + (static_cast<std::size_t>(y) * job.target_width + x) * 4U;
            for (int c = 0; c < 3; ++c) {
                out[c] = static_cast<std::uint16_t>(
                    std::min(65535.f, std::max(0.f, accumulator[x * 3 + c] * norm + 0.5f)));
            }
            out[3] = 65535U;
        }
    }
}

/// 매핑한 파일을 읽다가 디스크가 사라지거나 파일이 줄면 페이지 오류가 납니다. 그때 앱이 죽지
/// 않고 이 길만 실패하도록 구조적 예외를 여기서 받습니다(이 함수에는 소멸자가 있는 지역 변수가
/// 없어야 합니다).
void reduce_rows_guarded(const ReduceJob* const job, float* const accumulator, const int first_row,
                         const int row_count) noexcept {
    __try {
        reduce_rows(*job, accumulator, first_row, row_count);
    } __except (GetExceptionCode() == EXCEPTION_IN_PAGE_ERROR ? EXCEPTION_EXECUTE_HANDLER
                                                               : EXCEPTION_CONTINUE_SEARCH) {
        job->failed->store(true, std::memory_order_relaxed);
    }
}

/// 임시 첫 화면의 표본 하나입니다. `index` 는 출력 방향 좌표, `weight` 는 면적 가중치입니다.
struct Tap final {
    int index;
    float weight;
};

/// 출력 방향의 한 축을 면적 가중치로 나눕니다. `keep` 이 false 인 표본(읽지 않을 원본 행)은 뺍니다.
template <typename Keep>
[[nodiscard]] bool build_taps(const int length, const int out_length, const Keep keep,
                              std::vector<std::vector<Tap>>& taps, std::vector<float>& sums) {
    taps.assign(static_cast<std::size_t>(out_length), {});
    sums.assign(static_cast<std::size_t>(out_length), 0.f);
    const double scale = static_cast<double>(length) / out_length;
    for (int o = 0; o < out_length; ++o) {
        const double low = o * scale;
        const double high = std::min(static_cast<double>(length), (o + 1) * scale);
        double sum = 0.0;
        for (int s = static_cast<int>(low); static_cast<double>(s) < high && s < length; ++s) {
            if (!keep(s)) {
                continue;
            }
            const double weight =
                std::min(static_cast<double>(s + 1), high) - std::max(static_cast<double>(s), low);
            taps[static_cast<std::size_t>(o)].push_back({s, static_cast<float>(weight)});
            sum += weight;
        }
        if (sum <= 0.0) {
            return false;
        }
        sums[static_cast<std::size_t>(o)] = static_cast<float>(sum);
    }
    return true;
}

struct SampledTaps final {
    const std::vector<Tap>* rows{nullptr};
    const std::vector<Tap>* cols{nullptr};
    const float* row_sums{nullptr};
    const float* col_sums{nullptr};
};

void reduce_rows_sampled(const ReduceJob& job, const SampledTaps& taps, float* const accumulator,
                         const int first_row, const int row_count) {
    for (int y = first_row; y < first_row + row_count; ++y) {
        if (job.stop->stop_requested() || job.failed->load(std::memory_order_relaxed)) {
            return;
        }
        std::fill(accumulator, accumulator + static_cast<std::size_t>(job.target_width) * 3U, 0.f);
        for (const Tap& row : taps.rows[y]) {
            for (int x = 0; x < job.target_width; ++x) {
                float r = 0, g = 0, b = 0;
                for (const Tap& col : taps.cols[x]) {
                    const std::uint16_t* const p = pixel(job, row.index, col.index);
                    r += col.weight * value(job, p[0]);
                    g += col.weight * value(job, p[1]);
                    b += col.weight * value(job, p[2]);
                }
                accumulator[x * 3] += row.weight * r;
                accumulator[x * 3 + 1] += row.weight * g;
                accumulator[x * 3 + 2] += row.weight * b;
            }
        }
        for (int x = 0; x < job.target_width; ++x) {
            const float norm = 1.f / (taps.col_sums[x] * taps.row_sums[y]);
            std::uint16_t* const out = job.output + (static_cast<std::size_t>(y) * job.target_width + x) * 4U;
            for (int c = 0; c < 3; ++c) {
                out[c] = static_cast<std::uint16_t>(
                    std::min(65535.f, std::max(0.f, accumulator[x * 3 + c] * norm + 0.5f)));
            }
            out[3] = 65535U;
        }
    }
}

void reduce_rows_sampled_guarded(const ReduceJob* const job, const SampledTaps* const taps,
                                 float* const accumulator, const int first_row, const int row_count) noexcept {
    __try {
        reduce_rows_sampled(*job, *taps, accumulator, first_row, row_count);
    } __except (GetExceptionCode() == EXCEPTION_IN_PAGE_ERROR ? EXCEPTION_EXECUTE_HANDLER
                                                               : EXCEPTION_CONTINUE_SEARCH) {
        job->failed->store(true, std::memory_order_relaxed);
    }
}

}  // namespace

LinearDngMappedStatus decode_linear_dng_mapped(
    const std::filesystem::path& path,
    const std::uint32_t expected_width,
    const std::uint32_t expected_height,
    const int flip,
    const std::uint32_t target_width,
    const std::uint32_t target_height,
    const std::stop_token stop_token,
    DecodedImage& destination,
    const std::uint32_t source_row_step) noexcept {
    try {
        if (expected_width == 0U || expected_height == 0U || target_width == 0U || target_height == 0U ||
            expected_width > 65535U || expected_height > 65535U) {
            return LinearDngMappedStatus::not_applicable;
        }
        const MappedFile mapped{path};
        if (mapped.data() == nullptr) {
            return LinearDngMappedStatus::not_applicable;
        }
        const std::uint8_t* const base = mapped.data();
        const bool little = base[0] == 'I' && base[1] == 'I';
        if (!little && !(base[0] == 'M' && base[1] == 'M')) {
            return LinearDngMappedStatus::not_applicable;
        }
        const TiffReader tiff{base, mapped.size(), little};
        std::uint16_t magic = 0U;
        std::uint32_t first_ifd = 0U;
        if (!tiff.u16(2U, magic) || magic != 42U || !tiff.u32(4U, first_ifd)) {
            return LinearDngMappedStatus::not_applicable;  // BigTIFF(43) 등은 LibRaw 길로.
        }
        // 원본 화상은 IFD0 이나 그 SubIFD 에 있습니다(DNG 1.x). NewSubFileType 0 인 LinearRaw 를 찾습니다.
        RawIfd raw = read_ifd(tiff, first_ifd);
        if (!(raw.valid && raw.subfile == 0U && raw.photometric == photometric_linear_raw)) {
            const std::vector<std::uint32_t> children = raw.sub_ifds;
            raw = {};
            for (const std::uint32_t child : children) {
                RawIfd candidate = read_ifd(tiff, child);
                if (candidate.valid && candidate.subfile == 0U && candidate.photometric == photometric_linear_raw) {
                    raw = std::move(candidate);
                    break;
                }
            }
        }
        const std::uint32_t rows_per_strip = std::min(raw.rows_per_strip, raw.height);
        const bool sixteen_bit = !raw.bits.empty() &&
            std::all_of(raw.bits.begin(), raw.bits.end(), [](const std::uint32_t bits) { return bits == 16U; });
        if (!raw.valid || raw.photometric != photometric_linear_raw || raw.tiled || raw.linearized ||
            raw.compression != 1U || raw.samples != 3U || raw.planar != 1U || !sixteen_bit ||
            raw.width != expected_width || raw.height != expected_height || rows_per_strip == 0U ||
            raw.offsets.empty() || raw.offsets.size() != raw.counts.size() ||
            raw.offsets.size() != (raw.height + rows_per_strip - 1U) / rows_per_strip) {
            return LinearDngMappedStatus::not_applicable;
        }
        const std::uint64_t row_bytes = static_cast<std::uint64_t>(raw.width) * 6U;
        std::vector<const std::uint16_t*> rows(raw.height);
        for (std::size_t strip = 0U; strip < raw.offsets.size(); ++strip) {
            const std::uint32_t first_row = static_cast<std::uint32_t>(strip) * rows_per_strip;
            const std::uint32_t strip_rows = std::min(rows_per_strip, raw.height - first_row);
            const std::uint64_t needed = row_bytes * strip_rows;
            if (raw.counts[strip] < needed || raw.offsets[strip] + needed > mapped.size() ||
                (raw.offsets[strip] % 2U) != 0U) {
                return LinearDngMappedStatus::not_applicable;
            }
            for (std::uint32_t row = 0U; row < strip_rows; ++row) {
                rows[first_row + row] = reinterpret_cast<const std::uint16_t*>(
                    base + raw.offsets[strip] + row * row_bytes);
            }
        }

        const bool swapped = (flip & 4) != 0;
        const int width = static_cast<int>(swapped ? raw.height : raw.width);
        const int height = static_cast<int>(swapped ? raw.width : raw.height);
        const int out_width = static_cast<int>(target_width);
        const int out_height = static_cast<int>(target_height);
        if (out_width > width || out_height > height) {
            return LinearDngMappedStatus::not_applicable;
        }
        std::vector<int> start(out_width), end(out_width);
        std::vector<float> first(out_width), last(out_width), span(out_width);
        const double xscale = static_cast<double>(width) / out_width;
        for (int x = 0; x < out_width; ++x) {
            const double left = x * xscale;
            const double right = std::min(static_cast<double>(width), (x + 1) * xscale);
            const int s = static_cast<int>(left);
            const int e = std::max(s + 1, std::min(width, static_cast<int>(std::ceil(right))));
            start[x] = s;
            end[x] = e;
            span[x] = static_cast<float>(right - left);
            first[x] = static_cast<float>(e - s == 1 ? right - left : static_cast<double>(s + 1) - left);
            last[x] = static_cast<float>(e - s == 1 ? right - left : right - static_cast<double>(e - 1));
        }
        std::vector<std::uint16_t> samples(static_cast<std::size_t>(out_width) * out_height * 4U);
        std::atomic<bool> failed{false};
        ReduceJob job{};
        job.rows = rows.data();
        job.swap_bytes = !little;
        job.flip = flip;
        job.source_width = static_cast<int>(raw.width);
        job.source_height = static_cast<int>(raw.height);
        job.width = width;
        job.height = height;
        job.target_width = out_width;
        job.target_height = out_height;
        job.yscale = static_cast<double>(height) / out_height;
        job.start = start.data();
        job.end = end.data();
        job.first = first.data();
        job.last = last.data();
        job.span = span.data();
        job.output = samples.data();
        job.failed = &failed;
        job.stop = &stop_token;
        if (source_row_step > 1U) {
            // 원본 행은 회전이 없으면 출력 행이고, 90° 회전이면 출력 열입니다. 그 축에서만 걸러 냅니다.
            const int step = static_cast<int>(source_row_step);
            const int source_height = static_cast<int>(raw.height);
            const auto source_row_kept = [step, source_height, flip](const int index) {
                const int source_row = (flip & 2) ? source_height - 1 - index : index;
                return source_row % step == 0;
            };
            const auto every = [](int) { return true; };
            std::vector<std::vector<Tap>> row_taps;
            std::vector<std::vector<Tap>> col_taps;
            std::vector<float> row_sums;
            std::vector<float> col_sums;
            const bool built = swapped
                ? build_taps(height, out_height, every, row_taps, row_sums) &&
                      build_taps(width, out_width, source_row_kept, col_taps, col_sums)
                : build_taps(height, out_height, source_row_kept, row_taps, row_sums) &&
                      build_taps(width, out_width, every, col_taps, col_sums);
            if (!built) {
                return LinearDngMappedStatus::not_applicable;
            }
            const SampledTaps taps{row_taps.data(), col_taps.data(), row_sums.data(), col_sums.data()};
            negaflow::core::for_each_row_block(
                static_cast<std::uint32_t>(out_height),
                static_cast<std::uint64_t>(raw.width) * raw.height * 3U / source_row_step,
                [&job, &taps, out_width](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                    std::vector<float> accumulator;
                    try {
                        accumulator.resize(static_cast<std::size_t>(out_width) * 3U);
                    } catch (...) {
                        job.failed->store(true, std::memory_order_relaxed);
                        return;
                    }
                    reduce_rows_sampled_guarded(&job, &taps, accumulator.data(), static_cast<int>(first_row),
                                                static_cast<int>(row_count));
                });
        } else {
            // 실제로 읽는 양(원본 표본 수)을 넘깁니다 — 출력 행 수만 넘기면 병렬화가 조용히 꺼집니다.
            negaflow::core::for_each_row_block(
                static_cast<std::uint32_t>(out_height),
                static_cast<std::uint64_t>(raw.width) * raw.height * 3U,
                [&job, out_width](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                    std::vector<float> accumulator;
                    try {
                        accumulator.resize(static_cast<std::size_t>(out_width) * 3U);
                    } catch (...) {
                        job.failed->store(true, std::memory_order_relaxed);
                        return;
                    }
                    reduce_rows_guarded(&job, accumulator.data(), static_cast<int>(first_row),
                                        static_cast<int>(row_count));
                });
        }
        if (stop_token.stop_requested()) {
            return LinearDngMappedStatus::cancelled;
        }
        if (failed.load()) {
            return LinearDngMappedStatus::not_applicable;
        }
        destination.width = target_width;
        destination.height = target_height;
        destination.stride_bytes = target_width * 8U;
        destination.layout = DecodedPixelLayout::rgba16;
        destination.alpha_mode = AlphaMode::unassociated;
        destination.untagged_rgb_transfer = UntaggedRgbTransfer::linear_scanner;
        destination.samples = std::move(samples);
        return LinearDngMappedStatus::ok;
    } catch (...) {
        return LinearDngMappedStatus::not_applicable;
    }
}

}  // namespace negaflow::imageio
