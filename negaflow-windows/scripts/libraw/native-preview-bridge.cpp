// SPDX-License-Identifier: CDDL-1.0
// Copyright 2026 Negaflow contributors.
//
// 위쪽 네 함수는 macOS `negaflow-mac/scripts/libraw/native-preview-bridge.cpp` 와 같습니다. 다른
// 것은 Windows DLL 이 심볼을 내보내도록 `DllDef` 를 붙인 것뿐입니다 — 맥은 기본 가시성으로
// 나갑니다. 그 아래(첫 화면 가능 여부, 선형 DNG 셋, 화소 고리를 여러 코어로 도는 처리기, CR2·NEF
// 의 Huffman 데이터를 여러 코어로 푸는 해독기 둘)는 Windows 에만 있습니다. 해독기는 LibRaw 의
// `decoders_dcraw.cpp` 가 부릅니다(`raw-decoders-parallel.patch`).
// `build-libraw.ps1` 이 이 파일을 LibRaw 소스 트리의 `src\negaflow\` 로 복사해 DLL 에 함께
// 링크합니다(`native-preview-bridge-msvc.patch`).
#include "libraw/libraw.h"
#include <algorithm>
#include <climits>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <omp.h>

extern "C" DllDef int negaflow_libraw_preview_size(libraw_data_t* data, int* width, int* height) {
    if (!data || !data->parent_class || !data->image || !width || !height ||
        data->idata.colors != 3 || data->params.output_bps != 16 ||
        data->params.output_color != 0 || data->params.gamm[0] != 1 ||
        data->params.gamm[1] != 1 || data->params.bright != 1 || !data->params.no_auto_bright)
        return 0;
    int colors, bits;
    static_cast<LibRaw*>(data->parent_class)->get_mem_image_format(width, height, &colors, &bits);
    const int expected_width = (data->sizes.flip & 4) ? data->sizes.height : data->sizes.width;
    const int expected_height = (data->sizes.flip & 4) ? data->sizes.width : data->sizes.height;
    return colors == 3 && bits == 16 && *width == expected_width && *height == expected_height &&
        *width > 0 && *height > 0;
}

// Read canonical linear camera RGB directly. The upstream output curve is identity for
// gamma=1, bright=1 and no_auto_bright=1. Match the Swift area reducer's accumulation
// order, with FP contraction disabled by the build. The source stays owned by LibRaw.
extern "C" DllDef libraw_processed_image_t* negaflow_libraw_make_preview(
    libraw_data_t* data, int target_width, int target_height) {
    int width, height;
    if (!negaflow_libraw_preview_size(data, &width, &height) || target_width < 1 || target_height < 1 ||
        target_width > width || target_height > height ||
        static_cast<size_t>(target_width) * target_height > 128ULL * 1024 * 1024) return nullptr;
    const size_t bytes = static_cast<size_t>(target_width) * target_height * 8;
    auto* bitmap = static_cast<libraw_processed_image_t*>(std::malloc(sizeof(libraw_processed_image_t) + bytes));
    if (!bitmap) return nullptr;
    std::memset(bitmap, 0, sizeof(*bitmap));
    bitmap->type = LIBRAW_IMAGE_BITMAP;
    bitmap->width = target_width; bitmap->height = target_height;
    bitmap->colors = 4; bitmap->bits = 16; bitmap->data_size = static_cast<unsigned>(bytes);
    try {
        std::vector<int> start(target_width), end(target_width);
        std::vector<float> first(target_width), last(target_width), span(target_width);
        const double xscale = double(width) / target_width, yscale = double(height) / target_height;
        for (int x = 0; x < target_width; ++x) {
            const double left = x * xscale, right = std::min(double(width), (x + 1) * xscale);
            const int s = int(left), e = std::max(s + 1, std::min(width, int(std::ceil(right))));
            start[x] = s; end[x] = e; span[x] = float(right - left);
            first[x] = float(e - s == 1 ? right - left : double(s + 1) - left);
            last[x] = float(e - s == 1 ? right - left : right - double(e - 1));
        }
        const int flip = data->sizes.flip, source_width = data->sizes.width, source_height = data->sizes.height;
        auto pixel = [&](int y, int x) {
            if (flip & 4) std::swap(y, x);
            if (flip & 2) y = source_height - 1 - y;
            if (flip & 1) x = source_width - 1 - x;
            return data->image[static_cast<size_t>(y) * source_width + x];
        };
        auto* output = reinterpret_cast<unsigned short*>(bitmap->data);
        const int bands = std::min(target_height, std::max(1, omp_get_max_threads() * 4));
        // Allocate before entering OpenMP: allocation exceptions must not escape a worker.
        std::vector<float> scratch(static_cast<size_t>(bands) * target_width * 3);
#pragma omp parallel for schedule(static)
        for (int band = 0; band < bands; ++band) {
            float* acc = scratch.data() + static_cast<size_t>(band) * target_width * 3;
            for (int y = band * target_height / bands; y < (band + 1) * target_height / bands; ++y) {
                const double top = y * yscale, bottom = std::min(double(height), (y + 1) * yscale);
                std::fill(acc, acc + target_width * 3, 0.f);
                for (int sy = int(top); double(sy) < bottom && sy < height; ++sy) {
                    const float wy = float(std::min(double(sy + 1), bottom) - std::max(double(sy), top));
                    for (int x = 0; x < target_width; ++x) {
                        float r = 0, g = 0, b = 0;
                        for (int sx = start[x]; sx < end[x]; ++sx) {
                            const float w = sx == start[x] ? first[x] : (sx == end[x] - 1 ? last[x] : 1.f);
                            const auto* p = pixel(sy, sx);
                            r += w * p[0]; g += w * p[1]; b += w * p[2];
                        }
                        acc[x * 3] += wy * r; acc[x * 3 + 1] += wy * g; acc[x * 3 + 2] += wy * b;
                    }
                }
                const float row_span = float(bottom - top);
                for (int x = 0; x < target_width; ++x) {
                    const float norm = 1.f / (span[x] * row_span);
                    auto* out = output + (static_cast<size_t>(y) * target_width + x) * 4;
                    for (int c = 0; c < 3; ++c)
                        out[c] = static_cast<unsigned short>(std::min(65535.f, std::max(0.f, acc[x * 3 + c] * norm + 0.5f)));
                    out[3] = 65535;
                }
            }
        }
        return bitmap;
    } catch (...) {
        std::free(bitmap);
        return nullptr;
    }
}
extern "C" DllDef int negaflow_libraw_preview_mode(libraw_data_t* data, int maximum_dimension) {
    if (!data) return 0;
    data->params.half_size = 0;
    data->params.user_qual = -1;
    if (maximum_dimension <= 0 || !data->rawdata.raw_image || data->idata.colors != 3) return 0;
    const unsigned side = data->sizes.width > data->sizes.height ? data->sizes.width : data->sizes.height;
    if ((data->idata.filters == 9 || data->idata.filters > 1000) &&
        side / 2 >= static_cast<unsigned>(maximum_dimension) && data->sizes.pixel_aspect == 1.0) {
        data->params.half_size = 1;
        data->params.user_qual = 0;
        return 1;
    }
    if (data->idata.filters == 9) {
        data->params.user_qual = 0;
        return 1;
    }
    return 0;
}
extern "C" DllDef void negaflow_libraw_cancel(libraw_data_t* data) {
    if (data && data->parent_class) static_cast<LibRaw*>(data->parent_class)->setCancelFlag();
}

