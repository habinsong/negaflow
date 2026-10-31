#include "negaflow/imageio/libraw_image_decoder.h"

#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/imageio/libraw_preview_reduce.h"
#include "negaflow/imageio/linear_dng_mapped.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <limits>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>
#include <new>

#include <windows.h>

namespace negaflow::imageio {
namespace {

// LibRaw (https://www.libraw.org, CDDL-1.0 선택, LibRaw LLC) C ABI 호환용 공개 출력 구조체 선언입니다.
// `libraw.dll` 은 런타임에 `LoadLibraryExW`/`GetProcAddress` 로 동적 로드되며, 대응 소스와
// 라이선스 고지는 `THIRD-PARTY-NOTICES.md` 및 배포본의 `licenses/libraw/` 에 함께 수록됩니다.
// 이 구조체는 LibRaw 의 문서화된 출력 계약(`libraw_types.h`)이라 버전 사이에 바뀌지 않습니다. 반대로
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

// `libraw_imgother_t` 의 **앞 네 개**입니다. 뒤쪽(타임스탬프·GPS·설명 문자열)은 판마다
// 달라지므로 옮기지 않습니다 — 이 네 float 은 LibRaw 0.14 이후 구조체 맨 앞에 같은 차례로
// 있고, 우리가 함께 배포하는 판은 `build-libraw/` 에 고정돼 있습니다. 뒤를 읽지 않으므로
// 뒤가 바뀌어도 이 코드는 영향을 받지 않습니다.
struct LibRawImgOtherPrefix final {
    float iso_speed;
    float shutter;
    float aperture;
    float focal_len;
};

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
    float(__cdecl* get_rgb_cam)(void*, int, int){nullptr};
    void(__cdecl* set_adjust_maximum_thr)(void*, float){nullptr};
    // 크기만 알면 되는 자리를 위한 것입니다. `libraw_unpack` 도 `dcraw_process` 도
    // 부르지 않고 헤더만 읽습니다 - 가져오기가 이것 때문에 파일 전체를 현상했습니다.
    int(__cdecl* get_iwidth)(void*){nullptr};
    int(__cdecl* get_iheight)(void*){nullptr};
    // 보간 알고리즘. 프리뷰는 기본 AHD 대신 빠른 것을 씁니다.
    void(__cdecl* set_demosaic)(void*, int){nullptr};
    const char*(__cdecl* version)(){nullptr};
    // **선택 심볼**입니다. 아래 `bound` 사슬에 넣지 않습니다 — 이것이 없다고 RAW 현상까지
    // 포기하면 옛 `libraw.dll` 하나 때문에 사진이 아예 안 열립니다. 없으면 촬영 기록만
    // 비웁니다.
    const LibRawImgOtherPrefix*(__cdecl* get_imgother)(void*){nullptr};
    // **선택 심볼** — macOS 와 같은 프리뷰 브리지(`scripts/libraw/native-preview-bridge.cpp`)와
    // 그것을 쓰는 데 필요한 LibRaw 함수입니다. 하나라도 없으면 임시 첫 화면 없이 원본 크기로만
    // 처리합니다(`libraw_supports_provisional_preview`).
    int(__cdecl* preview_mode)(void*, int){nullptr};
    void(__cdecl* cancel)(void*){nullptr};
    // Windows 전용 브리지 — 헤더만으로 첫 화면 가능 여부, 항등 선형 DNG 를 처리 없이 바로 줄이기.
    int(__cdecl* first_preview_possible)(void*, int){nullptr};
    int(__cdecl* linear_header)(void*, int*, int*, int*){nullptr};
    int(__cdecl* linear_size)(void*, int*, int*){nullptr};
    LibRawProcessedImage*(__cdecl* make_linear_preview)(void*, int, int){nullptr};
    void(__cdecl* free_image)(void*){nullptr};
    void(__cdecl* recycle_datastream)(void*){nullptr};
    // LibRaw 의 진행 콜백(`libraw_set_progress_handler`). 0 이 아니면 그 자리에서 처리를 멈춥니다.
    void(__cdecl* set_progress_handler)(void*, int(__cdecl*)(void*, int, int, int), void*){nullptr};
    int(__cdecl* get_raw_width)(void*){nullptr};
    int(__cdecl* get_raw_height)(void*){nullptr};
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
    // 선택 심볼입니다. 실패해도 `bound` 를 깎지 않습니다.
    (void)bind(api.module, "libraw_get_imgother", api.get_imgother);
    (void)bind(api.module, "libraw_get_rgb_cam", api.get_rgb_cam);
    (void)bind(api.module, "libraw_set_adjust_maximum_thr", api.set_adjust_maximum_thr);
    (void)bind(api.module, "negaflow_libraw_preview_mode", api.preview_mode);
    (void)bind(api.module, "negaflow_libraw_cancel", api.cancel);
    (void)bind(api.module, "negaflow_libraw_first_preview_possible", api.first_preview_possible);
    (void)bind(api.module, "negaflow_libraw_linear_header", api.linear_header);
    (void)bind(api.module, "negaflow_libraw_linear_size", api.linear_size);
    (void)bind(api.module, "negaflow_libraw_make_linear_preview", api.make_linear_preview);
    (void)bind(api.module, "libraw_free_image", api.free_image);
    (void)bind(api.module, "libraw_recycle_datastream", api.recycle_datastream);
    (void)bind(api.module, "libraw_set_progress_handler", api.set_progress_handler);
    (void)bind(api.module, "libraw_get_raw_width", api.get_raw_width);
    (void)bind(api.module, "libraw_get_raw_height", api.get_raw_height);
    // 브리지의 처리기는 LibRaw 의 화소 고리 셋을 여러 코어로 돕니다. 결과는 원래 LibRaw 와 바이트
    // 단위로 같고, 처리 시간이 CR2 874→641 ms, ARW 1,189→875 ms, 디지털 프리뷰 489~656→191~233 ms
    // 로 줄었습니다(이 기계 실측). 없으면 원래 `libraw_init` 그대로입니다.
    void* (__cdecl* bridge_init)(unsigned int){nullptr};
    if (bound && bind(api.module, "negaflow_libraw_init", bridge_init)) {
        api.init = bridge_init;
    }
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

