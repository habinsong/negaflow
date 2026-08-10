#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/grain_mend.h"

#include <objbase.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

struct DecodedSrgb final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<std::uint8_t> rgba{};
    negaflow::imaging::WorkingImage linear{};
};

struct ReferenceMetrics final {
    double psnr_delta{0.0};
    double improved_pixel_fraction{0.0};
    double regressed_pixel_fraction{0.0};
    std::size_t changed_pixel_count{0U};
};

class ComApartment final {
public:
    ComApartment() {
        const HRESULT status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (FAILED(status)) {
            throw std::runtime_error("COM initialization failed");
        }
        initialized_ = true;
    }

    ~ComApartment() {
        if (initialized_) {
            CoUninitialize();
        }
    }

    ComApartment(const ComApartment&) = delete;
    ComApartment& operator=(const ComApartment&) = delete;

private:
    bool initialized_{false};
};

[[nodiscard]] std::size_t checked_byte_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    constexpr std::size_t channels = 4U;
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height) / channels) {
        throw std::runtime_error("invalid image dimensions");
    }
    return static_cast<std::size_t>(width) * height * channels;
}

[[nodiscard]] DecodedSrgb decode_srgb_jpeg(
    IWICImagingFactory* const factory,
    const std::filesystem::path& path) {
    ComPtr<IWICBitmapDecoder> decoder{};
    HRESULT status = factory->CreateDecoderFromFilename(
        path.c_str(),
        nullptr,
        GENERIC_READ,
        WICDecodeMetadataCacheOnLoad,
        &decoder);
    if (FAILED(status)) {
        throw std::runtime_error("WIC could not open " + path.string());
    }

    ComPtr<IWICBitmapFrameDecode> frame{};
    status = decoder->GetFrame(0U, &frame);
    if (FAILED(status)) {
        throw std::runtime_error("WIC could not decode " + path.string());
    }

    DecodedSrgb result{};
    status = frame->GetSize(&result.width, &result.height);
    if (FAILED(status)) {
        throw std::runtime_error("WIC could not read dimensions");
    }
    const std::size_t byte_count = checked_byte_count(result.width, result.height);
    if (static_cast<std::size_t>(result.width) >
        std::numeric_limits<UINT>::max() / 4U ||
        byte_count > std::numeric_limits<UINT>::max()) {
        throw std::runtime_error("image exceeds WIC buffer limits");
    }

    ComPtr<IWICFormatConverter> converter{};
    status = factory->CreateFormatConverter(&converter);
    if (FAILED(status)) {
        throw std::runtime_error("WIC converter creation failed");
    }
    status = converter->Initialize(
        frame.Get(),
        GUID_WICPixelFormat32bppRGBA,
        WICBitmapDitherTypeNone,
        nullptr,
        0.0,
        WICBitmapPaletteTypeCustom);
    if (FAILED(status)) {
        throw std::runtime_error("WIC RGBA conversion failed");
    }

    result.rgba.resize(byte_count);
    status = converter->CopyPixels(
        nullptr,
        result.width * 4U,
        static_cast<UINT>(byte_count),
        result.rgba.data());
    if (FAILED(status)) {
        throw std::runtime_error("WIC pixel copy failed");
    }

    result.linear.width = result.width;
    result.linear.height = result.height;
    result.linear.stride_pixels = result.width;
    result.linear.pixels.resize(byte_count / 4U);
    for (std::size_t pixel = 0U; pixel < result.linear.pixels.size(); ++pixel) {
        const std::size_t offset = pixel * 4U;
        result.linear.pixels[pixel] = {
            negaflow::color::srgb_encoded_to_linear(
                static_cast<float>(result.rgba[offset]) / 255.0F),
            negaflow::color::srgb_encoded_to_linear(
                static_cast<float>(result.rgba[offset + 1U]) / 255.0F),
            negaflow::color::srgb_encoded_to_linear(
                static_cast<float>(result.rgba[offset + 2U]) / 255.0F),
            1.0F,
        };
    }
    return result;
}