// ── Windows addition: can a half-size first preview be made, from the header alone ──
//
// Same decision as negaflow_libraw_preview_mode, but answerable right after open_file (no unpack),
// so the app can choose between "make the quick first preview now" and "wait for the decode a
// neighbour prefetch already started".
extern "C" DllDef int negaflow_libraw_first_preview_possible(libraw_data_t* data, int maximum_dimension) {
    if (!data || maximum_dimension <= 0 || data->idata.colors != 3) return 0;
    const unsigned side = data->sizes.width > data->sizes.height ? data->sizes.width : data->sizes.height;
    if ((data->idata.filters == 9 || data->idata.filters > 1000) &&
        side / 2 >= static_cast<unsigned>(maximum_dimension) && data->sizes.pixel_aspect == 1.0)
        return 1;
    return data->idata.filters == 9 ? 1 : 0;
}

// ── Windows addition: linear (demosaiced) DNG without dcraw_process ─────────────
//
// Film-scanner DNGs are LinearRaw: no CFA, three colours, black 0 and white 65535. With the
// scene-linear settings above (raw colour, unit multipliers, gamma 1, no auto-bright),
// dcraw_process() maps such data through identity scaling. On three 68 MP scanner DNGs the
// processed image equalled the unpacked samples exactly, and processing cost 555-590 ms.
// For exactly that case the preview is reduced straight from the unpacked samples. Any other
// file (black level, crop margins, non-square pixels, a CFA) reports 0 and keeps the normal path.
namespace {
bool linear_identity(const libraw_data_t* data) {
    if (!data || data->idata.filters != 0 || data->idata.colors != 3 ||
        (!data->rawdata.color4_image && !data->rawdata.color3_image) ||
        data->color.black != 0 || data->color.maximum != 65535 ||
        data->sizes.left_margin != 0 || data->sizes.top_margin != 0 ||
        data->sizes.raw_width != data->sizes.width || data->sizes.raw_height != data->sizes.height ||
        data->sizes.pixel_aspect != 1.0 || data->params.half_size ||
        data->params.output_bps != 16 || data->params.output_color != 0 ||
        data->params.gamm[0] != 1 || data->params.gamm[1] != 1 ||
        data->params.bright != 1 || !data->params.no_auto_bright)
        return false;
    for (int c = 0; c < 6; ++c)
        if (data->color.cblack[c] != 0) return false;
    for (int c = 0; c < 4; ++c)
        if (data->params.user_mul[c] != 1.f) return false;
    return true;
}
}  // namespace

