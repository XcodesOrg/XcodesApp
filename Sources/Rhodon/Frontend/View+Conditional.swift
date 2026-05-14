import SwiftUI

extension View {
    @ViewBuilder
    func `if`(_ predicate: Bool, then: (Self) -> some View) -> some View {
        if predicate {
            then(self)
        } else {
            self
        }
    }

    func emittingError(_ error: Binding<Error?>, recoveryHandler: @escaping (Error) -> Void) -> some View {
        modifier(ErrorAlertModifier(error: error, recoveryHandler: recoveryHandler))
    }
}

private struct ErrorAlertModifier: ViewModifier {
    @Binding var error: Error?
    let recoveryHandler: (Error) -> Void

    func body(content: Content) -> some View {
        content.alert(
            isPresented: Binding(
                get: { error != nil },
                set: { isPresented in
                    if !isPresented {
                        error = nil
                    }
                }
            )
        ) {
            let currentError = error
            return Alert(
                title: Text("Error"),
                message: Text(Self.message(for: currentError)),
                dismissButton: .default(Text("OK")) {
                    if let currentError {
                        recoveryHandler(currentError)
                    }
                    error = nil
                }
            )
        }
    }

    private static func message(for error: Error?) -> String {
        guard let error else { return "" }

        if let localizedError = error as? LocalizedError {
            return localizedError.errorDescription
                ?? localizedError.failureReason
                ?? localizedError.recoverySuggestion
                ?? error.localizedDescription
        }

        return error.localizedDescription
    }
}
