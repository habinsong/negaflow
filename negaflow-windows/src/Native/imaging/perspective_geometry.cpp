#include "negaflow/imaging/perspective_geometry.h"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace negaflow::imaging {
namespace {

// macOS `PerspectiveGeometry` 의 상수와 같습니다. 한쪽만 바꾸면 두 앱의 그림이 달라집니다.
constexpr double focal_length = 1.2;
constexpr double slider_degrees = 35.0;
constexpr double maximum_solved_degrees = 40.0;
constexpr double minimum_depth = 0.05;

using Matrix = std::array<double, 9>;

[[nodiscard]] Matrix multiply(const Matrix& a, const Matrix& b) noexcept {
    Matrix out{};
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            double sum = 0.0;
            for (int k = 0; k < 3; ++k) {
                sum += a[(row * 3) + k] * b[(k * 3) + column];
            }
            out[(row * 3) + column] = sum;
        }
    }
    return out;
}

[[nodiscard]] std::optional<Matrix> invert(const Matrix& m) noexcept {
    const double a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8];
    const double det = (a * ((e * i) - (f * h))) - (b * ((d * i) - (f * g))) + (c * ((d * h) - (e * g)));
    if (!std::isfinite(det) || std::abs(det) < 1.0e-15) {
        return std::nullopt;
    }
    const double s = 1.0 / det;
    return Matrix{
        ((e * i) - (f * h)) * s, ((c * h) - (b * i)) * s, ((b * f) - (c * e)) * s,
        ((f * g) - (d * i)) * s, ((a * i) - (c * g)) * s, ((c * d) - (a * f)) * s,
        ((d * h) - (e * g)) * s, ((b * g) - (a * h)) * s, ((a * e) - (b * d)) * s,
    };
}

// 로드리게스 공식. y 아래 카메라 좌표(x 오른쪽, y 아래, z 앞).
[[nodiscard]] Matrix rotation_matrix(const double wx, const double wy, const double wz) noexcept {
    const double angle = std::sqrt((wx * wx) + (wy * wy) + (wz * wz));
    if (angle <= 1.0e-12) {
        return Matrix{1, 0, 0, 0, 1, 0, 0, 0, 1};
    }
    const double kx = wx / angle, ky = wy / angle, kz = wz / angle;
    const Matrix k{0, -kz, ky, kz, 0, -kx, -ky, kx, 0};
    const Matrix k2 = multiply(k, k);
    const double s = std::sin(angle), c = 1.0 - std::cos(angle);
    Matrix out{1, 0, 0, 0, 1, 0, 0, 0, 1};
    for (std::size_t index = 0U; index < out.size(); ++index) {
        out[index] += (s * k[index]) + (c * k2[index]);
    }
    return out;
}