    /// 남겨 두었던 unpack 핸들을 넘겨받습니다. 이제부터 닫는 책임은 이 객체에 있습니다.
    Handle(const Api& functions, void* const adopted) noexcept
        : functions_(functions), handle_(adopted) {}

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

    /// 닫는 책임을 넘깁니다. 정착 디코드가 이어 쓰도록 남겨 둘 때만 씁니다.
    [[nodiscard]] void* release() noexcept {
        void* const handle = handle_;
        handle_ = nullptr;
        return handle;
    }

private:
    const Api& functions_;
    void* handle_{nullptr};
};

// ── 임시 첫 화면 뒤에 남겨 두는 unpack 결과 ─────────────────────────────────────
//
// macOS 는 한 작업 안에서 같은 핸들로 반 크기 → 원본을 잇달아 처리합니다
// (`produceProgressivePreview`). Windows 는 인터랙티브와 정착이 **따로 부르는 두 현상**이라,
// 그 사이에 핸들을 여기 한 장 남겨 둡니다. 정착 디코드가 이어 쓰면 unpack 을 다시 하지
// 않습니다 — 실측(이 기계): CR2·NEF 의 unpack 438 ms 가 통째로 빠지고, 결과 화소는 처음부터
// 푼 것과 비트 단위로 같았습니다(RAF·CR2·NEF·ARW·CR3 다섯 장).
//
// **한 장만** 남깁니다. 새 임시 첫 화면이 오거나, 다른 파일의 정착 디코드가 시작되거나,
// 프레임 캐시 예산을 넘으면 바로 놓습니다. 남기는 동안 파일은 닫습니다
// (`libraw_recycle_datastream`) — 사용자가 그 파일을 옮기거나 지울 수 있어야 합니다.
struct RetainedUnpack final {
    void* handle{nullptr};
    std::filesystem::path path{};
    ImageFileObservation observation{};
    // 음화(선형 카메라 RGB)와 양화(as-shot sRGB)는 LibRaw 설정이 다릅니다. 한쪽이 남긴 핸들을
    // 다른 쪽이 이어 쓰면 화소가 틀립니다.
    bool scene_linear{false};
    std::uint64_t bytes{0U};
};

// 프로세스가 끝날 때 소멸자가 LibRaw 를 부르지 않도록 힙에 두고 풀지 않습니다. 남은 핸들은
// 프로세스 종료가 회수합니다.
std::mutex& retained_mutex() noexcept {
    static std::mutex* const mutex = new std::mutex{};
    return *mutex;
}

RetainedUnpack& retained_unpack() noexcept {
    static RetainedUnpack* const retained = new RetainedUnpack{};
    return *retained;
}

std::atomic<std::uint64_t> g_retained_bytes{0U};

struct FittedPreview final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

/// `reduce_libraw_rgb16_to_preview` 의 상자 맞춤과 같은 정수 계산입니다. 줄이는 길이 바뀌어도
/// 프리뷰 크기는 같아야 뒤 단계(베이스 측정 격자, 캐시)가 같은 화상을 봅니다.
[[nodiscard]] FittedPreview fit_libraw_preview(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t maximum_width,
    const std::uint32_t maximum_height) noexcept {
    FittedPreview fitted{width, height};
    if (fitted.width > maximum_width) {
        fitted.width = maximum_width;
        fitted.height = std::max(1U, static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(height) * fitted.width) / width));
    }
    if (fitted.height > maximum_height) {
        fitted.height = maximum_height;
        fitted.width = std::max(1U, static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(width) * fitted.height) / height));
    }
    return fitted;
}

