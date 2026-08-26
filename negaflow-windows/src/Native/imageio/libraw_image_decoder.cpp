#include "negaflow/imageio/libraw_image_decoder.h"

#include <atomic>
#include <cstring>
#include <limits>
#include <mutex>
#include <new>

#include <windows.h>

namespace negaflow::imageio {
namespace {

// LibRaw 의 공개 출력 구조체입니다. `libraw_types.h` 의 정의를 그대로 옮겼습니다.
// 이 구조체는 LibRaw 의 문서화된 출력 계약이라 버전 사이에 바뀌지 않습니다. 반대로
// `libraw_data_t` 는 내부 필드가 계속 바뀌므로 **절대 여기에 옮겨 적지 않습니다** —
// 필요한 값은 전부 setter/getter 함수로만 만집니다.
struct LibRawProcessedImage final {
    int type;
    unsigned short height;
    unsigned short width;
    unsigned short colors;
    unsigned short bits;
    unsigned int data_size;
    unsigned char data[1];
};

constexpr int libraw_image_bitmap = 2;

struct Api final {
    HMODULE module{nullptr};
    void* (__cdecl* init)(unsigned int){nullptr};
    int(__cdecl* open_wfile)(void*, const wchar_t*){nullptr};
    int(__cdecl* unpack)(void*){nullptr};
    int(__cdecl* dcraw_process)(void*){nullptr};
    LibRawProcessedImage*(__cdecl* make_mem_image)(void*, int*){nullptr};
    void(__cdecl* clear_mem)(LibRawProcessedImage*){nullptr};
    void(__cdecl* close)(void*){nullptr};
    void(__cdecl* set_output_bps)(void*, int){nullptr};
    void(__cdecl* set_output_color)(void*, int){nullptr};
    void(__cdecl* set_gamma)(void*, int, float){nullptr};
    void(__cdecl* set_no_auto_bright)(void*, int){nullptr};
    void(__cdecl* set_highlight)(void*, int){nullptr};
    void(__cdecl* set_user_mul)(void*, int, float){nullptr};
    float(__cdecl* get_cam_mul)(void*, int){nullptr};
    // 크기만 알면 되는 자리를 위한 것입니다. `libraw_unpack` 도 `dcraw_process` 도
    // 부르지 않고 헤더만 읽습니다 - 가져오기가 이것 때문에 파일 전체를 현상했습니다.
    int(__cdecl* get_iwidth)(void*){nullptr};
    int(__cdecl* get_iheight)(void*){nullptr};
    // 보간 알고리즘. 프리뷰는 기본 AHD 대신 빠른 것을 씁니다.
    void(__cdecl* set_demosaic)(void*, int){nullptr};
    const char*(__cdecl* version)(){nullptr};
};

template <typename Fn>
[[nodiscard]] bool bind(const HMODULE module, const char* const name, Fn& target) noexcept {
    const FARPROC symbol = ::GetProcAddress(module, name);
    target = reinterpret_cast<Fn>(symbol);
    return target != nullptr;
}

[[nodiscard]] bool load_api(Api& api) noexcept {
    // 앱과 함께 배포한 DLL 만 씁니다. 검색 경로를 실행 파일 디렉터리로 제한해서
    // 작업 디렉터리에 놓인 남의 `libraw.dll` 을 집지 않게 합니다.
    api.module = ::LoadLibraryExW(
        L"libraw.dll", nullptr, LOAD_LIBRARY_SEARCH_APPLICATION_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (api.module == nullptr) {
        return false;
    }
    const bool bound =
        bind(api.module, "libraw_init", api.init) &&
        bind(api.module, "libraw_open_wfile", api.open_wfile) &&
        bind(api.module, "libraw_unpack", api.unpack) &&
        bind(api.module, "libraw_dcraw_process", api.dcraw_process) &&
        bind(api.module, "libraw_dcraw_make_mem_image", api.make_mem_image) &&
        bind(api.module, "libraw_dcraw_clear_mem", api.clear_mem) &&
        bind(api.module, "libraw_close", api.close) &&
        bind(api.module, "libraw_set_output_bps", api.set_output_bps) &&
        bind(api.module, "libraw_set_output_color", api.set_output_color) &&
        bind(api.module, "libraw_set_gamma", api.set_gamma) &&
        bind(api.module, "libraw_set_no_auto_bright", api.set_no_auto_bright) &&
        bind(api.module, "libraw_set_highlight", api.set_highlight) &&
        bind(api.module, "libraw_set_user_mul", api.set_user_mul) &&
        bind(api.module, "libraw_get_cam_mul", api.get_cam_mul) &&
        bind(api.module, "libraw_get_iwidth", api.get_iwidth) &&
        bind(api.module, "libraw_get_iheight", api.get_iheight) &&
        bind(api.module, "libraw_set_demosaic", api.set_demosaic) &&
        bind(api.module, "libraw_version", api.version);
    if (!bound) {
        // 심볼이 하나라도 없으면 그 DLL 은 우리가 아는 LibRaw 가 아닙니다. 반쯤 쓰지 않고
        // 통째로 포기하고 WIC 실패 사유를 그대로 사용자에게 돌려줍니다.
        ::FreeLibrary(api.module);
        api = Api{};
        return false;
    }
    return true;
}

const Api& api() noexcept {
    static const Api loaded = [] {
        Api candidate{};
        if (!load_api(candidate)) {
            return Api{};
        }
        return candidate;
    }();
    return loaded;
}

/// 열린 LibRaw 처리기를 반드시 닫습니다. 중간에 어느 단계가 실패해도 새는 곳이 없어야
/// 합니다 — 가져오기는 폴더 단위로 수백 번 돌 수 있습니다.
class Handle final {
public:
    explicit Handle(const Api& functions) noexcept
        : functions_(functions), handle_(functions.init != nullptr ? functions.init(0U) : nullptr) {}

    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    Handle(Handle&&) = delete;
    Handle& operator=(Handle&&) = delete;

    ~Handle() {
        if (handle_ != nullptr) {
            functions_.close(handle_);
        }
    }

    [[nodiscard]] void* get() const noexcept { return handle_; }

private:
    const Api& functions_;
    void* handle_{nullptr};
};

/// `libraw_dcraw_make_mem_image` 가 준 버퍼를 반드시 돌려줍니다.
class MemImage final {
public:
    MemImage(const Api& functions, LibRawProcessedImage* image) noexcept
        : functions_(functions), image_(image) {}

    MemImage(const MemImage&) = delete;
    MemImage& operator=(const MemImage&) = delete;
    MemImage(MemImage&&) = delete;
    MemImage& operator=(MemImage&&) = delete;

    ~MemImage() {
        if (image_ != nullptr) {
            functions_.clear_mem(image_);
        }
    }

    [[nodiscard]] const LibRawProcessedImage* get() const noexcept { return image_; }

private:
    const Api& functions_;
    LibRawProcessedImage* image_{nullptr};
};

/// WIC RAW 경로와 같은 그림을 내도록 현상 매개변수를 맞춥니다.
///
/// WIC 는 `WICAsShotParameterSet` + `WICRawRenderModeBestQuality` 로 현상하고 결과를
/// sRGB 색공간으로 내놓습니다. LibRaw 도 같게 맞춥니다.
void configure_as_shot(const Api& functions, void* const handle) noexcept {
    functions.set_output_bps(handle, 16);
    // 1 = sRGB primaries. 다운스트림이 `srgb_encoded` 로 해석하므로 전달 함수도 sRGB 여야
    // 합니다. LibRaw 기본값 0.45/4.5 는 BT.709 라 그대로 두면 밝기가 어긋납니다.
    functions.set_output_color(handle, 1);
    functions.set_gamma(handle, 0, 1.0F / 2.4F);
    functions.set_gamma(handle, 1, 12.92F);
    // 자동 밝기 보정은 사진마다 다른 배율을 곱합니다. 같은 롤의 컷들이 서로 다른 밝기로
    // 들어오면 필름 베이스(Dmin)를 한 번 잡아 롤 전체에 쓰는 작업 방식이 깨집니다.
    functions.set_no_auto_bright(handle, 1);
    // 0 = 하이라이트를 clip. 복원 모드는 없던 화소를 만들어 내므로 스캔 원본 계약에
    // 맞지 않습니다.
    functions.set_highlight(handle, 0);

    // 촬영 당시 화이트밸런스입니다. C API 에 `use_camera_wb` setter 가 없으므로 카메라가
    // 기록한 배율을 그대로 user_mul 로 넘깁니다 — 같은 결과입니다. 값이 없는 파일이면
    // 건드리지 않고 LibRaw 기본 판단에 맡깁니다.
    const float first = functions.get_cam_mul(handle, 0);
    if (first > 0.0F) {
        for (int index = 0; index < 4; ++index) {
            functions.set_user_mul(handle, index, functions.get_cam_mul(handle, index));
        }
    }
}

}  // namespace

bool libraw_decoder_available() noexcept {
    return api().module != nullptr;
}

const char* libraw_decoder_version() noexcept {
    const Api& functions = api();
    return functions.module != nullptr ? functions.version() : "";
}

const char* libraw_decode_status_name(const LibRawDecodeStatus status) noexcept {
    switch (status) {
        case LibRawDecodeStatus::ok: return "ok";
        case LibRawDecodeStatus::unavailable: return "libraw_unavailable";
        case LibRawDecodeStatus::invalid_argument: return "invalid_argument";
        case LibRawDecodeStatus::open_failed: return "libraw_open_failed";
        case LibRawDecodeStatus::unpack_failed: return "libraw_unpack_failed";
        case LibRawDecodeStatus::process_failed: return "libraw_process_failed";
        case LibRawDecodeStatus::unsupported_output: return "libraw_unsupported_output";
        case LibRawDecodeStatus::memory_limit_exceeded: return "decoded_pixel_memory_limit_exceeded";
        case LibRawDecodeStatus::allocation_failed: return "decoded_pixel_allocation_failed";
        case LibRawDecodeStatus::cancelled: return "cancelled";
    }
    return "unknown_libraw_decode_status";
}

LibRawMetadataResult probe_raw_metadata_with_libraw(const std::filesystem::path& path) noexcept {
    LibRawMetadataResult result{};
    const Api& functions = api();
    if (functions.module == nullptr) {
        result.status = LibRawDecodeStatus::unavailable;
        return result;
    }
    if (path.empty()) {
        result.status = LibRawDecodeStatus::invalid_argument;
        return result;
    }
    try {
        const Handle handle{functions};
        if (handle.get() == nullptr) {
            result.status = LibRawDecodeStatus::allocation_failed;
            return result;
        }
        // **여기서 멈춥니다.** `libraw_open_wfile` 은 헤더만 읽고, 그것만으로 크기가 정해집니다.
        // `libraw_unpack`/`libraw_dcraw_process` 를 부르면 파일 전체를 현상하게 되고, 크기만
        // 필요한 자리에서 그것은 파일 하나에 수백 MB 와 수 초입니다 - 실측으로 7168x5120 한 장이
        // 294 MB 였고 폴더 가져오기가 그 때문에 무너졌습니다.
        const int opened = functions.open_wfile(handle.get(), path.c_str());
        if (opened != 0) {
            result.status = LibRawDecodeStatus::open_failed;
            result.native_error_code = opened;
            return result;
        }
        const int width = functions.get_iwidth(handle.get());
        const int height = functions.get_iheight(handle.get());
        if (width <= 0 || height <= 0) {
            result.status = LibRawDecodeStatus::unsupported_output;
            return result;
        }
        result.status = LibRawDecodeStatus::ok;
        result.pixel_width = static_cast<std::uint32_t>(width);
        result.pixel_height = static_cast<std::uint32_t>(height);
        return result;
    } catch (...) {
        result.status = LibRawDecodeStatus::allocation_failed;
        return result;
    }
}

LibRawDecodeResult decode_raw_with_libraw(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits,
    const std::stop_token stop_token,
    const WicStandardImageDecodeControl& control) noexcept {
    LibRawDecodeResult result{};
    const Api& functions = api();
    if (functions.module == nullptr) {
        result.status = LibRawDecodeStatus::unavailable;
        return result;
    }
    if (path.empty()) {
        result.status = LibRawDecodeStatus::invalid_argument;
        return result;
    }

    try {
        const Handle handle{functions};
        if (handle.get() == nullptr) {
            result.status = LibRawDecodeStatus::allocation_failed;
            return result;
        }

        result.native_error_code = functions.open_wfile(handle.get(), path.c_str());
        if (result.native_error_code != 0) {
            result.status = LibRawDecodeStatus::open_failed;
            return result;
        }
        if (stop_token.stop_requested()) {
            result.status = LibRawDecodeStatus::cancelled;
            return result;
        }

        configure_as_shot(functions, handle.get());
        // 프리뷰는 보간을 빠른 것으로 바꿉니다. LibRaw 기본은 AHD(3) 이고, 0 은 선형
        // 보간입니다 - 프리뷰 프록시는 어차피 줄여서 보는 그림이라 이 차이가 화면에서
        // 드러나지 않고, 정착본은 기본 보간을 그대로 씁니다.
        if (control.prefer_speed && functions.set_demosaic != nullptr) {
            functions.set_demosaic(handle.get(), 0);
        }

        result.native_error_code = functions.unpack(handle.get());
        if (result.native_error_code != 0) {
            result.status = LibRawDecodeStatus::unpack_failed;
            return result;
        }
        if (stop_token.stop_requested()) {
            result.status = LibRawDecodeStatus::cancelled;
            return result;
        }

        result.native_error_code = functions.dcraw_process(handle.get());
        if (result.native_error_code != 0) {
            result.status = LibRawDecodeStatus::process_failed;
            return result;
        }

        int make_error = 0;
        const MemImage image{functions, functions.make_mem_image(handle.get(), &make_error)};
        if (image.get() == nullptr) {
            result.native_error_code = make_error;
            result.status = LibRawDecodeStatus::process_failed;
            return result;
        }

        const LibRawProcessedImage& produced = *image.get();
        // 16-bit·3채널 비트맵만 받습니다. JPEG 미리보기(type 1)나 8-bit 결과가 오면 위의
        // 설정이 먹지 않은 것이므로 조용히 품질을 낮추지 않고 실패로 끝냅니다.
        if (produced.type != libraw_image_bitmap || produced.bits != 16U ||
            produced.colors != 3U || produced.width == 0U || produced.height == 0U) {
            result.status = LibRawDecodeStatus::unsupported_output;
            return result;
        }

        const std::uint64_t width = produced.width;
        const std::uint64_t height = produced.height;
        const std::uint64_t source_samples = width * height * 3ULL;
        if (produced.data_size != source_samples * sizeof(std::uint16_t)) {
            result.status = LibRawDecodeStatus::unsupported_output;
            return result;
        }

        // 결과 계약은 WIC 경로와 같은 `rgba16` 입니다 — 화소당 8바이트.
        const std::uint64_t stride = width * 8ULL;
        const std::uint64_t bytes = stride * height;
        if (stride > std::numeric_limits<std::uint32_t>::max() ||
            bytes > limits.max_decoded_pixel_bytes ||
            bytes / sizeof(std::uint16_t) > std::numeric_limits<std::size_t>::max()) {
            result.status = LibRawDecodeStatus::memory_limit_exceeded;
            return result;
        }

        result.image.width = static_cast<std::uint32_t>(width);
        result.image.height = static_cast<std::uint32_t>(height);
        result.image.stride_bytes = static_cast<std::uint32_t>(stride);
        result.image.layout = DecodedPixelLayout::rgba16;
        result.image.alpha_mode = AlphaMode::unassociated;
        result.image.untagged_rgb_transfer = UntaggedRgbTransfer::srgb_encoded;
        result.image.samples.resize(static_cast<std::size_t>(bytes / sizeof(std::uint16_t)));

        const auto* const source = reinterpret_cast<const std::uint16_t*>(produced.data);
        std::uint16_t* const destination = result.image.samples.data();
        for (std::uint64_t index = 0U; index < width * height; ++index) {
            const std::size_t in = static_cast<std::size_t>(index) * 3U;
            const std::size_t out = static_cast<std::size_t>(index) * 4U;
            destination[out] = source[in];
            destination[out + 1U] = source[in + 1U];
            destination[out + 2U] = source[in + 2U];
            destination[out + 3U] = 65'535U;
        }

        if (stop_token.stop_requested()) {
            std::vector<std::uint16_t>{}.swap(result.image.samples);
            result.status = LibRawDecodeStatus::cancelled;
            return result;
        }

        result.status = LibRawDecodeStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = LibRawDecodeStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = LibRawDecodeStatus::invalid_argument;
        return result;
    }
}

}  // namespace negaflow::imageio
