// DNG 내보내기 시험. 쓴 파일을 기록기와 별개로 짠 최소 TIFF 해석기로 다시 읽어 태그와 화소를 확인한다.
// 합성 화상만 쓴다.
#include "negaflow/output/dng_linear_export.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <map>
#include <string>
#include <vector>

namespace {

namespace out = negaflow::output;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-dng-export-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary DNG export directory is created");
    }
    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;
    ~TempDirectory() {
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
    }
    [[nodiscard]] const std::filesystem::path& path() const noexcept { return path_; }

private:
    std::filesystem::path path_{};
};

// ── 시험용 TIFF 해석기(리틀엔디언) ────────────────────────────────────────────────────────

std::uint32_t le32(const std::vector<std::uint8_t>& b, const std::size_t at) {
    return static_cast<std::uint32_t>(b[at]) | (static_cast<std::uint32_t>(b[at + 1U]) << 8U) |
           (static_cast<std::uint32_t>(b[at + 2U]) << 16U) | (static_cast<std::uint32_t>(b[at + 3U]) << 24U);
}
std::uint16_t le16(const std::vector<std::uint8_t>& b, const std::size_t at) {
    return static_cast<std::uint16_t>(b[at] | (b[at + 1U] << 8U));
}

struct Entry final {
    std::uint16_t type{0U};
    std::uint32_t count{0U};
    std::vector<std::uint8_t> bytes{};

    [[nodiscard]] std::vector<std::uint32_t> longs() const {
        std::vector<std::uint32_t> values{};
        for (std::size_t at = 0U; at + 4U <= bytes.size(); at += 4U) values.push_back(le32(bytes, at));
        return values;
    }
    [[nodiscard]] std::vector<std::uint16_t> shorts() const {
        std::vector<std::uint16_t> values{};
        for (std::size_t at = 0U; at + 2U <= bytes.size(); at += 2U) values.push_back(le16(bytes, at));
        return values;
    }
    [[nodiscard]] std::string text() const {
        std::string value(bytes.begin(), bytes.end());
        value.resize(value.find('\0') == std::string::npos ? value.size() : value.find('\0'));
        return value;
    }
    [[nodiscard]] std::vector<double> rationals() const {
        std::vector<double> values{};
        for (std::size_t at = 0U; at + 8U <= bytes.size(); at += 8U) {
            values.push_back(static_cast<double>(le32(bytes, at)) / static_cast<double>(le32(bytes, at + 4U)));
        }
        return values;
    }
    [[nodiscard]] std::vector<double> signed_rationals() const {
        std::vector<double> values{};
        for (std::size_t at = 0U; at + 8U <= bytes.size(); at += 8U) {
            values.push_back(static_cast<double>(static_cast<std::int32_t>(le32(bytes, at))) /
                             static_cast<double>(static_cast<std::int32_t>(le32(bytes, at + 4U))));
        }
        return values;
    }
};

using Directory = std::map<std::uint16_t, Entry>;

struct Parsed final {
    std::vector<std::uint8_t> bytes{};
    Directory ifd0{};
    Directory exif{};
};

constexpr std::size_t type_size(const std::uint16_t type) {
    switch (type) {
        case 3: return 2U;
        case 4: case 11: return 4U;
        case 5: case 10: return 8U;
        default: return 1U;
    }
}

Directory directory(const std::vector<std::uint8_t>& bytes, const std::size_t offset) {
    Directory entries{};
    const std::size_t count = le16(bytes, offset);
    int previous = -1;
    for (std::size_t index = 0U; index < count; ++index) {
        const std::size_t at = offset + 2U + (index * 12U);
        const std::uint16_t tag = le16(bytes, at);
        expect(static_cast<int>(tag) > previous, "IFD 항목은 태그 오름차순이다");
        previous = tag;
        Entry entry{};
        entry.type = le16(bytes, at + 2U);
        entry.count = le32(bytes, at + 4U);
        const std::size_t size = entry.count * type_size(entry.type);
        const std::size_t value_at = size <= 4U ? at + 8U : le32(bytes, at + 8U);
        if (size > 4U) expect(value_at % 2U == 0U, "바깥 값은 짝수 오프셋이다");
        entry.bytes.assign(bytes.begin() + static_cast<std::ptrdiff_t>(value_at),
                           bytes.begin() + static_cast<std::ptrdiff_t>(value_at + size));
        entries[tag] = std::move(entry);
    }
    expect(le32(bytes, offset + 2U + (count * 12U)) == 0U, "다음 IFD 가 없다");
    return entries;
}