/// 한 번의 LibRaw 디코드가 단계마다 쓴 시간을 `decode-trace.txt` 에 한 줄로 남깁니다(켜져 있을
/// 때만). 어느 길(이어 쓰기·임시 첫 화면·선형·원본)로 갔는지도 함께 적습니다.
class DecodeTraceTimer final {
public:
    DecodeTraceTimer(const std::filesystem::path& path, const LibRawDecodeResult& result) noexcept
        : path_(path), result_(result) {}
    DecodeTraceTimer(const DecodeTraceTimer&) = delete;
    DecodeTraceTimer& operator=(const DecodeTraceTimer&) = delete;

    void mark(double& slot) noexcept {
        const auto now = std::chrono::steady_clock::now();
        slot = std::chrono::duration<double, std::milli>(now - last_).count();
        last_ = now;
    }

    double open_ms{-1.0};
    double unpack_ms{-1.0};
    double process_ms{-1.0};
    double output_ms{-1.0};
    const char* route{"full"};

    ~DecodeTraceTimer() {
        if (!decode_trace_enabled()) {
            return;
        }
        try {
            const std::wstring name = path_.filename().wstring();
            char narrow[260]{};
            ::WideCharToMultiByte(CP_UTF8, 0, name.c_str(), -1, narrow, sizeof(narrow) - 1, nullptr, nullptr);
            const double total =
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start_).count();
            char line[512]{};
            std::snprintf(line, sizeof(line),
                "libraw %s route=%s status=%s open=%.0f unpack=%.0f process=%.0f output=%.0f total=%.0f ms",
                narrow, route, libraw_decode_status_name(result_.status), open_ms, unpack_ms, process_ms,
                output_ms, total);
            decode_trace_write(line);
        } catch (...) {
        }
    }

private:
    const std::filesystem::path& path_;
    const LibRawDecodeResult& result_;
    std::chrono::steady_clock::time_point start_{std::chrono::steady_clock::now()};
    std::chrono::steady_clock::time_point last_{start_};
};

void close_handle(void* const handle) noexcept {
    if (handle != nullptr) {
        api().close(handle);
    }
}

/// 같은 파일·같은 관측이면 넘겨줍니다. 다른 파일의 것은 버려진 것이므로 놓습니다.
[[nodiscard]] void* take_retained(
    const std::filesystem::path& path,
    const ImageFileObservation& observation,
    const bool scene_linear) noexcept {
    void* taken = nullptr;
    void* abandoned = nullptr;
    {
        const std::lock_guard<std::mutex> guard{retained_mutex()};
        RetainedUnpack& retained = retained_unpack();
        if (retained.handle == nullptr) {
            return nullptr;
        }
        bool same_path = false;
        try {
            same_path = retained.path == path;
        } catch (...) {
        }
        if (same_path && retained.scene_linear == scene_linear &&
            same_image_file_observation(retained.observation, observation)) {
            taken = retained.handle;
        } else {
            abandoned = retained.handle;
        }
        retained.handle = nullptr;
        retained.bytes = 0U;
        g_retained_bytes.store(0U, std::memory_order_relaxed);
    }
    close_handle(abandoned);
    return taken;
}

void store_retained(
    void* const handle,
    const std::filesystem::path& path,
    const ImageFileObservation& observation,
    const bool scene_linear,
    const std::uint64_t bytes) noexcept {
    void* replaced = handle;
    try {
        const std::lock_guard<std::mutex> guard{retained_mutex()};
        RetainedUnpack& retained = retained_unpack();
        std::filesystem::path stored_path = path;
        replaced = retained.handle;
        retained.handle = handle;
        retained.path = std::move(stored_path);
        retained.observation = observation;
        retained.scene_linear = scene_linear;
        retained.bytes = bytes;
        g_retained_bytes.store(bytes, std::memory_order_relaxed);
    } catch (...) {
        // 경로를 담지 못하면 남기지 않습니다 — 넘겨받은 핸들을 바로 닫습니다.
    }
    close_handle(replaced);
}

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
    // 1 = sRGB primaries. 사진 렌더링의 기본 전달 함수는 sRGB입니다.
    // 필름 scene-linear 디코드는 호출부에서 gamma를 (1, 1)로 바꾸고 선형 태그를 기록합니다.
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

bool libraw_supports_provisional_preview() noexcept {
    const Api& functions = api();
    return functions.module != nullptr && functions.preview_mode != nullptr &&
        functions.free_image != nullptr && functions.recycle_datastream != nullptr &&
        functions.get_raw_width != nullptr && functions.get_raw_height != nullptr;
}

namespace {

[[nodiscard]] std::wstring decode_trace_folder() {
    wchar_t* folder = nullptr;
    std::size_t length = 0U;
    if (_wdupenv_s(&folder, &length, L"LOCALAPPDATA") != 0 || folder == nullptr) {
        return {};
    }
    std::wstring path{folder};
    std::free(folder);
    return path + L"\\Negaflow\\Logs";
}

}  // namespace

