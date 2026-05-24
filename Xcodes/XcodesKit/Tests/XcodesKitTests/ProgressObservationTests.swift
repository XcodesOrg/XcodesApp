import XCTest
@testable import XcodesKit

final class ProgressObservationTests: XCTestCase {
    func testObserveDefaultsToFractionCompletedChanges() {
        let progress = Progress(totalUnitCount: 10)
        let observation = ProgressObservation()
        let expectation = expectation(description: "progress changed")

        observation.observe(progress) { changedProgress in
            XCTAssertEqual(changedProgress.completedUnitCount, 1)
            expectation.fulfill()
        }

        progress.completedUnitCount = 1

        wait(for: [expectation], timeout: 1)
    }

    func testChangesYieldsObservedPropertyChanges() async throws {
        let progress = Progress(totalUnitCount: 10)
        let stream = ProgressObservation.changes(
            for: progress,
            observing: [.fractionCompleted, .localizedAdditionalDescription, .isIndeterminate]
        )

        progress.completedUnitCount = 1

        try await waitForNextValue(in: stream)
    }

    private func waitForNextValue(in stream: AsyncStream<Void>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                guard await iterator.next() != nil else {
                    throw ProgressObservationTestError.streamFinished
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw ProgressObservationTestError.timedOut
            }

            try await group.next()
            group.cancelAll()
        }
    }
}

private enum ProgressObservationTestError: Error {
    case streamFinished
    case timedOut
}