// Same identity conditions answered right after open_file, before unpack, plus the orientation.
// The app then reads such a file straight from a memory mapping instead of unpacking it: on
// four 68 MP scanner DNGs that took 73-102 ms against 457-481 ms, with identical pixels.
extern "C" DllDef int negaflow_libraw_linear_header(libraw_data_t* data, int* width, int* height, int* flip) {
    if (!data || !width || !height || !flip || data->idata.filters != 0 || data->idata.colors != 3 ||
        data->color.black != 0 || data->color.maximum != 65535 ||
        data->sizes.left_margin != 0 || data->sizes.top_margin != 0 ||
        data->sizes.raw_width != data->sizes.width || data->sizes.raw_height != data->sizes.height ||
        data->sizes.pixel_aspect != 1.0 || data->params.half_size ||
        data->params.output_bps != 16 || data->params.output_color != 0 ||
        data->params.gamm[0] != 1 || data->params.gamm[1] != 1 ||
        data->params.bright != 1 || !data->params.no_auto_bright)
        return 0;
    for (int c = 0; c < 6; ++c)
        if (data->color.cblack[c] != 0) return 0;
    for (int c = 0; c < 4; ++c)
        if (data->params.user_mul[c] != 1.f) return 0;
    *width = data->sizes.width;
    *height = data->sizes.height;
    *flip = data->sizes.flip;
    return *width > 0 && *height > 0;
}

extern "C" DllDef int negaflow_libraw_linear_size(libraw_data_t* data, int* width, int* height) {
    if (!linear_identity(data) || !width || !height) return 0;
    const bool swap = (data->sizes.flip & 4) != 0;
    *width = swap ? data->sizes.height : data->sizes.width;
    *height = swap ? data->sizes.width : data->sizes.height;
    return *width > 0 && *height > 0;
}

// Area average with the same weights and accumulation order as negaflow_libraw_make_preview,
// reading the unpacked samples (row pitch raw_pitch) instead of the processed image.
extern "C" DllDef libraw_processed_image_t* negaflow_libraw_make_linear_preview(
    libraw_data_t* data, int target_width, int target_height) {
    int width, height;
    if (!negaflow_libraw_linear_size(data, &width, &height) || target_width < 1 || target_height < 1 ||
        target_width > width || target_height > height ||
        static_cast<size_t>(target_width) * target_height > 128ULL * 1024 * 1024) return nullptr;
    const size_t bytes = static_cast<size_t>(target_width) * target_height * 8;
    auto* bitmap = static_cast<libraw_processed_image_t*>(std::malloc(sizeof(libraw_processed_image_t) + bytes));
    if (!bitmap) return nullptr;
    std::memset(bitmap, 0, sizeof(*bitmap));
    bitmap->type = LIBRAW_IMAGE_BITMAP;
    bitmap->width = target_width; bitmap->height = target_height;
    bitmap->colors = 4; bitmap->bits = 16; bitmap->data_size = static_cast<unsigned>(bytes);
    try {
        std::vector<int> start(target_width), end(target_width);
        std::vector<float> first(target_width), last(target_width), span(target_width);
        const double xscale = double(width) / target_width, yscale = double(height) / target_height;
        for (int x = 0; x < target_width; ++x) {
            const double left = x * xscale, right = std::min(double(width), (x + 1) * xscale);
            const int s = int(left), e = std::max(s + 1, std::min(width, int(std::ceil(right))));
            start[x] = s; end[x] = e; span[x] = float(right - left);
            first[x] = float(e - s == 1 ? right - left : double(s + 1) - left);
            last[x] = float(e - s == 1 ? right - left : right - double(e - 1));
        }
        const int flip = data->sizes.flip, source_width = data->sizes.width, source_height = data->sizes.height;
        const size_t pitch = data->sizes.raw_pitch;
        const auto* four = reinterpret_cast<const char*>(data->rawdata.color4_image);
        const auto* three = reinterpret_cast<const char*>(data->rawdata.color3_image);
        auto pixel = [&](int y, int x) -> const unsigned short* {
            if (flip & 4) std::swap(y, x);
            if (flip & 2) y = source_height - 1 - y;
            if (flip & 1) x = source_width - 1 - x;
            return four ? reinterpret_cast<const unsigned short(*)[4]>(four + static_cast<size_t>(y) * pitch)[x]
                        : reinterpret_cast<const unsigned short(*)[3]>(three + static_cast<size_t>(y) * pitch)[x];
        };
        auto* output = reinterpret_cast<unsigned short*>(bitmap->data);
        const int bands = std::min(target_height, std::max(1, omp_get_max_threads() * 4));
        std::vector<float> scratch(static_cast<size_t>(bands) * target_width * 3);
#pragma omp parallel for schedule(static)
        for (int band = 0; band < bands; ++band) {
            float* acc = scratch.data() + static_cast<size_t>(band) * target_width * 3;
            for (int y = band * target_height / bands; y < (band + 1) * target_height / bands; ++y) {
                const double top = y * yscale, bottom = std::min(double(height), (y + 1) * yscale);
                std::fill(acc, acc + target_width * 3, 0.f);
                for (int sy = int(top); double(sy) < bottom && sy < height; ++sy) {
                    const float wy = float(std::min(double(sy + 1), bottom) - std::max(double(sy), top));
                    for (int x = 0; x < target_width; ++x) {
                        float r = 0, g = 0, b = 0;
                        for (int sx = start[x]; sx < end[x]; ++sx) {
                            const float w = sx == start[x] ? first[x] : (sx == end[x] - 1 ? last[x] : 1.f);
                            const auto* p = pixel(sy, sx);
                            r += w * p[0]; g += w * p[1]; b += w * p[2];
                        }
                        acc[x * 3] += wy * r; acc[x * 3 + 1] += wy * g; acc[x * 3 + 2] += wy * b;
                    }
                }
                const float row_span = float(bottom - top);
                for (int x = 0; x < target_width; ++x) {
                    const float norm = 1.f / (span[x] * row_span);
                    auto* out = output + (static_cast<size_t>(y) * target_width + x) * 4;
                    for (int c = 0; c < 3; ++c)
                        out[c] = static_cast<unsigned short>(std::min(65535.f, std::max(0.f, acc[x * 3 + c] * norm + 0.5f)));
                    out[3] = 65535;
                }
            }
        }
        return bitmap;
    } catch (...) {
        std::free(bitmap);
        return nullptr;
    }
}