[[nodiscard]] std::uint8_t encode_channel(const float linear) noexcept {
    const float encoded = std::clamp(
        negaflow::color::linear_to_srgb_encoded(linear),
        0.0F,
        1.0F);
    return static_cast<std::uint8_t>(std::lround(encoded * 255.0F));
}

[[nodiscard]] std::vector<std::uint8_t> render_srgb8(
    const negaflow::imaging::WorkingImage& image) {
    std::vector<std::uint8_t> result(image.pixels.size() * 4U, 255U);
    for (std::size_t pixel = 0U; pixel < image.pixels.size(); ++pixel) {
        const std::size_t offset = pixel * 4U;
        result[offset] = encode_channel(image.pixels[pixel].red);
        result[offset + 1U] = encode_channel(image.pixels[pixel].green);
        result[offset + 2U] = encode_channel(image.pixels[pixel].blue);
    }
    return result;
}

void write_rgba_png(
    IWICImagingFactory* const factory,
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& rgba,
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<std::uint8_t> bgra = rgba;
    for (std::size_t offset = 0U; offset < bgra.size(); offset += 4U) {
        std::swap(bgra[offset], bgra[offset + 2U]);
    }
    std::error_code remove_error{};
    static_cast<void>(std::filesystem::remove(path, remove_error));
    ComPtr<IWICStream> stream{};
    HRESULT status = factory->CreateStream(&stream);
    if (SUCCEEDED(status)) {
        status = stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE);
    }
    ComPtr<IWICBitmapEncoder> encoder{};
    if (SUCCEEDED(status)) {
        status = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
    }
    if (SUCCEEDED(status)) {
        status = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
    }
    ComPtr<IWICBitmapFrameEncode> frame{};
    if (SUCCEEDED(status)) {
        status = encoder->CreateNewFrame(&frame, nullptr);
    }
    if (SUCCEEDED(status)) {
        status = frame->Initialize(nullptr);
    }
    if (SUCCEEDED(status)) {
        status = frame->SetSize(width, height);
    }
    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
    if (SUCCEEDED(status)) {
        status = frame->SetPixelFormat(&format);
    }
    if (SUCCEEDED(status) &&
        IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA) == FALSE) {
        status = E_FAIL;
    }
    if (SUCCEEDED(status)) {
        status = frame->WritePixels(
            height,
            width * 4U,
            static_cast<UINT>(bgra.size()),
            bgra.data());
    }
    if (SUCCEEDED(status)) {
        status = frame->Commit();
    }
    if (SUCCEEDED(status)) {
        status = encoder->Commit();
    }
    if (FAILED(status)) {
        throw std::runtime_error("diagnostic PNG write failed");
    }
}

[[nodiscard]] std::vector<std::uint8_t> make_difference_image(
    const std::vector<std::uint8_t>& before,
    const std::vector<std::uint8_t>& after) {
    std::vector<std::uint8_t> result(before.size(), 255U);
    for (std::size_t pixel = 0U; pixel < before.size() / 4U; ++pixel) {
        const std::size_t offset = pixel * 4U;
        int maximum = 0;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            maximum = std::max(
                maximum,
                std::abs(static_cast<int>(before[offset + channel]) -
                         static_cast<int>(after[offset + channel])));
        }
        const auto value = static_cast<std::uint8_t>(std::min(255, maximum * 6));
        result[offset] = value;
        result[offset + 1U] = value;
        result[offset + 2U] = value;
    }
    return result;
}

[[nodiscard]] double psnr(const double squared_error, const double count) {
    const double mean = squared_error / count;
    if (!(mean > 0.0)) {
        return 100.0;
    }
    return 10.0 * std::log10(1.0 / mean);
}

