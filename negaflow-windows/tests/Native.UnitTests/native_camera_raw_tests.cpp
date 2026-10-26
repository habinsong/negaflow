#include "negaflow/imageio/libraw_image_decoder.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/working_image_resample.h"

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_negative_invert.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/pipeline/develop_export.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <iostream>

namespace {
int failures = 0;
void expect(const bool value, const char* message) {
    if (!value) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}
void test_order_and_resample() {
    using namespace negaflow;
    const imageio::CameraToWorkingMatrix matrix{1.5F,-0.3F,-0.2F,-0.1F,1.3F,-0.2F,-0.05F,-0.2F,1.25F};
    imaging::WorkingImage raw{};
    raw.width = 8; raw.height = 4; raw.stride_pixels = 8;
    raw.camera_to_working = matrix;
    const float base[3]{0.80F,0.55F,0.35F};
    const float scene[3]{0.20F,0.24F,0.30F};
    const auto response = core::color_negative_print_response();
    float expected_native[3]{};
    for (unsigned c=0;c<3;++c) {
        const float d=(0.60F+0.62F*std::log10(scene[c]/0.18F))/response.normal_range;
        expected_native[c]=std::pow(10.0F,response.y_ceiling-response.amplitude*
            std::exp(-std::pow(response.rate*d,response.shape)));
    }

    core::Rgba32F pixel{};
    pixel.red = base[0] * std::pow(10.0F, -(0.60F + 0.62F * std::log10(scene[0] / 0.18F)));
    pixel.green = base[1] * std::pow(10.0F, -(0.60F + 0.62F * std::log10(scene[1] / 0.18F)));
    pixel.blue = base[2] * std::pow(10.0F, -(0.60F + 0.62F * std::log10(scene[2] / 0.18F)));
    pixel.alpha = 1;
    raw.pixels.assign(32, pixel);
    auto proxy = imaging::resample_working_image_lanczos3(raw, 4, 2);
    expect(proxy.image.camera_to_working == raw.camera_to_working, "proxy retains native camera basis");
    imaging::ManualNegativeDevelopParameters params{{base[0],base[1],base[2]}};
    params.linear_output = false;
    auto result = imaging::develop_manual_negative(std::move(proxy.image), params);
    expect(result.status == imaging::ManualNegativeDevelopStatus::ok, "native negative inversion succeeds");
    expect(imaging::apply_deferred_camera_transform(result.image), "post-inversion camera matrix succeeds");
    const auto positive = result.image.pixels.front();
    const float expected[3]{1.5F*expected_native[0]-0.3F*expected_native[1]-0.2F*expected_native[2],
        -0.1F*expected_native[0]+1.3F*expected_native[1]-0.2F*expected_native[2],
        -0.05F*expected_native[0]-0.2F*expected_native[1]+1.25F*expected_native[2]};
    expect(std::abs(positive.red - expected[0]) < 1e-5F && std::abs(positive.green - expected[1]) < 1e-5F &&
           std::abs(positive.blue - expected[2]) < 1e-5F, "matrix follows inverse film, not negative transmittance");
    expect(!result.image.camera_to_working, "camera transform is consumed");
    expect(imaging::apply_deferred_camera_transform(result.image) && result.image.pixels.front().red == positive.red,
           "camera transform is not applied twice");
}
void compare_native_gpu(const negaflow::imaging::WorkingImage& raw) {
    using namespace negaflow;
    imaging::ManualNegativeDevelopParameters params{{0.80F,0.55F,0.35F}};
    params.linear_output = false;
    auto cpu = imaging::develop_manual_negative(raw, params);
    const auto native_positive = cpu.image;
    expect(cpu.status == imaging::ManualNegativeDevelopStatus::ok &&
        imaging::apply_deferred_camera_transform(cpu.image), "native RAW CPU reference");
    for (const auto preference : {gpu::GpuDevicePreference::hardware_only, gpu::GpuDevicePreference::warp_only}) {
        const auto device = gpu::GpuDevice::create(preference);
        if (!device.is_usable()) {
            expect(preference != gpu::GpuDevicePreference::warp_only, "WARP must execute the native RAW regression");
            continue;
        }
        gpu::GpuNegativeInvert kernel{};
        gpu::GpuWorkingImage input{}, output{};
        expect(gpu::GpuNegativeInvert::create(device,kernel) == gpu::GpuKernelStatus::ok &&
            gpu::GpuWorkingImage::upload(device,raw.pixels.data(),raw.width,raw.height,raw.stride_pixels,input) == gpu::GpuImageStatus::ok &&
            gpu::GpuWorkingImage::create(device,raw.width,raw.height,output) == gpu::GpuImageStatus::ok, "native RAW D3D setup");
        const auto response = core::color_negative_print_response();
        gpu::GpuNegativeInvertParameters parameters{};
        for (unsigned c=0;c<3;++c) { parameters.dmin[c]=cpu.info.applied_dmin[c]; parameters.dmax_normalized[c]=cpu.info.dmax_normalized[c]; }
        parameters.linear_output=false;
        parameters.response_y_ceiling=response.y_ceiling; parameters.response_amplitude=response.amplitude;
        parameters.response_rate=response.rate; parameters.response_shape=response.shape; parameters.normal_range=response.normal_range;
        expect(kernel.dispatch(device,input,output,parameters) == gpu::GpuKernelStatus::ok, "native RAW D3D inverse");
        auto actual = raw;
        expect(output.download(device,actual.pixels.data(),actual.stride_pixels) == gpu::GpuImageStatus::ok &&
            imaging::apply_deferred_camera_transform(actual), "native RAW D3D readback then matrix");
        float worst=0;
        for (std::size_t p=0;p<actual.pixels.size();++p) {
            const auto a=actual.pixels[p], b=cpu.image.pixels[p], n=native_positive.pixels[p];
            const float av[3]{a.red,a.green,a.blue}, bv[3]{b.red,b.green,b.blue}, nv[3]{n.red,n.green,n.blue};
            const auto& m=*raw.camera_to_working;
            for (unsigned row=0;row<3;++row) {
                // Propagate the established 1e-5 native-kernel budget through |M|.
                // Camera matrices can cancel large channel terms near zero output.
                float scale=0;
                for (unsigned col=0;col<3;++col) { scale+=std::abs(m[row*3+col])*std::max(1.0F,std::abs(nv[col])); }
                worst=std::max(worst,std::abs(av[row]-bv[row])/scale);
            }
        }
        std::cout << "[native-raw-gpu] " << device.capability().adapter.description.data() << " max-matrix-scaled-delta=" << worst << '\n';
        expect(worst < 1e-5F, "actual camera RAW CPU/D3D parity within propagated kernel tolerance");

    }
}
void test_pipeline(const std::filesystem::path& source) {
    using namespace negaflow;
    pipeline::DevelopExportRequest request{};
    request.source=source;
    request.negative.dmin={0.80F,0.55F,0.35F};
    request.auto_balance = true;
    std::vector<std::uint8_t> first(320U*320U*4U), second(first.size());
    const auto preview=pipeline::develop_preview(request,320,320,first.data(),first.size());
    const auto cached=pipeline::develop_preview(request,320,320,second.data(),second.size());
    expect(preview.succeeded && cached.succeeded, "actual RAW develop preview and cached preview");
    expect(first==second, "cached native input does not apply camera matrix twice");
    request.destination=std::filesystem::temp_directory_path() /
        ("negaflow-native-raw-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count())+".png");
    const auto exported=pipeline::develop_and_export(request);
    expect(exported.succeeded && std::filesystem::exists(request.destination) && std::filesystem::file_size(request.destination)>1000U, "actual RAW full-resolution export");
    if (!exported.succeeded) { std::cerr << "RAW export failure: " << exported.failure_name << '\n'; }
    std::error_code ignored; std::filesystem::remove(request.destination,ignored);
}
void test_real_raw(const std::filesystem::path& source) {
    using namespace negaflow;
    expect(imageio::libraw_decoder_available(), "LibRaw runtime is required for actual RAW regression");
    imageio::WicStandardImageDecodeControl control{};
    control.scene_linear_raw = true;
    control.max_output_width = 320; control.max_output_height = 320;
    const auto decoded = imageio::decode_raw_with_libraw(source, {}, {}, control);
    expect(decoded.status == imageio::LibRawDecodeStatus::ok, "CC0 camera RAW decodes as camera RGB");
    if (decoded.status != imageio::LibRawDecodeStatus::ok) {
        std::cerr << imageio::libraw_decode_status_name(decoded.status) << '\n'; return;
    }
    expect(decoded.image.camera_to_working.has_value(), "camera RAW has a deferred color matrix");
    const auto working = imaging::convert_scanner_to_working(decoded.image);
    expect(working.status == imaging::ScannerToWorkingStatus::ok &&
        working.image.camera_to_working == decoded.image.camera_to_working, "conversion retains native basis without early matrix");
    if (working.status == imaging::ScannerToWorkingStatus::ok) { compare_native_gpu(working.image); }
    test_pipeline(source);
    std::cout << "[raw] decoder=" << imageio::libraw_decoder_version() << " camera matrix=";
    for (const float coefficient : *decoded.image.camera_to_working) { std::cout << coefficient << ' '; }
    std::cout << '\n';
}
}
int main(const int argc, char** argv) {
    test_order_and_resample();
    if (argc != 2) { std::cerr << "RAW fixture path required\n"; return 1; }
    test_real_raw(std::filesystem::path(argv[1]));
    if (failures == 0) { std::cout << "native camera RAW checks passed\n"; }
    return failures == 0 ? 0 : 1;
}
