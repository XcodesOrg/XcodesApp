import Foundation
import os

public final class OneShotContinuation<Value: Sendable>: Sendable {
    private enum State: Sendable {
        case pending(CheckedContinuation<Value, Error>?)
        case completed(Result<Value, Error>)
    }

    private let state = OSAllocatedUnfairLock(initialState: State.pending(nil))

    public init() {}

    public func value(
        onCancel: @escaping @Sendable () -> Void = {},
        start: @Sendable () throws -> Void
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if setContinuation(continuation) {
                    do {
                        try start()
                    } catch {
                        resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            onCancel()
            resume(throwing: CancellationError())
        }
    }

    @discardableResult
    public func setContinuation(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        let result = state.withLock {
            switch $0 {
            case .pending:
                $0 = .pending(continuation)
                return nil as Result<Value, Error>?
            case .completed(let result):
                return result
            }
        }

        guard let result else { return true }
        continuation.resume(with: result)
        return false
    }

    public func resume(with result: Result<Value, Error>) {
        let continuation = state.withLock {
            switch $0 {
            case .pending(let continuation):
                $0 = .completed(result)
                return continuation
            case .completed:
                return nil
            }
        }

        continuation?.resume(with: result)
    }

    public func resume(throwing error: Error) {
        resume(with: .failure(error))
    }
}

extension OneShotContinuation where Value == Void {
    public func resume() {
        resume(with: .success(()))
    }
}