// ── Windows addition: LibRaw's per-pixel loops on every core ───────────────────
//
// LibRaw keeps three per-pixel loops as virtual methods so that a subclass can replace them:
// scale_colors_loop, convert_to_rgb_loop and lin_interpolate_loop. The stock versions run on one
// core. These overrides compute the same expressions, split by pixel or by row:
//  - scale_colors_loop and convert_to_rgb_loop touch each pixel on its own; the histogram is
//    counted per thread and summed, and integer counts do not depend on the order of addition.
//  - lin_interpolate_loop writes only a pixel's own non-native channels and reads only its
//    neighbours' native channels, which nothing writes, so rows do not depend on one another.
// On this machine (16 threads) the processed images were byte-identical to stock LibRaw for RAF,
// CR2, ARW and NEF. dcraw_process went from 874 to 641 ms (CR2), 1189 to 875 ms (ARW) and 1191 to
// 1037 ms (RAF) with the negative settings, and from 489-656 to 191-233 ms with the linear
// interpolation of the digital preview. negaflow_libraw_init() replaces libraw_init();
// libraw_close() deletes through LibRaw's virtual destructor as before.
namespace {
class NegaflowLibRaw final : public LibRaw {
public:
    explicit NegaflowLibRaw(unsigned int flags) : LibRaw(flags) {}

protected:
    static unsigned short clip16(const int value) noexcept {
        return static_cast<unsigned short>(value < 0 ? 0 : (value > 65535 ? 65535 : value));
    }

    void scale_colors_loop(float scale_mul[4]) override {
        const int size = static_cast<int>(imgdata.sizes.iheight * imgdata.sizes.iwidth);
        const unsigned iwidth = imgdata.sizes.iwidth;
        unsigned short (*const image)[4] = imgdata.image;
        const unsigned* const cblack = imgdata.color.cblack;
        if (cblack[4] && cblack[5]) {
#pragma omp parallel for schedule(static)
            for (int index = 0; index < size; ++index) {
                const unsigned i = static_cast<unsigned>(index);
                for (unsigned c = 0; c < 4; c++) {
                    int val = image[i][c];
                    if (!val) continue;
                    val -= cblack[6 + i / iwidth % cblack[4] * cblack[5] + i % iwidth % cblack[5]];
                    val -= cblack[c];
                    val = int(val * scale_mul[c]);
                    image[i][c] = clip16(val);
                }
            }
        } else if (cblack[0] || cblack[1] || cblack[2] || cblack[3]) {
#pragma omp parallel for schedule(static)
            for (int index = 0; index < size; ++index) {
                const unsigned i = static_cast<unsigned>(index);
                for (unsigned c = 0; c < 4; c++) {
                    int val = image[i][c];
                    if (!val) continue;
                    val -= cblack[c];
                    val = int(val * scale_mul[c]);
                    image[i][c] = clip16(val);
                }
            }
        } else {
#pragma omp parallel for schedule(static)
            for (int index = 0; index < size; ++index) {
                const unsigned i = static_cast<unsigned>(index);
                for (unsigned c = 0; c < 4; c++) {
                    int val = image[i][c];
                    val = int(val * scale_mul[c]);
                    image[i][c] = clip16(val);
                }
            }
        }
    }