Parsed parse(const std::filesystem::path& path) {
    Parsed parsed{};
    std::ifstream stream(path, std::ios::binary);
    parsed.bytes.assign(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
    expect(parsed.bytes.size() > 8U && parsed.bytes[0] == 0x49U && parsed.bytes[1] == 0x49U &&
               le16(parsed.bytes, 2U) == 42U,
           "리틀엔디언 TIFF 머리말");
    if (parsed.bytes.size() <= 8U) return parsed;
    parsed.ifd0 = directory(parsed.bytes, le32(parsed.bytes, 4U));
    if (const auto pointer = parsed.ifd0.find(34665U); pointer != parsed.ifd0.end()) {
        parsed.exif = directory(parsed.bytes, pointer->second.longs()[0]);
    }
    return parsed;
}

std::vector<std::uint16_t> pixels(const Parsed& parsed) {
    std::vector<std::uint16_t> samples{};
    const auto offsets = parsed.ifd0.at(273U).longs();
    const auto counts = parsed.ifd0.at(279U).longs();
    for (std::size_t strip = 0U; strip < offsets.size(); ++strip) {
        for (std::size_t at = offsets[strip]; at < offsets[strip] + counts[strip]; at += 2U) {
            samples.push_back(le16(parsed.bytes, at));
        }
    }
    return samples;
}

// ── 합성 입력 ───────────────────────────────────────────────────────────────────────────

constexpr std::uint32_t width = 53U;
constexpr std::uint32_t height = 31U;

std::array<float, 3> value_at(const std::uint32_t x, const std::uint32_t y) {
    return {static_cast<float>(x) / static_cast<float>(width - 1U),
            static_cast<float>(y) / static_cast<float>(height - 1U),
            static_cast<float>((x * 7U + y * 3U) % 17U) / 16.0F};
}

negaflow::imaging::WorkingImage make_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const auto v = value_at(x, y);
            image.pixels[static_cast<std::size_t>(y) * width + x] = {v[0], v[1], v[2], 1.0F};
        }
    }
    return image;
}

out::DngExportLimits small_strips() {
    out::DngExportLimits limits{};
    limits.strip_bytes = 1000U;  // 여러 묶음이 되도록 작게 잡는다
    return limits;
}

void report(const out::DngExportResult& result) {
    if (result.status != out::DngExportStatus::ok) {
        std::cerr << "  status=" << out::dng_export_status_name(result.status)
                  << " conversion=" << out::working_to_srgb16_status_name(result.conversion_status)
                  << " native=0x" << std::hex << result.native_error_code << std::dec << '\n';
    }
}

// ── 시험 ────────────────────────────────────────────────────────────────────────────────