bool decode_trace_enabled() noexcept {
    // 관리 쪽 `PreviewTrace` 와 같이 처음 한 번만 봅니다 — 화소 경로에서 매번 파일 시스템을
    // 묻지 않습니다. 켜고 끄는 것은 앱을 다시 띄울 때 반영됩니다.
    // 표시 파일은 로그 폴더나 실행 파일 폴더에 둡니다(관리 쪽 `PreviewTrace` 와 같습니다 — 개발자
    // 모드가 꺼진 채 앱이 뜨면 로그 폴더의 표시는 지워지므로, 설치 폴더에 둔 표시가 측정용입니다).
    static const bool enabled = [] {
        try {
            const std::wstring folder = decode_trace_folder();
            if (!folder.empty() &&
                ::GetFileAttributesW((folder + L"\\decode-trace.on").c_str()) != INVALID_FILE_ATTRIBUTES) {
                return true;
            }
            wchar_t module[MAX_PATH]{};
            const DWORD length = ::GetModuleFileNameW(nullptr, module, MAX_PATH);
            if (length == 0U || length >= MAX_PATH) {
                return false;
            }
            std::wstring beside{module, length};
            beside.resize(beside.find_last_of(L'\\') + 1U);
            return ::GetFileAttributesW((beside + L"decode-trace.on").c_str()) != INVALID_FILE_ATTRIBUTES;
        } catch (...) {
            return false;
        }
    }();
    return enabled;
}

void decode_trace_write(const char* const line) noexcept {
    if (!decode_trace_enabled() || line == nullptr) {
        return;
    }
    static std::mutex* const mutex = new std::mutex{};
    try {
        static const std::wstring path = decode_trace_folder() + L"\\decode-trace.txt";
        SYSTEMTIME now{};
        ::GetSystemTime(&now);
        const std::lock_guard<std::mutex> guard{*mutex};
        std::FILE* file = nullptr;
        if (_wfopen_s(&file, path.c_str(), L"ab") != 0 || file == nullptr) {
            return;
        }
        std::fprintf(file, "%02u:%02u:%02u.%03u %lu %s\n", now.wHour, now.wMinute, now.wSecond,
            now.wMilliseconds, ::GetCurrentThreadId(), line);
        std::fclose(file);
    } catch (...) {
    }
}

bool libraw_first_preview_possible(
    const std::filesystem::path& path,
    const std::uint32_t maximum_dimension) noexcept {
    const Api& functions = api();
    if (!libraw_supports_provisional_preview() || functions.first_preview_possible == nullptr ||
        path.empty() || maximum_dimension == 0U) {
        return false;
    }
    try {
        const Handle handle{functions};
        // 헤더만 읽습니다(크기 프로브와 같은 자리에서 멈춥니다).
        return handle.get() != nullptr && functions.open_wfile(handle.get(), path.c_str()) == 0 &&
            functions.first_preview_possible(
                handle.get(), static_cast<int>(std::min<std::uint32_t>(maximum_dimension, 65535U))) == 1;
    } catch (...) {
        return false;
    }
}

std::uint64_t libraw_retained_unpacked_bytes() noexcept {
    return g_retained_bytes.load(std::memory_order_relaxed);
}

