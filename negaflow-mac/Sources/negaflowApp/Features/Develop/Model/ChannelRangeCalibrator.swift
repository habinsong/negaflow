import Foundation
import Chromabase

/// 롤 교정의 순수 규칙. 한 묶음(물리 롤 또는 같은 스캔 폴더)의 프레임이 잰 채널 범위 모양에서
/// 그 묶음의 교정값 하나를 정한다. 프레임·카탈로그·렌더를 모르므로 값만으로 시험한다.
enum ChannelRangeCalibrator {
    enum Container: Hashable {
        case roll(UUID)
        case folder(String)
    }

    /// 같은 장치·필름의 프레임이 모이는 단위. 스캐너 TIFF 와 가져온 파일은 센서 경로가 달라 섞지 않는다.
    struct Group: Hashable {
        var container: Container
        var source: FrameSource
    }

    struct Member {
        var shape: SIMD3<Double>?
        /// 이미 `params.channelRange` 로 찍혀 있는 값.
        var stamped: SIMD3<Double>?
        /// 가상 사본은 원본과 같은 사진이라 측정 표본으로 두 번 세지 않는다.
        var contributesShape: Bool
    }

    /// 묶음의 폴더 키. 물리 롤에 속하면 롤이, 아니면 원본이 놓인 폴더가 묶음이다.
    static func group(
        rollID: UUID?, sourceFolder: String, source: FrameSource
    ) -> Group {
        Group(container: rollID.map(Container.roll) ?? .folder(sourceFolder), source: source)
    }

    /// 묶음의 교정값. 이미 찍힌 값이 있으면 그것을 따른다(가장 많은 값, 동률이면 앞선 값) — 같은
    /// 롤 안에서 프레임마다 값이 갈라지지 않고, 찍힌 뒤 표본이 늘어도 그림이 움직이지 않는다. 없으면
    /// 측정 표본의 중앙값(`ChannelRangeCalibration.combine`)이고, 표본이 모자라면 nil 이다.
    static func resolve(_ members: [Member]) -> SIMD3<Double>? {
        var tally: [(value: SIMD3<Double>, count: Int)] = []
        for value in members.compactMap(\.stamped) {
            if let index = tally.firstIndex(where: { $0.value == value }) {
                tally[index].count += 1
            } else {
                tally.append((value, 1))
            }
        }
        if let best = tally.max(by: { $0.count < $1.count }) { return best.value }
        return ChannelRangeCalibration.combine(
            members.filter(\.contributesShape).compactMap(\.shape)
        )
    }
}
