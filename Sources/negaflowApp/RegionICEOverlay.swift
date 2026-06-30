import SwiftUI
import AppKit
import Chromabase

// 반자동 Region ICE 오버레이.
//  - 검출 전: 드래그로 ROI 사각형 지정 → 종료 시 검출(빨강 표시).
//  - 검출 후: 빨강 컴포넌트를 탭하면 제외↔포함 토글. 빈 곳을 드래그하면 새 ROI 로 재검출.
//  - 컨트롤 바: 민감도 슬라이더, 제거/취소.
// 좌표는 base 정규로 들고 baseUnitToDisplay 로 화면에 매핑 — 회전/플립/회전보정/크롭과 정합한다.
struct RegionICEOverlay: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject var model: AppModel
    let imageFrame: CGRect

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        ZStack(alignment: .top) {
            previewCanvas
            roiRubberBand
            gestureLayer
            controlBar
        }
    }

    // MARK: 미리보기(빨강 컴포넌트)

    private var previewCanvas: some View {
        Canvas { ctx, _ in
            guard frame.iceBaseSize != nil else { return }
            for comp in frame.icePreview {
                let excluded = frame.iceExcludedIDs.contains(comp.id)
                let color = excluded ? Color.gray.opacity(0.35) : Color.red.opacity(0.6)
                for pt in comp.points {
                    let d = displayPoint(pt)
                    guard imageFrame.contains(d) else { continue }
                    ctx.fill(Path(CGRect(x: d.x - 1.5, y: d.y - 1.5, width: 3, height: 3)), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var roiRubberBand: some View {
        if let s = dragStart, let c = dragCurrent {
            let r = screenRect(s, c)
            Rectangle()
                .strokeBorder(Color.yellow.opacity(0.9), lineWidth: 1.5)
                .background(Color.yellow.opacity(0.06))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)
        }
    }

    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
                    .onChanged { value in
                        if dragStart == nil { dragStart = value.startLocation }
                        dragCurrent = value.location
                    }
                    .onEnded { value in
                        let start = dragStart ?? value.startLocation
                        dragStart = nil; dragCurrent = nil
                        let dist = hypot(value.translation.width, value.translation.height)
                        if dist < 6 {
                            // 탭: 검출 상태면 컴포넌트 토글.
                            if frame.iceActive, !frame.iceIsDetecting {
                                model.toggleRegionComponent(frame, atDisplay: unit(value.location))
                            }
                        } else {
                            // 드래그: 새 ROI 검출.
                            let roi = unitRect(start, value.location)
                            if roi.width > 0.012, roi.height > 0.012 {
                                model.runRegionDetect(frame, displayROI: roi)
                            }
                        }
                    }
            )
    }

    // MARK: 컨트롤 바

    private var controlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope").foregroundStyle(.red)
            if frame.iceIsDetecting {
                ProgressView().controlSize(.small)
                Text("검출 중").font(.caption).foregroundStyle(.secondary)
            } else if frame.iceActive {
                Text(detectSummary).font(.caption).foregroundStyle(.secondary)
                Divider().frame(height: 16)
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $frame.iceSensitivity, in: 0.7...3.0,
                           onEditingChanged: { editing in if !editing { model.redetectRegion(frame) } })
                        .frame(width: 110)
                }
                Divider().frame(height: 16)
                Button(action: { model.cancelRegionICE(frame) }) { Image(systemName: "xmark") }
                    .help("취소").disabled(frame.iceIsRemoving)
                Button(action: { model.commitRegionICE(frame) }) {
                    if frame.iceIsRemoving { ProgressView().controlSize(.small) }
                    else { Label("제거", systemImage: "wand.and.stars") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(frame.iceIsRemoving || !hasSelectable)
            } else {
                Text("결함 영역을 드래그하세요").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 12)
    }

    private var detectSummary: String {
        let total = frame.icePreview.count
        let excluded = frame.iceExcludedIDs.count
        if total == 0 { return "결함 없음" }
        return excluded > 0 ? "결함 \(total)개 (제외 \(excluded))" : "결함 \(total)개"
    }

    private var hasSelectable: Bool {
        frame.icePreview.contains { !frame.iceExcludedIDs.contains($0.id) }
    }

    // MARK: 좌표 변환

    /// base 정규(0..1, y-down) → 화면 픽셀.
    private func displayPoint(_ base: CGPoint) -> CGPoint {
        guard let bs = frame.iceBaseSize else { return .zero }
        let d = frame.imageTransform.baseUnitToDisplay(base, baseSize: bs)
        return CGPoint(x: imageFrame.minX + d.x * imageFrame.width,
                       y: imageFrame.minY + d.y * imageFrame.height)
    }

    private func unit(_ p: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(x: min(max((p.x - imageFrame.minX) / imageFrame.width, 0), 1),
                       y: min(max((p.y - imageFrame.minY) / imageFrame.height, 0), 1))
    }

    private func unitRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        let ua = unit(a), ub = unit(b)
        return CGRect(x: min(ua.x, ub.x), y: min(ua.y, ub.y),
                      width: abs(ua.x - ub.x), height: abs(ua.y - ub.y))
    }

    private func screenRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
