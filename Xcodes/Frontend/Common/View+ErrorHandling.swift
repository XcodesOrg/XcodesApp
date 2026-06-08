import SwiftUI

enum ErrorCategory: Equatable {
    case nonRecoverable
    case recoverable(recoveryOption: RecoveryOption)
    case requiresSignout
}

protocol CategorizedError: Error {
    var category: ErrorCategory { get }
}

extension Error {
    func resolveCategory() -> ErrorCategory {
        guard let categorized = self as? CategorizedError else {
            return .nonRecoverable
        }

        return categorized.category
    }
}

struct RecoveryOption: Identifiable, Equatable, CustomStringConvertible {
    let id: String
    let description: String

    init(id: String, description: String) {
        self.id = id
        self.description = description
    }
}

extension RecoveryOption {
    static let retry = RecoveryOption(id: "com.xcodesorg.Xcodes.retry", description: "Retry")
}

@MainActor
protocol ErrorHandler: Sendable {
    func handle<T: View>(
        _ error: Binding<Error?>,
        in view: T,
        recoveryHandler: @escaping (RecoveryOption) -> Void,
        signOutHandler: @escaping () -> Void
    ) -> AnyView
}

struct AlertErrorHandler: ErrorHandler {
    private let id = UUID()

    func handle<T: View>(
        _ error: Binding<Error?>,
        in view: T,
        recoveryHandler: @escaping (RecoveryOption) -> Void,
        signOutHandler: @escaping () -> Void
    ) -> AnyView {
        guard error.wrappedValue?.resolveCategory() != .requiresSignout else {
            signOutHandler()
            return AnyView(view)
        }

        let binding = Binding(
            get: {
                error.wrappedValue.map {
                    Presentation(
                        id: id,
                        error: $0,
                        recoveryHandler: { recoveryOption in
                            DispatchQueue.main.async {
                                recoveryHandler(recoveryOption)
                            }
                        }
                    )
                }
            },
            set: { possiblePresentation in
                if possiblePresentation == nil {
                    error.wrappedValue = nil
                }
            }
        )

        return AnyView(view.alert(item: binding, content: makeAlert))
    }
}

private extension AlertErrorHandler {
    struct Presentation: Identifiable {
        let id: UUID
        let error: Error
        let recoveryHandler: (RecoveryOption) -> Void
    }

    func makeAlert(for presentation: Presentation) -> Alert {
        let error = presentation.error

        switch error.resolveCategory() {
        case let .recoverable(recoveryOption):
            return Alert(
                title: Text("An error occurred"),
                message: Text(error.localizedDescription),
                primaryButton: .default(Text("Dismiss")),
                secondaryButton: .default(
                    Text(recoveryOption.description),
                    action: { presentation.recoveryHandler(recoveryOption) }
                )
            )
        case .nonRecoverable:
            return Alert(
                title: Text("An error occurred"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("Dismiss"))
            )
        case .requiresSignout:
            assertionFailure("Should have signed out")
            return Alert(title: Text("Signing out..."))
        }
    }
}

private struct ErrorHandlerEnvironmentKey: EnvironmentKey {
    static let defaultValue: any ErrorHandler = AlertErrorHandler()
}

private struct SignOutHandlerEnvironmentKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var errorHandler: any ErrorHandler {
        get { self[ErrorHandlerEnvironmentKey.self] }
        set { self[ErrorHandlerEnvironmentKey.self] = newValue }
    }

    var signOutHandler: @MainActor @Sendable () -> Void {
        get { self[SignOutHandlerEnvironmentKey.self] }
        set { self[SignOutHandlerEnvironmentKey.self] = newValue }
    }
}

@MainActor
struct ErrorEmittingViewModifier: ViewModifier {
    @SwiftUI.Environment(\.errorHandler) private var errorHandler: any ErrorHandler
    @SwiftUI.Environment(\.signOutHandler) private var signOutHandler: @MainActor @Sendable () -> Void

    var error: Binding<Error?>
    var recoveryHandler: (RecoveryOption) -> Void

    func body(content: Content) -> some View {
        errorHandler.handle(
            error,
            in: content,
            recoveryHandler: recoveryHandler,
            signOutHandler: signOutHandler
        )
    }
}

extension View {
    func handlingErrors(using handler: any ErrorHandler) -> some View {
        environment(\.errorHandler, handler)
    }

    func emittingError(
        _ error: Binding<Error?>,
        recoveryHandler: @escaping (RecoveryOption) -> Void
    ) -> some View {
        modifier(ErrorEmittingViewModifier(
            error: error,
            recoveryHandler: recoveryHandler
        ))
    }
}