void test_structure_and_pixels(const std::filesystem::path& folder) {
    const auto path = folder / L"structure.dng";
    const auto result = out::export_working_to_dng16(make_image(), path, small_strips());
    report(result);
    expect(result.status == out::DngExportStatus::ok, "DNG 가 게시된다");
    expect(result.info.published, "게시됨");
    const Parsed file = parse(path);
    const Directory& t = file.ifd0;

    expect(t.at(256U).longs() == std::vector<std::uint32_t>{width}, "ImageWidth");
    expect(t.at(257U).longs() == std::vector<std::uint32_t>{height}, "ImageLength");
    expect(t.at(258U).shorts() == std::vector<std::uint16_t>({16U, 16U, 16U}), "BitsPerSample 16x3");
    expect(t.at(259U).shorts() == std::vector<std::uint16_t>{1U}, "무압축");
    expect(t.at(262U).shorts() == std::vector<std::uint16_t>{34892U}, "LinearRaw");
    expect(t.at(277U).shorts() == std::vector<std::uint16_t>{3U}, "SamplesPerPixel");
    expect(t.at(274U).shorts() == std::vector<std::uint16_t>{1U}, "Orientation 은 DNG 필수 태그");
    expect(t.at(254U).longs() == std::vector<std::uint32_t>{0U}, "NewSubfileType 0");
    expect(t.at(50706U).bytes == std::vector<std::uint8_t>({1U, 4U, 0U, 0U}), "DNGVersion");
    expect(t.at(50707U).bytes == std::vector<std::uint8_t>({1U, 1U, 0U, 0U}), "DNGBackwardVersion");
    expect(t.at(50708U).text().rfind("Negaflow", 0U) == 0U, "UniqueCameraModel");
    expect(t.at(50717U).shorts() == std::vector<std::uint16_t>({65535U, 65535U, 65535U}), "WhiteLevel");
    expect(t.at(50728U).rationals() == std::vector<double>({1.0, 1.0, 1.0}), "AsShotNeutral (1,1,1)");
    // 독립 기준: 공개된 sRGB(D65) XYZ → 선형 RGB 행렬(IEC 61966-2-1 의 소수 자릿수 그대로).
    const std::array<double, 9> srgb_xyz_to_rgb{3.2406, -1.5372, -0.4986, -0.9689, 1.8758, 0.0415, 0.0557, -0.2040, 1.0570};
    const auto color_matrix = t.at(50721U).signed_rationals();
    expect(color_matrix.size() == 9U, "ColorMatrix1 은 9개다");
    for (std::size_t index = 0U; index < 9U && color_matrix.size() == 9U; ++index) {
        expect(std::abs(color_matrix[index] - srgb_xyz_to_rgb[index]) < 5.0e-4, "sRGB ColorMatrix1 이 규격 행렬과 같다");
    }
    expect(t.at(50778U).shorts() == std::vector<std::uint16_t>{21U}, "CalibrationIlluminant1 = D65");
    expect(t.at(50879U).shorts() == std::vector<std::uint16_t>{1U}, "ColorimetricReference = 출력 기준");
    expect(t.at(51110U).longs() == std::vector<std::uint32_t>{1U}, "DefaultBlackRender 없음");

    const std::uint32_t rows_per_strip = t.at(278U).longs()[0];
    expect(rows_per_strip == 1000U / (width * 6U), "묶음 줄 수");
    const auto counts = t.at(279U).longs();
    expect(counts.size() == (height + rows_per_strip - 1U) / rows_per_strip, "묶음 개수");
    std::uint64_t total = 0U;
    for (const auto count : counts) total += count;
    expect(total == static_cast<std::uint64_t>(width) * height * 6U, "묶음 바이트 합");
    expect(t.at(273U).longs().back() + counts.back() == file.bytes.size(), "줄 데이터가 파일 끝까지다");
    expect(result.info.artifact_bytes == file.bytes.size(), "보고한 파일 크기가 실제와 같다");

    const auto samples = pixels(file);
    expect(samples.size() == static_cast<std::size_t>(width) * height * 3U, "화소 수");
    int worst = 0;
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const auto v = value_at(x, y);
            for (std::size_t c = 0U; c < 3U; ++c) {
                const int reference = static_cast<int>(std::lround(static_cast<double>(v[c]) * 65535.0));
                const int actual = samples[(static_cast<std::size_t>(y) * width + x) * 3U + c];
                worst = std::max(worst, std::abs(actual - reference));
            }
        }
    }
    expect(worst <= 1, "선형 sRGB 화소가 같은 줄 순서로 그대로 기록된다");
}