void libraw_release_retained_unpacked() noexcept {
    void* released = nullptr;
    {
        const std::lock_guard<std::mutex> guard{retained_mutex()};
        RetainedUnpack& retained = retained_unpack();
        released = retained.handle;
        retained.handle = nullptr;
        retained.bytes = 0U;
        g_retained_bytes.store(0U, std::memory_order_relaxed);
    }
    close_handle(released);
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

LibRawShotResult probe_raw_shot_with_libraw(const std::filesystem::path& path) noexcept {
    LibRawShotResult result{};
    const Api& functions = api();
    if (functions.module == nullptr || functions.get_imgother == nullptr) {
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
        // 크기 프로브와 같이 **여기서 멈춥니다.** `libraw_open_wfile` 이 헤더를 훑으면서
        // `imgdata.other` 를 채우므로 현상까지 갈 이유가 없습니다.
        const int opened = functions.open_wfile(handle.get(), path.c_str());
        if (opened != 0) {
            result.status = LibRawDecodeStatus::open_failed;
            return result;
        }
        const LibRawImgOtherPrefix* const other = functions.get_imgother(handle.get());
        if (other == nullptr) {
            result.status = LibRawDecodeStatus::unsupported_output;
            return result;
        }
        const auto usable = [](const float value) noexcept {
            return value > 0.0F && value < 1.0e9F && value == value;
        };
        if (usable(other->iso_speed)) {
            result.shot.has_iso_speed = true;
            result.shot.iso_speed = static_cast<std::uint32_t>(other->iso_speed + 0.5F);
        }
        if (usable(other->shutter)) {
            result.shot.has_exposure_time = true;
            result.shot.exposure_time_seconds = static_cast<double>(other->shutter);
        }
        if (usable(other->aperture)) {
            result.shot.has_f_number = true;
            result.shot.f_number = static_cast<double>(other->aperture);
        }
        if (usable(other->focal_len)) {
            result.shot.has_focal_length = true;
            result.shot.focal_length_mm = static_cast<double>(other->focal_len);
        }
        result.status = LibRawDecodeStatus::ok;
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

    DecodeTraceTimer timer{path, result};
    try {
        // 임시 첫 화면과 unpack 이어 쓰기는 음화 RAW 와 디지털(양화) RAW 프리뷰 모두에 씁니다.
        // macOS 는 음화에만 쓰지만, Windows 실기에서는 디지털 RAW 샘플 일곱 장이 앱을 켜자마자
        // 썸네일(360 px)까지 원본 크기로 풀며 각 0.7~1.8 초씩 코어를 잡고 있었습니다(2026-10-31
        // `decode-trace.txt`). 호출부가 첫 화면을 청할 때(`raw_first_preview_edge`)만 돕니다.
        const bool provisional_capable = libraw_supports_provisional_preview();
        const bool wants_first = provisional_capable && control.raw_first_preview_edge != 0U;
        ImageFileObservation observation{};
        bool observed = false;
        if (provisional_capable && (!wants_first || control.retain_unpacked_raw)) {
            const ImageFileObservationResult current = observe_image_file(path);
            observed = current.status == ImageFileObservationStatus::ok;
            observation = current.observation;
        }
        // 정착 디코드는 바로 앞 임시 첫 화면이 남긴 unpack 을 이어 씁니다.
        void* const adopted = provisional_capable && !wants_first && observed
            ? take_retained(path, observation, control.scene_linear_raw)
            : nullptr;
        Handle handle = adopted != nullptr ? Handle{functions, adopted} : Handle{functions};
        if (handle.get() == nullptr) {
            result.status = LibRawDecodeStatus::allocation_failed;
            return result;
        }
        // 사진을 넘기면 이 디코드를 끊습니다(macOS `negaflow_libraw_cancel`). LibRaw 는 unpack 의
        // 디코더와 X-Trans 디모자이크의 타일 사이(`xtrans-parallel-rows.patch`)에서 이 표시를
        // 봅니다 — 실측: RAF 원본 처리 1,174 ms 를 150 ms 에 끊으면 216 ms 에 돌아옵니다. 콜백은
        // 핸들보다 먼저 사라지도록 핸들 뒤에 둡니다.
        void* const cancel_target = handle.get();
        const auto cancel_handle = [&functions, cancel_target]() noexcept {
            if (functions.cancel != nullptr) {
                functions.cancel(cancel_target);
            }
        };
        const std::stop_callback cancel_on_stop{stop_token, cancel_handle};
        // 위 표시를 보지 않는 단계도 있습니다 — Bayer 의 AHD 보간은 LibRaw 의 진행 콜백만 보고 멈춥니다.
        // 실기(2026-10-31): 52 MP CR2 의 정착 처리가 취소된 뒤에도 690 ms 를 더 돌아 다음 사진의 첫
        // 화면이 1.5 초 늦었습니다. 진행 콜백이 취소를 알리게 합니다. 취소가 없으면 늘 0 이라 결과는
        // 그대로입니다. 핸들을 남길 때는 이 함수의 stop_token 을 가리키지 않도록 먼저 떼고(아래), 그 밖의
        // 길은 함수를 나갈 때 뗍니다.
        struct ProgressCancel final {
            const Api& functions;
            const Handle& handle;
            ~ProgressCancel() {
                if (functions.set_progress_handler != nullptr && handle.get() != nullptr) {
                    functions.set_progress_handler(handle.get(), nullptr, nullptr);
                }
            }
        } const progress_cancel{functions, handle};
        if (functions.set_progress_handler != nullptr) {
            functions.set_progress_handler(
                handle.get(),
                [](void* const data, int, int, int) -> int {
                    return static_cast<const std::stop_token*>(data)->stop_requested() ? 1 : 0;
                },
                const_cast<std::stop_token*>(&stop_token));
        }

        if (adopted != nullptr) {
            timer.route = "adopted";
        }
        if (adopted == nullptr) {
            result.native_error_code = functions.open_wfile(handle.get(), path.c_str());
            timer.mark(timer.open_ms);
            if (result.native_error_code != 0) {
                result.status = LibRawDecodeStatus::open_failed;
                return result;
            }
            if (stop_token.stop_requested()) {
                result.status = LibRawDecodeStatus::cancelled;
                return result;
            }

            configure_as_shot(functions, handle.get());
            if (control.scene_linear_raw) {
                if (functions.get_rgb_cam == nullptr || functions.set_adjust_maximum_thr == nullptr) {
                    result.status = LibRawDecodeStatus::unsupported_output;
                    return result;
                }
                functions.set_output_color(handle.get(), 0);
                functions.set_adjust_maximum_thr(handle.get(), 0);
                functions.set_highlight(handle.get(), 1);
                for (int c = 0; c < 4; ++c) { functions.set_user_mul(handle.get(), c, 1); }
                functions.set_gamma(handle.get(), 0, 1.0F);
                functions.set_gamma(handle.get(), 1, 1.0F);
            }
            // 디지털 프리뷰만 선형 보간을 사용합니다. 음화는 프리뷰와 내보내기의
            // 채널 값이 같도록 양쪽 모두 LibRaw 기본 보간을 유지합니다.
            if (control.prefer_speed && !control.scene_linear_raw && functions.set_demosaic != nullptr) {
                functions.set_demosaic(handle.get(), 0);
            }

            // 필름 스캐너의 선형 DNG 는 LibRaw 의 unpack 없이 매핑한 파일에서 바로 줄입니다
            // (`linear_dng_mapped.h`). LibRaw 는 머리만 읽었고(검정·흰색·여백·방향 판정), 파일
            // 구조가 조금이라도 다르면 아래 unpack 으로 그대로 갑니다.
            int header_width = 0;
            int header_height = 0;
            int header_flip = 0;
            if (control.scene_linear_raw && control.max_output_width != 0U &&
                control.max_output_height != 0U && functions.linear_header != nullptr &&
                functions.get_rgb_cam != nullptr &&
                functions.linear_header(handle.get(), &header_width, &header_height, &header_flip) == 1) {
                const bool swapped = (header_flip & 4) != 0;
                // 첫 화면은 그 상자로 바로 줄이면서 원본 행을 띄엄띄엄 읽습니다. 출력 한 행(또는 회전이면
                // 한 열)이 원본 두 행 안팎을 평균하도록 간격은 축소 배율의 절반을 반올림한 값입니다 — 이
                // 폴더의 68.6 MP 스캔(10104x6792)을 2560 상자로 줄이면 배율 3.95, 간격 2 라 원본 행의
                // 절반만 읽습니다. 간격은 배율을 넘지 않으므로 어느 출력 칸에도 읽은 행이 하나 이상
                // 있습니다. 정착 결과와 화소가 다르므로 임시 화면입니다(캐시에 담지 않고 정착 디코드가
                // 원본 전체로 다시 풉니다).
                // 간격이 1 이면(배율이 작으면) 첫 화면도 여느 정착 디코드입니다. 그때 첫 화면 상자로
                // 줄이면 그 작은 화상이 정착 크기 캐시에 들어가 정착 화면까지 작아집니다.
                const std::uint32_t oriented_width = static_cast<std::uint32_t>(swapped ? header_height : header_width);
                const std::uint32_t oriented_height = static_cast<std::uint32_t>(swapped ? header_width : header_height);
                FittedPreview fitted =
                    fit_libraw_preview(oriented_width, oriented_height, control.max_output_width, control.max_output_height);
                std::uint32_t row_step = 1U;
                if (wants_first) {
                    const std::uint32_t first_box = std::min(
                        control.raw_first_preview_edge, std::max(control.max_output_width, control.max_output_height));
                    const FittedPreview first = fit_libraw_preview(oriented_width, oriented_height,
                        std::min(control.max_output_width, first_box), std::min(control.max_output_height, first_box));
                    // 원본 행 축의 배율: 회전이 없으면 세로, 90° 회전이면 가로입니다.
                    const double row_scale = static_cast<double>(header_height) /
                        std::max<std::uint32_t>(1U, swapped ? first.width : first.height);
                    const auto step = static_cast<std::uint32_t>(std::max(1L, std::lround(row_scale / 2.0)));
                    if (step > 1U) {
                        fitted = first;
                        row_step = step;
                    }
                }
                const std::uint32_t fitted_width = fitted.width;
                const std::uint32_t fitted_height = fitted.height;
                CameraToWorkingMatrix matrix{};
                for (int row = 0; row < 3; ++row) {
                    for (int col = 0; col < 3; ++col) {
                        matrix[static_cast<std::size_t>(row * 3 + col)] =
                            functions.get_rgb_cam(handle.get(), row, col);
                    }
                }
                if (valid_camera_matrix(matrix) &&
                    static_cast<std::uint64_t>(fitted_width) * fitted_height * 8ULL <= limits.max_decoded_pixel_bytes) {
                    const LinearDngMappedStatus mapped = decode_linear_dng_mapped(
                        path,
                        static_cast<std::uint32_t>(header_width),
                        static_cast<std::uint32_t>(header_height),
                        header_flip,
                        fitted_width,
                        fitted_height,
                        stop_token,
                        result.image,
                        row_step);
                    if (mapped == LinearDngMappedStatus::cancelled) {
                        result.status = LibRawDecodeStatus::cancelled;
                        return result;
                    }
                    if (mapped == LinearDngMappedStatus::ok) {
                        result.image.camera_to_working = matrix;
                        result.reduced_for_preview =
                            fitted_width != static_cast<std::uint32_t>(swapped ? header_height : header_width) ||
                            fitted_height != static_cast<std::uint32_t>(swapped ? header_width : header_height);
                        result.provisional = row_step > 1U;
                        timer.route = row_step > 1U ? "mapped-first" : "mapped";
                        timer.mark(timer.output_ms);
                        result.status = LibRawDecodeStatus::ok;
                        return result;
                    }
                }
            }

            result.native_error_code = functions.unpack(handle.get());
            timer.mark(timer.unpack_ms);
            if (result.native_error_code != 0) {
                result.status = stop_token.stop_requested()
                    ? LibRawDecodeStatus::cancelled
                    : LibRawDecodeStatus::unpack_failed;
                return result;
            }
            if (stop_token.stop_requested()) {
                result.status = LibRawDecodeStatus::cancelled;
                return result;
            }
        }

        // 필름 스캐너의 선형 DNG(검정 0·흰색 65535·CFA 없음)는 위 설정에서 처리가 항등입니다 —
        // 실측 6,830만 화소 세 장에서 처리 결과가 unpack 한 값과 화소 하나 다르지 않았고, 처리에
        // 555~590 ms 가 들었습니다. 그런 파일만 처리를 건너뛰고 unpack 한 값에서 바로 줄입니다.
        // 값이 같으므로 임시 화면이 아니라 정착 결과입니다. 프리뷰 상자가 있을 때만 씁니다.
        if (control.scene_linear_raw && control.max_output_width != 0U &&
            control.max_output_height != 0U && functions.linear_size != nullptr &&
            functions.make_linear_preview != nullptr) {
            int linear_width = 0;
            int linear_height = 0;
            if (functions.linear_size(handle.get(), &linear_width, &linear_height) == 1 &&
                linear_width > 0 && linear_height > 0) {
                const auto [fitted_width, fitted_height] = fit_libraw_preview(
                    static_cast<std::uint32_t>(linear_width),
                    static_cast<std::uint32_t>(linear_height),
                    control.max_output_width,
                    control.max_output_height);
                const std::uint64_t linear_bytes =
                    static_cast<std::uint64_t>(fitted_width) * fitted_height * 8ULL;
                const MemImage linear{functions, linear_bytes <= limits.max_decoded_pixel_bytes
                    ? functions.make_linear_preview(
                          handle.get(), static_cast<int>(fitted_width), static_cast<int>(fitted_height))
                    : nullptr};
                const LibRawProcessedImage* const reduced = linear.get();
                if (reduced != nullptr && reduced->type == libraw_image_bitmap &&
                    reduced->bits == 16U && reduced->colors == 4U &&
                    reduced->width == fitted_width && reduced->height == fitted_height &&
                    reduced->data_size == linear_bytes && functions.get_rgb_cam != nullptr) {
                    if (stop_token.stop_requested()) {
                        result.status = LibRawDecodeStatus::cancelled;
                        return result;
                    }
                    CameraToWorkingMatrix matrix{};
                    for (int row = 0; row < 3; ++row) {
                        for (int col = 0; col < 3; ++col) {
                            matrix[static_cast<std::size_t>(row * 3 + col)] =
                                functions.get_rgb_cam(handle.get(), row, col);
                        }
                    }
                    if (!valid_camera_matrix(matrix)) {
                        result.status = LibRawDecodeStatus::unsupported_output;
                        return result;
                    }
                    const auto* samples = reinterpret_cast<const std::uint16_t*>(reduced->data);
                    result.image.samples.assign(samples, samples + linear_bytes / sizeof(std::uint16_t));
                    result.image.width = fitted_width;
                    result.image.height = fitted_height;
                    result.image.stride_bytes = fitted_width * 8U;
                    result.image.layout = DecodedPixelLayout::rgba16;
                    result.image.alpha_mode = AlphaMode::unassociated;
                    result.image.untagged_rgb_transfer = UntaggedRgbTransfer::linear_scanner;
                    result.image.camera_to_working = matrix;
                    result.reduced_for_preview = fitted_width != static_cast<std::uint32_t>(linear_width) ||
                        fitted_height != static_cast<std::uint32_t>(linear_height);
                    result.provisional = false;
                    timer.route = "linear";
                    timer.mark(timer.output_ms);
                    result.status = LibRawDecodeStatus::ok;
                    return result;
                }
            }
        }

        // macOS `negaflow_libraw_preview_mode`: 긴 변의 절반이 첫 화면 상자 이상이면 반 크기,
        // X-Trans 는 선형 보간. 이 기계 실측으로 RAF 처리 1,207 ms 가 55 ms 가 됩니다. 빨리 만들
        // 길이 없으면(0) 여느 정착 디코드로 이어 갑니다.
        const int first_edge = static_cast<int>(
            std::min<std::uint32_t>(control.raw_first_preview_edge, 65535U));
        result.provisional = wants_first && functions.preview_mode(handle.get(), first_edge) == 1;

        if (result.provisional) {
            timer.route = "provisional";
        }
        result.native_error_code = functions.dcraw_process(handle.get());
        timer.mark(timer.process_ms);
        // 취소 표시는 LibRaw 가 읽을 때만 지워집니다. 처리가 표시를 보기 전에 끝났어도 그 핸들은
        // 다음 처리에서 곧바로 끊기므로 이어 쓰지 않습니다 — 취소면 여기서 끝냅니다.
        if (stop_token.stop_requested()) {
            result.status = LibRawDecodeStatus::cancelled;
            return result;
        }
        if (result.native_error_code != 0) {
            result.status = LibRawDecodeStatus::process_failed;
            return result;
        }

        // 처리 뒤 축소는 지금 길(원본 크기 사본 + 정수배 평균 + WIC)을 그대로 씁니다. macOS 의
        // `negaflow_libraw_make_preview` 로 바로 줄이는 길을 재 봤지만 이득이 없었습니다(RAF
        // 55→33 ms, 회전된 CR2 75→76~95 ms) — 시간은 unpack 과 디모자이크에 있습니다.
        int make_error = 0;
        const MemImage image{functions, functions.make_mem_image(handle.get(), &make_error)};
        if (image.get() == nullptr) {
            result.native_error_code = make_error;
            result.status = LibRawDecodeStatus::process_failed;
            return result;
        }
        {
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

            // 결과 계약은 WIC 경로와 같은 `rgba16` 입니다 — 화소당 8바이트. 다만 **원본
            // 크기로는 넓히지 않습니다.** 프리뷰가 요청한 상자까지 줄이면서 넓힙니다 —
            // `reduce_libraw_rgb16_to_preview` 주석에 그 이유와 실측이 있습니다.
            // 임시 첫 화면은 첫 화면 상자(인터랙티브)로 바로 줄입니다. 반 크기(RAF 3016 px)를 그대로
            // 넘기면 뒤에서 Lanczos 로 2560 까지 한 번 더 줄였습니다(실기 프록시 단계 60~80 ms).
            // 정착 결과는 지금처럼 정착 상자입니다 — 캐시가 그 크기로 담습니다.
            const std::uint32_t output_width = result.provisional && control.raw_first_preview_edge != 0U
                ? std::min(control.max_output_width == 0U ? control.raw_first_preview_edge : control.max_output_width,
                           control.raw_first_preview_edge)
                : control.max_output_width;
            const std::uint32_t output_height = result.provisional && control.raw_first_preview_edge != 0U
                ? std::min(control.max_output_height == 0U ? control.raw_first_preview_edge : control.max_output_height,
                           control.raw_first_preview_edge)
                : control.max_output_height;
            const LibRawPreviewReduceResult reduced = reduce_libraw_rgb16_to_preview(
                reinterpret_cast<const std::uint16_t*>(produced.data),
                static_cast<std::uint32_t>(width),
                static_cast<std::uint32_t>(height),
                output_width,
                output_height,
                limits.max_decoded_pixel_bytes,
                result.image);
            if (!reduced.ok) {
                result.status = LibRawDecodeStatus::memory_limit_exceeded;
                return result;
            }
            result.reduced_for_preview = reduced.reduced;
        }
        if (control.scene_linear_raw) {
            result.image.untagged_rgb_transfer = UntaggedRgbTransfer::linear_scanner;
            CameraToWorkingMatrix matrix{};
            for (int row = 0; row < 3; ++row) {
                for (int col = 0; col < 3; ++col) {
                    matrix[static_cast<std::size_t>(row * 3 + col)] = functions.get_rgb_cam(handle.get(), row, col);
                }
            }
            if (!valid_camera_matrix(matrix)) { result.status = LibRawDecodeStatus::unsupported_output; return result; }
            result.image.camera_to_working = matrix;
        }

        if (stop_token.stop_requested()) {
            std::vector<std::uint16_t>{}.swap(result.image.samples);
            result.status = LibRawDecodeStatus::cancelled;
            return result;
        }

        // 임시 첫 화면을 만든 핸들을 정착 디코드에 넘깁니다. 처리 결과 버퍼는 지금 놓고
        // (`libraw_free_image`), 반 크기 설정을 되돌리고, 파일을 닫습니다. 남는 것은 unpack 한
        // 센서 원본 한 벌(가로×세로×2 바이트)뿐입니다.
        if (result.provisional && control.retain_unpacked_raw && observed) {
            functions.free_image(handle.get());
            (void)functions.preview_mode(handle.get(), 0);
            // `preview_mode(0)` 은 보간을 LibRaw 기본으로 되돌립니다. 디지털 프리뷰는 처음에 선형
            // 보간을 골랐으므로(아래 `prefer_speed`) 그대로 다시 겁니다 — 안 그러면 이어 쓴 정착이
            // X-Trans 3 패스로 돌아 1.4 초가 됩니다(실측 X-T30 III).
            if (control.prefer_speed && !control.scene_linear_raw && functions.set_demosaic != nullptr) {
                functions.set_demosaic(handle.get(), 0);
            }
            functions.recycle_datastream(handle.get());
            const std::uint64_t raw_bytes =
                static_cast<std::uint64_t>(std::max(0, functions.get_raw_width(handle.get()))) *
                static_cast<std::uint64_t>(std::max(0, functions.get_raw_height(handle.get()))) *
                sizeof(std::uint16_t);
            if (functions.set_progress_handler != nullptr) {
                functions.set_progress_handler(handle.get(), nullptr, nullptr);
            }
            store_retained(handle.release(), path, observation, control.scene_linear_raw, raw_bytes);
        }

        timer.mark(timer.output_ms);
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