    void convert_to_rgb_loop(float out_cam[3][4]) override {
        constexpr int bins = LIBRAW_HISTOGRAM_SIZE;
        int (*const histogram)[LIBRAW_HISTOGRAM_SIZE] = libraw_internal_data.output_data.histogram;
        std::memset(histogram, 0, sizeof(int) * bins * 4);
        const int height = imgdata.sizes.height;
        const int width = imgdata.sizes.width;
        const int colors = imgdata.idata.colors;
        const bool raw_color = libraw_internal_data.internal_output_params.raw_color != 0;
        unsigned short (*const image)[4] = imgdata.image;
        const int threads = std::max(1, omp_get_max_threads());
        std::vector<int> local(static_cast<std::size_t>(threads) * 4U * bins, 0);
#pragma omp parallel
        {
            int* const counts = local.data() + static_cast<std::size_t>(omp_get_thread_num()) * 4U * bins;
#pragma omp for schedule(static)
            for (int row = 0; row < height; row++) {
                unsigned short* img = image[static_cast<std::size_t>(row) * width];
                if (raw_color) {
                    for (int col = 0; col < width; col++, img += 4) {
                        for (int c = 0; c < colors; c++) {
                            counts[c * bins + (img[c] >> 3)]++;
                        }
                    }
                } else if (colors == 3) {
                    float out[3];
                    for (int col = 0; col < width; col++, img += 4) {
                        out[0] = out_cam[0][0] * img[0] + out_cam[0][1] * img[1] +
                                 out_cam[0][2] * img[2];
                        out[1] = out_cam[1][0] * img[0] + out_cam[1][1] * img[1] +
                                 out_cam[1][2] * img[2];
                        out[2] = out_cam[2][0] * img[0] + out_cam[2][1] * img[1] +
                                 out_cam[2][2] * img[2];
                        img[0] = clip16((int)out[0]);
                        img[1] = clip16((int)out[1]);
                        img[2] = clip16((int)out[2]);
                        counts[0 * bins + (img[0] >> 3)]++;
                        counts[1 * bins + (img[1] >> 3)]++;
                        counts[2 * bins + (img[2] >> 3)]++;
                    }
                } else if (colors == 4) {
                    float out[3];
                    for (int col = 0; col < width; col++, img += 4) {
                        out[0] = out_cam[0][0] * img[0] + out_cam[0][1] * img[1] +
                                 out_cam[0][2] * img[2] + out_cam[0][3] * img[3];
                        out[1] = out_cam[1][0] * img[0] + out_cam[1][1] * img[1] +
                                 out_cam[1][2] * img[2] + out_cam[1][3] * img[3];
                        out[2] = out_cam[2][0] * img[0] + out_cam[2][1] * img[1] +
                                 out_cam[2][2] * img[2] + out_cam[2][3] * img[3];
                        img[0] = clip16((int)out[0]);
                        img[1] = clip16((int)out[1]);
                        img[2] = clip16((int)out[2]);
                        counts[0 * bins + (img[0] >> 3)]++;
                        counts[1 * bins + (img[1] >> 3)]++;
                        counts[2 * bins + (img[2] >> 3)]++;
                        counts[3 * bins + (img[3] >> 3)]++;
                    }
                }
            }
        }
        for (int t = 0; t < threads; ++t) {
            const int* const counts = local.data() + static_cast<std::size_t>(t) * 4U * bins;
            for (int c = 0; c < 4; ++c) {
                for (int bin = 0; bin < bins; ++bin) {
                    histogram[c][bin] += counts[c * bins + bin];
                }
            }
        }
    }

    void lin_interpolate_loop(int* code, int size) override {
        const int height = imgdata.sizes.height;
        const int width = imgdata.sizes.width;
        const int colors = imgdata.idata.colors;
        unsigned short (*const image)[4] = imgdata.image;
#pragma omp parallel for schedule(static)
        for (int row = 1; row < height - 1; row++) {
            for (int col = 1; col < width - 1; col++) {
                int sum[4];
                unsigned short* const pix = image[static_cast<std::size_t>(row) * width + col];
                int* ip = code + ((((row % size) * 16) + (col % size)) * 32);
                std::memset(sum, 0, sizeof sum);
                for (int i = *ip++; i--; ip += 3)
                    sum[ip[2]] += pix[ip[0]] << ip[1];
                for (int i = colors; --i; ip += 2)
                    pix[ip[0]] = static_cast<unsigned short>(sum[ip[0]] * ip[1] >> 8);
            }
        }
    }
};

}  // namespace

extern "C" DllDef libraw_data_t* negaflow_libraw_init(unsigned int flags) {
    try {
        return &(new NegaflowLibRaw(flags))->imgdata;
    } catch (...) {
        return nullptr;
    }
}

// ── Windows addition: Huffman-coded raw data decoded on every core ──────────────
//
// LibRaw reads Canon's lossless JPEG (CR2) and Nikon's compressed NEF data one bit at a time
// through the datastream, on one core: on this machine 245-425 ms for 12-21 MP CR2 files,
// 1020 ms for a 52 MP one, and 195-401 ms for 12-24 MP NEF files. Neither stream has restart
// markers, so it cannot be cut at known places. These decoders use the self-synchronising
// property of Huffman codes (S. T. Klein and Y. Wiseman, "Parallel Huffman decoding with
// applications to JPEG files", The Computer Journal 46(5), 2003): a decoder that starts at an
// arbitrary bit soon lands on the true codeword boundaries, and from the first boundary it shares
// with the true decoder on, both decode the same symbols.
//  1. The rest of the file is read once (for JPEG, the 0xFF00 stuffing is removed and reading
//     stops at the first marker, as LibRaw's bit reader does).
//  2. The bits are cut into chunks. Each chunk records where its first symbols start when decoded
//     from the cut; then each chunk decodes on past its end until it reaches one of those starts
//     in the next chunk. The true decoder (from bit 0) thereby hands over from chunk to chunk, and
//     symbols before a hand-over point are discarded.
//  3. Each chunk decodes its share again and leaves every difference at the pixel it belongs to.
//  4. The predictions are summed: the first column(s) of each row down the rows, then each row
//     along itself, rows in parallel.
// Only the plain cases are taken (see the two functions). Anything else, and any sign of damage
// that LibRaw would report through derror() - a code missing from the table, a value outside the
// sample range, running out of data - returns 0; the caller rewinds and runs LibRaw's own loop,
// so damaged files behave exactly as before. Valid files give raw_image byte for byte the same as
// LibRaw's loop (eight CR2 and six NEF files here, and damaged copies of them).
namespace {

struct BitSource final {
    const unsigned char* bytes{nullptr};
    unsigned long long total_bits{0};