void test_wide_gamut(const std::filesystem::path& folder) {
    // 독립 기준: 공개 규격의 sRGB 행렬(IEC 61966-2-1)을 직접 적은 선형 sRGB → XYZ(D65).
    constexpr double to_xyz[3][3] = {
        {0.4124564, 0.3575761, 0.1804375},
        {0.2126729, 0.7151522, 0.0721750},
        {0.0193339, 0.1191920, 0.9503041},
    };
    for (const auto space : {negaflow::color::OutputColorSpace::display_p3,
                             negaflow::color::OutputColorSpace::adobe_rgb}) {
        const auto path = folder / (space == negaflow::color::OutputColorSpace::display_p3 ? L"p3.dng" : L"adobe.dng");
        out::DngExportLimits limits{};
        limits.color_space = space;
        const auto result = out::export_working_to_dng16(make_image(), path, limits);
        report(result);
        expect(result.status == out::DngExportStatus::ok, "와이드 감마 DNG 가 게시된다");
        const Parsed file = parse(path);
        const auto samples = pixels(file);
        const auto matrix = file.ifd0.at(50721U).signed_rationals();
        expect(matrix.size() == 9U, "ColorMatrix1 은 9개다");

        // 백색(D65, xy = 0.3127, 0.3290)은 (1,1,1) 로 가야 한다.
        const double white[3] = {0.3127 / 0.3290, 1.0, (1.0 - 0.3127 - 0.3290) / 0.3290};
        for (std::size_t row = 0U; row < 3U; ++row) {
            const double v = matrix[row * 3U] * white[0] + matrix[row * 3U + 1U] * white[1] + matrix[row * 3U + 2U] * white[2];
            expect(std::abs(v - 1.0) < 2.0e-4, "D65 백색이 (1,1,1) 로 간다");
        }

        // 화소: 선형 sRGB → XYZ → 대상 RGB(= ColorMatrix1 × XYZ). 같은 행렬을 쓰므로 어긋나면 변환이 잘못이다.
        double worst = 0.0;
        for (const auto [x, y] : {std::pair<std::uint32_t, std::uint32_t>{0U, 0U}, {52U, 0U}, {0U, 30U}, {52U, 30U}, {17U, 9U}, {30U, 21U}}) {
            const auto v = value_at(x, y);
            double xyz[3]{};
            for (std::size_t r = 0U; r < 3U; ++r) {
                xyz[r] = to_xyz[r][0] * v[0] + to_xyz[r][1] * v[1] + to_xyz[r][2] * v[2];
            }
            for (std::size_t c = 0U; c < 3U; ++c) {
                const double target = matrix[c * 3U] * xyz[0] + matrix[c * 3U + 1U] * xyz[1] + matrix[c * 3U + 2U] * xyz[2];
                const double clamped = std::clamp(target, 0.0, 1.0);
                worst = std::max(worst, std::abs(static_cast<double>(samples[(static_cast<std::size_t>(y) * width + x) * 3U + c]) / 65535.0 - clamped));
            }
        }
        expect(worst < 3.0e-4, "와이드 감마 변환이 독립 계산과 같다");
    }
}

void test_metadata_policies(const std::filesystem::path& folder) {
    out::DngExportLimits limits{};
    limits.output_dpi = 3200U;
    limits.metadata.make = L"Epson";
    limits.metadata.model = L"V850";
    limits.metadata.software = L"Negaflow 9";
    limits.metadata.artist = L"Kim";
    limits.metadata.copyright = L"(c) Kim";
    limits.metadata.film_type = L"colorNegative";
    limits.metadata.film_stock = L"Portra 400";
    limits.metadata.captured_at = L"2023:11:14 22:13:20";

    limits.metadata_policy = out::ExportMetadataPolicy::remove_location;
    const auto all_path = folder / L"all.dng";
    expect(out::export_working_to_dng16(make_image(), all_path, limits).status == out::DngExportStatus::ok, "정책 all 게시");
    const Parsed all = parse(all_path);
    expect(all.ifd0.at(271U).text() == "Epson" && all.ifd0.at(272U).text() == "V850", "Make/Model");
    expect(all.ifd0.at(305U).text() == "Negaflow 9", "Software");
    expect(all.ifd0.at(306U).text() == "2023:11:14 22:13:20", "DateTime");
    expect(all.ifd0.at(282U).rationals() == std::vector<double>{3200.0}, "XResolution");
    expect(all.ifd0.at(296U).shorts() == std::vector<std::uint16_t>{2U}, "ResolutionUnit 인치");
    expect(all.ifd0.at(315U).text() == "Kim" && all.ifd0.at(33432U).text() == "(c) Kim", "저작권 표시");
    expect(all.exif.at(36867U).text() == "2023:11:14 22:13:20", "DateTimeOriginal");
    expect(all.exif.at(36881U).text() == "+00:00", "UTC 오프셋");
    const std::string comment_all(all.exif.at(37510U).bytes.begin() + 8, all.exif.at(37510U).bytes.end());
    expect(comment_all == "FilmType: colorNegative; FilmStock: Portra 400", "UserComment 에 필름 스톡도 담는다");

    // minimal: 사용자가 적은 필름 스톡은 싣지 않는다(Windows TIFF 내보내기와 같다).
    limits.metadata_policy = out::ExportMetadataPolicy::minimal;
    const auto minimal_path = folder / L"minimal.dng";
    expect(out::export_working_to_dng16(make_image(), minimal_path, limits).status == out::DngExportStatus::ok, "정책 minimal 게시");
    const Parsed minimal = parse(minimal_path);
    const std::string comment_minimal(minimal.exif.at(37510U).bytes.begin() + 8, minimal.exif.at(37510U).bytes.end());
    expect(comment_minimal == "FilmType: colorNegative", "minimal 은 필름 스톡을 싣지 않는다");
    expect(minimal.ifd0.count(315U) == 1U, "저작권 표시는 어느 정책에서도 남는다");

    // copyright_only: 저작권만 남기고 장비·소프트웨어·날짜·해상도는 적지 않는다.
    limits.metadata_policy = out::ExportMetadataPolicy::copyright_only;
    const auto copyright_path = folder / L"copyright.dng";
    expect(out::export_working_to_dng16(make_image(), copyright_path, limits).status == out::DngExportStatus::ok, "정책 copyright_only 게시");
    const Parsed copyright = parse(copyright_path);
    expect(copyright.ifd0.at(315U).text() == "Kim" && copyright.ifd0.at(33432U).text() == "(c) Kim", "저작권만 남는다");
    for (const std::uint16_t tag : std::array<std::uint16_t, 8>{271U, 272U, 305U, 306U, 282U, 283U, 296U, 34665U}) {
        expect(copyright.ifd0.count(tag) == 0U, "copyright_only 는 장비·날짜 태그를 적지 않는다");
    }
    expect(copyright.exif.empty(), "copyright_only 는 EXIF IFD 가 없다");
}