[[nodiscard]] ReferenceMetrics evaluate(
    const std::vector<std::uint8_t>& before,
    const std::vector<std::uint8_t>& after,
    const std::vector<std::uint8_t>& reference) {
    if (before.size() != after.size() || before.size() != reference.size() ||
        before.size() % 4U != 0U) {
        throw std::runtime_error("metric buffer sizes differ");
    }

    double baseline_squared_error = 0.0;
    double repaired_squared_error = 0.0;
    std::size_t improved = 0U;
    std::size_t regressed = 0U;
    std::size_t changed = 0U;
    const std::size_t pixel_count = before.size() / 4U;
    for (std::size_t pixel = 0U; pixel < pixel_count; ++pixel) {
        const std::size_t offset = pixel * 4U;
        double baseline_pixel_error = 0.0;
        double repaired_pixel_error = 0.0;
        int maximum_change = 0;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            const double expected =
                static_cast<double>(reference[offset + channel]) / 255.0;
            const double baseline_delta =
                static_cast<double>(before[offset + channel]) / 255.0 - expected;
            const double repaired_delta =
                static_cast<double>(after[offset + channel]) / 255.0 - expected;
            baseline_squared_error += baseline_delta * baseline_delta;
            repaired_squared_error += repaired_delta * repaired_delta;
            baseline_pixel_error += std::abs(baseline_delta);
            repaired_pixel_error += std::abs(repaired_delta);
            maximum_change = std::max(
                maximum_change,
                std::abs(static_cast<int>(before[offset + channel]) -
                         static_cast<int>(after[offset + channel])));
        }
        if (repaired_pixel_error < baseline_pixel_error) {
            ++improved;
        } else if (repaired_pixel_error > baseline_pixel_error) {
            ++regressed;
        }
        if (maximum_change > 2) {
            ++changed;
        }
    }

    const double channel_count = static_cast<double>(pixel_count) * 3.0;
    const double baseline_psnr = psnr(baseline_squared_error, channel_count);
    const double repaired_psnr = psnr(repaired_squared_error, channel_count);
    return {
        repaired_psnr - baseline_psnr,
        static_cast<double>(improved) / static_cast<double>(pixel_count),
        static_cast<double>(regressed) / static_cast<double>(pixel_count),
        changed,
    };
}

[[nodiscard]] std::string json_string(const std::string_view value) {
    std::string result{"\""};
    for (const char character : value) {
        if (character == '\\' || character == '"') {
            result.push_back('\\');
        }
        result.push_back(character);
    }
    result.push_back('"');
    return result;
}

[[nodiscard]] std::vector<std::filesystem::path> corpus_inputs(
    const std::filesystem::path& directory) {
    std::vector<std::filesystem::path> result{};
    for (const auto& entry : std::filesystem::directory_iterator(directory)) {
        if (!entry.is_regular_file() || entry.path().extension() != ".jpg") {
            continue;
        }
        const std::string stem = entry.path().stem().string();
        if (!stem.ends_with("_restored")) {
            result.push_back(entry.path());
        }
    }
    std::sort(result.begin(), result.end());
    return result;
}

}  // namespace