    unsigned peek(unsigned long long pos, int count) const {
        const unsigned char* p = bytes + (pos >> 3);
        unsigned long long window = 0;
        for (int i = 0; i < 8; ++i) window = window << 8 | p[i];
        window <<= (pos & 7);
        return static_cast<unsigned>(window >> (64 - count));
    }
};

// The rest of the stream from its current position, in memory with 16 zero bytes after it (bits
// past the end read as zero, as in LibRaw). With `stuffed`, 0xFF 0x00 becomes 0xFF and the data
// ends before the first other 0xFF pair.
bool read_rest(LibRaw_abstract_datastream* input, const bool stuffed, std::vector<unsigned char>& buffer,
               BitSource& bits) {
    const INT64 start = input->tell();
    const INT64 size = input->size();
    if (start < 0 || size <= start || size - start >= (INT64(1) << 31)) return false;
    const size_t available = static_cast<size_t>(size - start);
    buffer.resize(available + 16);
    if (input->read(buffer.data(), 1, available) != static_cast<int>(available)) return false;
    unsigned char* data = buffer.data();
    size_t out = available;
    if (stuffed) {
        size_t in = 0;
        out = 0;
        while (in < available) {
            const void* found = std::memchr(data + in, 0xff, available - in);
            const size_t run = found ? static_cast<size_t>(static_cast<const unsigned char*>(found) - (data + in))
                                     : available - in;
            std::memmove(data + out, data + in, run);
            out += run;
            in += run;
            if (!found) break;
            if (in + 1 < available && data[in + 1] == 0) {
                data[out++] = 0xff;
                in += 2;
                continue;
            }
            break;  // a marker, or 0xFF as the last byte: LibRaw's reader stops before it
        }
    }
    std::memset(data + out, 0, 16);
    bits.bytes = data;
    bits.total_bits = static_cast<unsigned long long>(out) * 8;
    return bits.total_bits != 0;
}

// Steps 2 and 3. `decode(pos, odd)` returns one difference and moves `pos`; it sets `odd` where
// LibRaw's reader would not see a valid symbol (it still moves on, because paths that have not
// synchronised yet run into such patterns). `store(index, diff)` receives the true differences.
template <class Decode, class Store>
bool decode_parallel(const BitSource& bits, const Decode& decode, const long long symbols, const Store& store) {
    const int threads = std::max(1, omp_get_max_threads());
    const long long by_size = static_cast<long long>(bits.total_bits >> 16);
    const int chunks = static_cast<int>(std::max(1LL, std::min<long long>(by_size, threads * 4LL)));
    constexpr int recorded = 4096;
    std::vector<unsigned long long> cut(chunks + 1);
    for (int i = 0; i <= chunks; ++i) cut[i] = bits.total_bits * static_cast<unsigned long long>(i) / chunks;
    std::vector<unsigned long long> starts(static_cast<size_t>(chunks) * recorded);
    std::vector<int> start_count(chunks, 0);
#pragma omp parallel for schedule(dynamic, 1)
    for (int i = 1; i < chunks; ++i) {
        unsigned long long pos = cut[i];
        bool odd = false;
        int k = 0;
        while (k < recorded && pos < bits.total_bits) {
            starts[static_cast<size_t>(i) * recorded + k++] = pos;
            (void)decode(pos, odd);
        }
        start_count[i] = k;
    }
    std::vector<long long> end(chunks, -1);  // symbols on chunk i's path before it hands over
    std::vector<int> joined(chunks, 0);      // where on chunk i's path the true decoder joins
    std::vector<std::vector<long long>> odd_at(chunks);
#pragma omp parallel for schedule(dynamic, 1)
    for (int i = 0; i < chunks; ++i) {
        unsigned long long pos = i == 0 ? 0 : cut[i];
        long long index = 0;
        const bool last = i == chunks - 1;
        const unsigned long long* next = last ? nullptr : &starts[static_cast<size_t>(i + 1) * recorded];
        const int next_count = last ? 0 : start_count[i + 1];
        int j = 0;
        for (;;) {
            if (!last && pos >= cut[i + 1]) {
                while (j < next_count && next[j] < pos) ++j;
                if (j >= next_count) break;  // no hand-over: end stays -1
                if (next[j] == pos) {
                    end[i] = index;
                    joined[i + 1] = j;
                    break;
                }
            }
            if (last && pos >= bits.total_bits) {
                end[i] = index;
                break;
            }
            bool odd = false;
            (void)decode(pos, odd);
            if (odd) odd_at[i].push_back(index);
            ++index;
        }
    }
    std::vector<long long> offset(chunks + 1, 0);
    for (int i = 0; i < chunks; ++i) {
        if (end[i] < joined[i]) return false;
        offset[i + 1] = offset[i] + (end[i] - joined[i]);
    }
    if (offset[chunks] < symbols) return false;
    for (int i = 0; i < chunks; ++i) {
        const long long first = joined[i];
        const long long last = joined[i] + std::max(0LL, std::min(end[i] - joined[i], symbols - offset[i]));
        for (const long long at : odd_at[i])
            if (at >= first && at < last) return false;
    }
#pragma omp parallel for schedule(dynamic, 1)
    for (int i = 0; i < chunks; ++i) {
        if (offset[i] >= symbols) continue;
        unsigned long long pos = i == 0 ? 0 : starts[static_cast<size_t>(i) * recorded + joined[i]];
        const long long count = std::min(end[i] - joined[i], symbols - offset[i]);
        bool odd = false;
        for (long long k = 0; k < count; ++k) store(offset[i] + k, decode(pos, odd));
    }
    return true;
}

// A table entry as LibRaw's make_decoder() builds it: huff[0] is the longest code, then one entry
// (code length << 8 | symbol) per possible max-bit pattern.
struct HuffmanCode final {
    const unsigned short* huff;
    int max_bits;
    // Returns the symbol, or -1 for a pattern that is not a code (LibRaw reads it as length 0).
    int read(const BitSource& bits, unsigned long long& pos) const {
        const unsigned short entry = huff[1 + bits.peek(pos, max_bits)];
        if ((entry >> 8) == 0) {
            pos += 1;
            return -1;
        }
        pos += entry >> 8;
        return entry & 0xff;
    }
};

}  // namespace