void test_failures_are_visible(const std::filesystem::path& folder) {
    // 이미 있는 목적지는 덮어쓰지 않고 거절한다.
    const auto existing = folder / L"existing.dng";
    {
        std::ofstream marker(existing, std::ios::binary);
        marker << "keep";
    }
    const auto exists_result = out::export_working_to_dng16(make_image(), existing);
    expect(exists_result.status == out::DngExportStatus::destination_exists, "있는 파일은 거절한다");
    {
        std::ifstream marker(existing, std::ios::binary);
        std::string content((std::istreambuf_iterator<char>(marker)), std::istreambuf_iterator<char>());
        expect(content == "keep", "거절한 목적지는 그대로다");
    }

    // 유한하지 않은 화소는 줄 변환이 걸러 내고 파일을 남기지 않는다.
    auto broken = make_image();
    broken.pixels[100].red = std::numeric_limits<float>::quiet_NaN();
    const auto broken_path = folder / L"broken.dng";
    const auto broken_result = out::export_working_to_dng16(broken, broken_path, small_strips());
    expect(broken_result.status == out::DngExportStatus::working_conversion_failed, "NaN 화소는 변환 실패로 보고한다");
    expect(broken_result.conversion_status == out::WorkingToSrgb16Status::non_finite_pixel, "실패 이유가 non_finite_pixel");
    expect(!std::filesystem::exists(broken_path), "실패한 내보내기는 목적지에 파일을 남기지 않는다");

    // 빈 화상.
    const auto empty_result = out::export_working_to_dng16({}, folder / L"empty.dng");
    expect(empty_result.status == out::DngExportStatus::working_conversion_failed, "빈 화상은 거절한다");
    expect(!std::filesystem::exists(folder / L"empty.dng"), "빈 화상은 파일을 남기지 않는다");

    // 파일 크기 한도.
    out::DngExportLimits tiny{};
    tiny.max_artifact_bytes = 1000U;
    expect(out::export_working_to_dng16(make_image(), folder / L"tiny.dng", tiny).status ==
               out::DngExportStatus::size_limit_exceeded, "크기 한도를 넘으면 거절한다");
    expect(!std::filesystem::exists(folder / L"tiny.dng"), "한도 초과는 파일을 남기지 않는다");
}

}  // namespace

int main() {
    const TempDirectory temp{};
    test_structure_and_pixels(temp.path());
    test_wide_gamut(temp.path());
    test_metadata_policies(temp.path());
    test_failures_are_visible(temp.path());
    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "dng_linear_export_tests passed\n";
    return 0;
}