int wmain(const int argument_count, wchar_t* arguments[]) {
    if (argument_count != 3 && argument_count != 4) {
        std::cerr << "usage: negaflow_grain_mend_corpus_tests "
                     "<corpus-directory> <report.json> [regression-artifact-directory]\n";
        return 2;
    }
    try {
        const ComApartment apartment{};
        ComPtr<IWICImagingFactory> factory{};
        HRESULT status = CoCreateInstance(
            CLSID_WICImagingFactory2,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory));
        if (FAILED(status)) {
            status = CoCreateInstance(
                CLSID_WICImagingFactory,
                nullptr,
                CLSCTX_INPROC_SERVER,
                IID_PPV_ARGS(&factory));
        }
        if (FAILED(status)) {
            throw std::runtime_error("WIC factory creation failed");
        }

        const std::filesystem::path corpus = arguments[1];
        const std::vector<std::filesystem::path> inputs = corpus_inputs(corpus);
        if (inputs.empty()) {
            throw std::runtime_error("corpus has no damaged JPEG inputs");
        }
        const std::filesystem::path report_path = arguments[2];
        const std::filesystem::path artifact_directory =
            argument_count == 4 ? std::filesystem::path(arguments[3])
                                : std::filesystem::path{};
        std::filesystem::create_directories(report_path.parent_path());
        std::ofstream report(report_path, std::ios::binary | std::ios::trunc);
        if (!report) {
            throw std::runtime_error("report could not be created");
        }
        report << std::setprecision(17) << "[\n";
        for (std::size_t index = 0U; index < inputs.size(); ++index) {
            const std::filesystem::path& input_path = inputs[index];
            const std::filesystem::path reference_path =
                input_path.parent_path() /
                (input_path.stem().wstring() + L"_restored.jpg");
            DecodedSrgb input = decode_srgb_jpeg(factory.Get(), input_path);
            const DecodedSrgb reference =
                decode_srgb_jpeg(factory.Get(), reference_path);
            if (input.width != reference.width || input.height != reference.height) {
                throw std::runtime_error("reference dimensions differ");
            }

            negaflow::imaging::GrainMendParameters parameters{1.0};
            parameters.dust_sensitivity = 0.0;
            parameters.scratch_sensitivity = 0.1;
            parameters.protect_detail = 0.6;
            parameters.reject_structure_lines = true;
            const auto started = std::chrono::steady_clock::now();
            const auto result = negaflow::imaging::apply_grain_mend(
                std::move(input.linear),
                parameters);
            const auto elapsed = std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - started).count();
            if (result.status != negaflow::imaging::GrainMendStatus::ok) {
                throw std::runtime_error(
                    std::string("GrainMend failed: ") +
                    negaflow::imaging::grain_mend_status_name(result.status));
            }
            const std::vector<std::uint8_t> after = render_srgb8(result.image);
            const ReferenceMetrics metrics = evaluate(
                input.rgba,
                after,
                reference.rgba);
            const std::string name = input_path.stem().string();
            if (metrics.psnr_delta < 0.0 && !artifact_directory.empty()) {
                std::filesystem::create_directories(artifact_directory);
                write_rgba_png(
                    factory.Get(),
                    artifact_directory / (input_path.stem().wstring() + L"-after.png"),
                    after,
                    input.width,
                    input.height);
                write_rgba_png(
                    factory.Get(),
                    artifact_directory / (input_path.stem().wstring() + L"-diff.png"),
                    make_difference_image(input.rgba, after),
                    input.width,
                    input.height);
            }
            std::cout << name << " psnr_delta=" << metrics.psnr_delta
                      << " changed=" << metrics.changed_pixel_count
                      << " elapsed_ms=" << elapsed << '\n';
            report << (index == 0U ? "" : ",\n")
                   << "  {\n"
                   << "    \"imageName\": " << json_string(name) << ",\n"
                   << "    \"width\": " << input.width << ",\n"
                   << "    \"height\": " << input.height << ",\n"
                   << "    \"sensitivity\": 0.69999999999999996,\n"
                   << "    \"changedPixelCount\": "
                   << metrics.changed_pixel_count << ",\n"
                   << "    \"referenceMetrics\": {\n"
                   << "      \"psnrDelta\": " << metrics.psnr_delta << ",\n"
                   << "      \"improvedPixelFraction\": "
                   << metrics.improved_pixel_fraction << ",\n"
                   << "      \"regressedPixelFraction\": "
                   << metrics.regressed_pixel_fraction << "\n"
                   << "    }\n"
                   << "  }";
        }
        report << "\n]\n";
        if (!report) {
            throw std::runtime_error("report write failed");
        }
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "grain_mend_corpus: " << error.what() << '\n';
        return 1;
    }
}