// Lossless JPEG (LibRaw lossless_jpeg_load_raw): predictor 1, no restart interval, no sRAW, one
// Huffman table for every component, SSSS 16 meaning -32768, rows in order, and every difference
// landing inside raw_image through LibRaw's CR2 slice mapping.
int negaflow_ljpeg_parallel(LibRaw_abstract_datastream* input, const unsigned short* huff, int clrs, int bits,
                            int high, int wide, int short16, unsigned short* raw_image, unsigned raw_width,
                            unsigned raw_height, const unsigned short* curve, const unsigned short* slice) {
    try {
        if (!input || !huff || !raw_image || !curve || !slice || !short16 || clrs < 1 || clrs > 4 || bits < 1 ||
            bits > 16 || high < 1 || wide < 1 || raw_width < 1 || raw_height < 1)
            return 0;
        const HuffmanCode code{huff, huff[0]};
        if (code.max_bits < 1 || code.max_bits > 16) return 0;
        const long long jwide = static_cast<long long>(wide) * clrs;
        const long long symbols = jwide * high;
        if (symbols >= INT_MAX || static_cast<long long>(high) * wide >= INT_MAX) return 0;
        if (slice[0]) {
            if (!slice[1] || !slice[2]) return 0;
            if (static_cast<long long>(slice[0]) * slice[1] + slice[2] > raw_width) return 0;
            const long long base = static_cast<long long>(slice[0]) * slice[1] * raw_height;
            if (symbols > base && (symbols - 1 - base) / slice[2] >= raw_height) return 0;
        } else if ((symbols - 1) / raw_width >= raw_height) {
            return 0;
        }
        // LibRaw's placement of difference jidx = jrow * jwide + jcol.
        const auto place = [&](int jidx) -> size_t {
            int row, col;
            if (slice[0]) {
                const int band = slice[1] * static_cast<int>(raw_height);
                int i = jidx / band;
                const int j = i >= slice[0];
                if (j) i = slice[0];
                jidx -= i * band;
                row = jidx / slice[1 + j];
                col = jidx % slice[1 + j] + i * slice[1];
            } else {
                row = jidx / static_cast<int>(raw_width);
                col = jidx % static_cast<int>(raw_width);
            }
            return static_cast<size_t>(row) * raw_width + static_cast<size_t>(col);
        };

        std::vector<unsigned char> buffer;
        BitSource source{};
        if (!read_rest(input, true, buffer, source)) return 0;
        const auto decode = [&](unsigned long long& pos, bool& odd) -> int {
            const int ssss = code.read(source, pos);
            if (ssss < 0) {
                odd = true;
                return 0;
            }
            if (ssss == 0) return 0;
            if (ssss == 16) return -32768;
            if (ssss > 16) {
                odd = true;
                if (ssss <= 25) pos += static_cast<unsigned>(ssss);
                return 0;
            }
            int diff = static_cast<int>(source.peek(pos, ssss));
            pos += static_cast<unsigned>(ssss);
            if ((diff & (1 << (ssss - 1))) == 0) diff -= (1 << ssss) - 1;
            if (pos > source.total_bits) odd = true;
            return diff;
        };
        if (!decode_parallel(source, decode, symbols, [&](long long index, int diff) {
                raw_image[place(static_cast<int>(index))] = static_cast<unsigned short>(diff);
            }))
            return 0;

        // The first column follows the row above (LibRaw's vpred); the rest follow the left pixel.
        std::vector<unsigned short> first(static_cast<size_t>(high) * clrs);
        unsigned short vpred[4];
        for (int c = 0; c < clrs; ++c) vpred[c] = static_cast<unsigned short>(1 << (bits - 1));
        for (int jrow = 0; jrow < high; ++jrow)
            for (int c = 0; c < clrs; ++c) {
                const int diff = static_cast<short>(raw_image[place(static_cast<int>(jrow * jwide + c))]);
                vpred[c] = static_cast<unsigned short>(vpred[c] + diff);
                if (vpred[c] >> bits) return 0;
                first[static_cast<size_t>(jrow) * clrs + c] = vpred[c];
            }
        int damaged = 0;
#pragma omp parallel for schedule(static) reduction(| : damaged)
        for (int jrow = 0; jrow < high; ++jrow) {
            unsigned short left[4];
            for (int c = 0; c < clrs; ++c) left[c] = first[static_cast<size_t>(jrow) * clrs + c];
            const int row_start = static_cast<int>(jrow * jwide);
            for (int jcol = 0; jcol < jwide; ++jcol) {
                const size_t at = place(row_start + jcol);
                const int c = jcol % clrs;
                unsigned short value = left[c];
                if (jcol >= clrs) {
                    value = static_cast<unsigned short>(value + static_cast<short>(raw_image[at]));
                    left[c] = value;
                }
                if (value >> bits) damaged = 1;
                raw_image[at] = curve[value];
            }
        }
        return damaged ? 0 : 1;
    } catch (...) {
        return 0;
    }
}

