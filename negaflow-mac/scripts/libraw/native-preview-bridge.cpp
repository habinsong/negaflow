// SPDX-License-Identifier: CDDL-1.0
// Copyright 2026 Negaflow contributors.
#include "libraw/libraw.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <omp.h>

extern "C" int negaflow_libraw_preview_size(libraw_data_t* data, int* width, int* height) {
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
extern "C" libraw_processed_image_t* negaflow_libraw_make_preview(
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
extern "C" int negaflow_libraw_preview_mode(libraw_data_t* data, int maximum_dimension) {
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
extern "C" void negaflow_libraw_cancel(libraw_data_t* data) {
    if (data && data->parent_class) static_cast<LibRaw*>(data->parent_class)->setCancelFlag();
}
