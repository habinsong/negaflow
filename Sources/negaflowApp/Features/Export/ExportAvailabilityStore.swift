import Combine
import Foundation

@MainActor
final class ExportAvailabilityStore: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    private struct FrameObservation {
        weak var frame: ScanFrame?
        let readiness: AnyCancellable
    }

    private var frameObservations: [UUID: FrameObservation] = [:]

    func observe(_ frames: [ScanFrame]) {
        let observationSetChanged = frames.count != frameObservations.count
            || frames.contains { frame in
                guard let existing = frameObservations[frame.id] else { return true }
                return existing.frame !== frame
            }
        var observations: [UUID: FrameObservation] = [:]
        observations.reserveCapacity(frames.count)

        for frame in frames {
            if let existing = frameObservations[frame.id],
               existing.frame === frame {
                observations[frame.id] = existing
                continue
            }

            let readiness = Publishers.CombineLatest(
                frame.$hasDevelopedOnce.removeDuplicates(),
                frame.$isDeveloping.removeDuplicates()
            )
            .dropFirst()
            .sink { [weak self] _ in
                self?.revision &+= 1
            }
            observations[frame.id] = FrameObservation(
                frame: frame,
                readiness: readiness
            )
        }

        frameObservations = observations
        if observationSetChanged {
            revision &+= 1
        }
    }
}