// Nikon compressed NEF (LibRaw nikon_load_raw) without a split row: one Huffman table for the
// whole frame. `vpred` is the predictor block LibRaw read from the maker notes and `limit` its
// `max` (values at or above it are what LibRaw reports through derror()).
int negaflow_nikon_parallel(LibRaw_abstract_datastream* input, const unsigned short* huff, int stuffed,
                            int rows, unsigned raw_width, const unsigned short* vpred_in, int limit,
                            const unsigned short* curve, unsigned short* raw_image) {
    try {
        if (!input || !huff || !vpred_in || !curve || !raw_image || rows < 1 || raw_width < 2) return 0;
        const HuffmanCode code{huff, huff[0]};
        if (code.max_bits < 1 || code.max_bits > 16) return 0;
        const long long symbols = static_cast<long long>(rows) * raw_width;
        if (symbols >= INT_MAX) return 0;

        std::vector<unsigned char> buffer;
        BitSource source{};
        if (!read_rest(input, stuffed != 0, buffer, source)) return 0;
        const auto decode = [&](unsigned long long& pos, bool& odd) -> int {
            const int symbol = code.read(source, pos);
            if (symbol < 0) {
                odd = true;
                return 0;
            }
            const int len = symbol & 15;
            const int shl = symbol >> 4;
            const int extra = len - shl;
            if (extra < 0 || extra > 25) {
                odd = true;
                return 0;
            }
            const unsigned value = extra ? source.peek(pos, extra) : 0u;
            pos += static_cast<unsigned>(extra);
            int diff = static_cast<int>(((value << 1) + 1) << shl >> 1);
            if (len > 0 && (diff & (1 << (len - 1))) == 0) diff -= (1 << len) - !shl;
            if (pos > source.total_bits) odd = true;
            return diff;
        };
        if (!decode_parallel(source, decode, symbols, [&](long long index, int diff) {
                raw_image[index] = static_cast<unsigned short>(diff);
            }))
            return 0;

        // Columns 0 and 1 follow the earlier row of the same parity; the rest follow the pixel two to
        // the left (LibRaw's vpred and hpred).
        std::vector<unsigned short> first(static_cast<size_t>(rows) * 2);
        unsigned short vpred[2][2] = {{vpred_in[0], vpred_in[1]}, {vpred_in[2], vpred_in[3]}};
        for (int row = 0; row < rows; ++row)
            for (int c = 0; c < 2; ++c) {
                unsigned short& v = vpred[row & 1][c];
                v = static_cast<unsigned short>(v + static_cast<short>(raw_image[static_cast<size_t>(row) * raw_width + c]));
                first[static_cast<size_t>(row) * 2 + c] = v;
            }
        int damaged = 0;
#pragma omp parallel for schedule(static) reduction(| : damaged)
        for (int row = 0; row < rows; ++row) {
            unsigned short* const line = raw_image + static_cast<size_t>(row) * raw_width;
            unsigned short hpred[2] = {first[static_cast<size_t>(row) * 2], first[static_cast<size_t>(row) * 2 + 1]};
            for (unsigned col = 0; col < raw_width; ++col) {
                if (col >= 2) hpred[col & 1] = static_cast<unsigned short>(hpred[col & 1] + static_cast<short>(line[col]));
                const unsigned short value = hpred[col & 1];
                if (value >= limit) damaged = 1;
                const short clamped = static_cast<short>(value);
                line[col] = curve[clamped < 0 ? 0 : (clamped > 0x3fff ? 0x3fff : clamped)];
            }
        }
        return damaged ? 0 : 1;
    } catch (...) {
        return 0;
    }
}
