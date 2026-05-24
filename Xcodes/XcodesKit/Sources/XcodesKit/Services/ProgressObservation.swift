import Foundation
import os

public enum ProgressObservedProperty: Sendable, Hashable {
    case fractionCompleted
    case localizedAdditionalDescription
    case isIndeterminate
}

public final class ProgressObservation: Sendable {
    private let observations = OSAllocatedUnfairLock(initialState: [NSKeyValueObservation]())

    public init() {}

    deinit {
        invalidate()
    }

    public func observe(_ progress: Progress, onChange: @escaping @Sendable (Progress) -> Void) {
        observe(progress, observing: [.fractionCompleted], onChange: onChange)
    }

    public func observe(_ progress: Progress, observing properties: Set<ProgressObservedProperty>, onChange: @escaping @Sendable (Progress) -> Void) {
        let observations = properties.sortedForObservation().map { property in
            switch property {
            case .fractionCompleted:
                progress.observe(\.fractionCompleted) { progress, _ in
                    onChange(progress)
                }
            case .localizedAdditionalDescription:
                progress.observe(\.localizedAdditionalDescription) { progress, _ in
                    onChange(progress)
                }
            case .isIndeterminate:
                progress.observe(\.isIndeterminate) { progress, _ in
                    onChange(progress)
                }
            }
        }

        let previousObservations = self.observations.withLock {
            let previousObservations = $0
            $0 = observations
            return previousObservations
        }

        for observation in previousObservations {
            observation.invalidate()
        }
    }

    public static func changes(
        for progress: Progress,
        observing properties: Set<ProgressObservedProperty> = [.fractionCompleted]
    ) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let observation = ProgressObservation()

        observation.observe(progress, observing: properties) { _ in
            continuation.yield()
        }

        continuation.onTermination = { _ in
            observation.invalidate()
        }

        return stream
    }

    public func invalidate() {
        let observations = self.observations.withLock {
            let observations = $0
            $0 = []
            return observations
        }

        for observation in observations {
            observation.invalidate()
        }
    }
}

private extension ProgressObservedProperty {
    var sortOrder: Int {
        switch self {
        case .fractionCompleted:
            0
        case .localizedAdditionalDescription:
            1
        case .isIndeterminate:
            2
        }
    }
}

private extension Set where Element == ProgressObservedProperty {
    func sortedForObservation() -> [ProgressObservedProperty] {
        sorted { $0.sortOrder < $1.sortOrder }
    }
}