[[nodiscard]] bool contains(const std::array<PerspectivePoint, 4>& polygon, const PerspectivePoint p) noexcept {
    double sign = 0.0;
    for (std::size_t index = 0U; index < polygon.size(); ++index) {
        const PerspectivePoint a = polygon[index];
        const PerspectivePoint b = polygon[(index + 1U) % polygon.size()];
        const double cross = ((b.x - a.x) * (p.y - a.y)) - ((b.y - a.y) * (p.x - a.x));
        if (std::abs(cross) < 1.0e-9) {
            continue;
        }
        const double current = cross > 0.0 ? 1.0 : -1.0;
        if (sign == 0.0) {
            sign = current;
        } else if (current != sign) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool in_range(const double value, const double limit) noexcept {
    return std::isfinite(value) && std::abs(value) <= limit;
}

} // namespace

bool valid_perspective_parameters(const PerspectiveParameters& p) noexcept {
    return in_range(p.solved_vertical, maximum_solved_degrees) &&
        in_range(p.solved_horizontal, maximum_solved_degrees) && in_range(p.solved_rotate, 45.0) &&
        in_range(p.vertical, 100.0) && in_range(p.horizontal, 100.0) && in_range(p.rotate, 10.0) &&
        in_range(p.aspect, 100.0) && std::isfinite(p.scale) && p.scale >= 50.0 && p.scale <= 150.0 &&
        in_range(p.offset_x, 100.0) && in_range(p.offset_y, 100.0);
}

bool perspective_changes_geometry(const PerspectiveParameters& p) noexcept {
    if (!p.active) {
        return false;
    }
    const double v = p.solved_vertical + (p.vertical / 100.0 * slider_degrees);
    const double h = p.solved_horizontal + (p.horizontal / 100.0 * slider_degrees);
    const double r = p.solved_rotate + p.rotate;
    return std::sqrt((v * v) + (h * h) + (r * r)) * std::numbers::pi / 180.0 > 1.0e-7 ||
        std::abs(p.aspect) > 1.0e-6 || std::abs(p.scale - 100.0) > 1.0e-6 ||
        std::abs(p.offset_x) > 1.0e-6 || std::abs(p.offset_y) > 1.0e-6;
}

std::optional<PerspectivePoint> apply_homography(const Matrix& m, const PerspectivePoint p) noexcept {
    const double x = (m[0] * p.x) + (m[1] * p.y) + m[2];
    const double y = (m[3] * p.x) + (m[4] * p.y) + m[5];
    const double z = (m[6] * p.x) + (m[7] * p.y) + m[8];
    if (std::abs(z) <= 1.0e-12) {
        return std::nullopt;
    }
    const PerspectivePoint out{x / z, y / z};
    if (!std::isfinite(out.x) || !std::isfinite(out.y)) {
        return std::nullopt;
    }
    return out;
}

std::optional<PerspectiveMapping> make_perspective_mapping(
    const PerspectiveParameters& p, const double w, const double h) noexcept {
    if (!perspective_changes_geometry(p) || !valid_perspective_parameters(p) || !(w > 1.0) || !(h > 1.0)) {
        return std::nullopt;
    }
    const double s = std::max(w, h) / 2.0;
    const Matrix to_normal{1.0 / s, 0, -w / 2.0 / s, 0, 1.0 / s, -h / 2.0 / s, 0, 0, 1};
    const Matrix to_pixel{s, 0, w / 2.0, 0, s, h / 2.0, 0, 0, 1};
    const double f = focal_length;
    const Matrix k{f, 0, 0, 0, f, 0, 0, 0, 1};
    const Matrix k_inverse{1.0 / f, 0, 0, 0, 1.0 / f, 0, 0, 0, 1};
    const double radians = std::numbers::pi / 180.0;
    const Matrix rotation = rotation_matrix(
        (p.solved_vertical + (p.vertical / 100.0 * slider_degrees)) * radians,
        (p.solved_horizontal + (p.horizontal / 100.0 * slider_degrees)) * radians,
        (p.solved_rotate + p.rotate) * radians);
    const double stretch = std::pow(2.0, p.aspect / 200.0);
    const double zoom = p.scale / 100.0;
    const Matrix planar{zoom * stretch, 0, p.offset_x / 100.0 * 0.5, 0, zoom / stretch, p.offset_y / 100.0 * 0.5,
                        0, 0, 1};
    // 기울인 그림의 중심을 프레임 가운데로 되돌립니다(macOS PerspectiveGeometry.homography 와 같은 식).
    const Matrix tilt = multiply(multiply(k, rotation), k_inverse);
    const Matrix recenter = tilt[8] > minimum_depth
        ? Matrix{1, 0, -tilt[2] / tilt[8], 0, 1, -tilt[5] / tilt[8], 0, 0, 1}
        : Matrix{1, 0, 0, 0, 1, 0, 0, 0, 1};
    const Matrix forward = multiply(multiply(multiply(multiply(to_pixel, planar), recenter), tilt), to_normal);

    PerspectiveMapping mapping{};
    mapping.width = w;
    mapping.height = h;
    mapping.forward = forward;
    const std::array<PerspectivePoint, 4> source{{{0, 0}, {w, 0}, {w, h}, {0, h}}};
    for (std::size_t index = 0U; index < source.size(); ++index) {
        const double z = (forward[6] * source[index].x) + (forward[7] * source[index].y) + forward[8];
        const auto mapped = apply_homography(forward, source[index]);
        if (!(z > minimum_depth) || !mapped.has_value()) {
            return std::nullopt;
        }
        mapping.corners[index] = *mapped;
    }
    const auto inverse = invert(forward);
    if (!inverse.has_value()) {
        return std::nullopt;
    }
    mapping.inverse = *inverse;
    mapping.output_left = 0.0;
    mapping.output_top = 0.0;
    mapping.output_width = w;
    mapping.output_height = h;
    if (!p.constrain_crop) {
        return mapping;
    }
    // 볼록 사각형과 캔버스 안에 들어가는, 캔버스와 같은 비율의 가장 큰 사각형. 중심은 보정한
    // 그림의 중심이고 캔버스 밖이면 안으로 당깁니다(macOS `inscribedRect`).
    const PerspectivePoint raw_center =
        apply_homography(forward, {w / 2.0, h / 2.0}).value_or(PerspectivePoint{w / 2.0, h / 2.0});
    const PerspectivePoint center{std::clamp(raw_center.x, 1.0, w - 1.0), std::clamp(raw_center.y, 1.0, h - 1.0)};
    if (!contains(mapping.corners, center)) {
        return std::nullopt;
    }
    const double aspect = w / h;
    const auto fits = [&](const double half_height) noexcept {
        const double half_width = half_height * aspect;
        const double left = center.x - half_width, right = center.x + half_width;
        const double top = center.y - half_height, bottom = center.y + half_height;
        if (left < -1.0e-6 || top < -1.0e-6 || right > w + 1.0e-6 || bottom > h + 1.0e-6) {
            return false;
        }
        return contains(mapping.corners, {left, top}) && contains(mapping.corners, {right, top}) &&
            contains(mapping.corners, {right, bottom}) && contains(mapping.corners, {left, bottom});
    };
    double low = 0.0, high = h / 2.0;
    for (int iteration = 0; iteration < 40; ++iteration) {
        const double mid = (low + high) / 2.0;
        if (fits(mid)) {
            low = mid;
        } else {
            high = mid;
        }
    }
    const double half_height = low, half_width = low * aspect;
    if (half_height < 4.0 || half_width < 4.0) {
        return std::nullopt;
    }
    const double x0 = std::ceil(center.x - half_width), y0 = std::ceil(center.y - half_height);
    const double x1 = std::floor(center.x + half_width), y1 = std::floor(center.y + half_height);
    if (x1 - x0 < 8.0 || y1 - y0 < 8.0) {
        return std::nullopt;
    }
    mapping.output_left = x0;
    mapping.output_top = y0;
    mapping.output_width = x1 - x0;
    mapping.output_height = y1 - y0;
    return mapping;
}

} // namespace negaflow::imaging
