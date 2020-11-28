import AppKit
import AppleAPI
import Combine
import Path
import PromiseKit
import XcodesKit

class AppState: ObservableObject {
    private let list = XcodeList()
    private lazy var installer = XcodeInstaller(configuration: Configuration(), xcodeList: list)
    
    struct XcodeVersion: Identifiable {
        let title: String
        let installState: InstallState
        let selected: Bool
        let path: String?
        var id: String { title }
        var installed: Bool { installState == .installed }
    }
    enum InstallState: Equatable {
        case notInstalled
        case installing(Progress)
        case installed
    }
    
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var allVersions: [XcodeVersion] = []
    
    struct AlertContent: Identifiable {
        var title: String
        var message: String
        var id: String { title + message }
    }
    @Published var error: AlertContent?
    
    @Published var presentingSignInAlert = false
    @Published var secondFactorSessionData: AppleSessionData?
    
    private var cancellables = Set<AnyCancellable>()
    let client = AppleAPI.Client()

    func load() {
//        if list.shouldUpdate {
            update()
//                .done { _ in
//                    self.updateAllVersions()
//                }
//                .catch { error in
//                    self.error = AlertContent(title: "Error", 
//                                              message: error.localizedDescription)
//                }
////        }
//        else {
//            updateAllVersions()
//        }        
    }
    
    func validateSession() -> AnyPublisher<Void, Error> {
        return client.validateSession()
            .handleEvents(receiveCompletion: { completion in 
                if case .failure = completion {
                    self.authenticationState = .unauthenticated
                    self.presentingSignInAlert = true
                }
            })
            .eraseToAnyPublisher()
    }
    
    func login(username: String, password: String) {
        client.login(accountName: username, password: password)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        // TODO: show error
                    }
                }, 
                receiveValue: { authenticationState in 
                    self.authenticationState = authenticationState
                    if case let AuthenticationState.waitingForSecondFactor(option, sessionData) = authenticationState {
                        self.handleTwoFactorOption(option, serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func handleTwoFactorOption(_ option: TwoFactorOption, serviceKey: String, sessionID: String, scnt: String) {
//        Current.logging.log("Two-factor authentication is enabled for this account.\n")
        switch option {
        case let .smsSent(codeLength, phoneNumber):
            break
//            return Result {
//                let code = self.promptForSMSSecurityCode(length: codeLength, for: phoneNumber)
//                return try URLRequest.submitSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, code: code)
//            }
//            .publisher
//            .flatMap { request in
//                return Current.network.dataTask(with: request)
//                    .validateSecurityCodeResponse()
//                    .mapError { $0 as Error }
//            }
//            .flatMap { (data, response) in
//                self.updateSession(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
//            }
//            .eraseToAnyPublisher()
        case let .smsPendingChoice(codeLength, trustedPhoneNumbers):
            break
//            return handleWithPhoneNumberSelection(codeLength: codeLength, trustedPhoneNumbers: trustedPhoneNumbers, serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        case let .codeSent(codeLength):
            self.presentingSignInAlert = false
            self.secondFactorSessionData = AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
//            let code = Current.shell.readLine("""
//        Enter "sms" without quotes to exit this prompt and choose a phone number to send an SMS security code to.
//        Enter the \(codeLength) digit code from one of your trusted devices: 
//        """) ?? ""
//            
//            if code == "sms" {
                // return handleWithPhoneNumberSelection(codeLength: codeLength, trustedPhoneNumbers: authOp, serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
//            }
        }
    }
    
//    func selectPhoneNumberInteractively(from trustedPhoneNumbers: [AuthOptionsResponse.TrustedPhoneNumber]) -> AnyPublisher<AuthOptionsResponse.TrustedPhoneNumber, Swift.Error> {
//        return Result {
//            Current.logging.log("Trusted phone numbers:")
//            trustedPhoneNumbers.enumerated().forEach { (index, phoneNumber) in
//                Current.logging.log("\(index + 1): \(phoneNumber.numberWithDialCode)")
//            }
//
//            let possibleSelectionNumberString = Current.shell.readLine("Select a trusted phone number to receive a code via SMS: ")
//            guard
//                let selectionNumberString = possibleSelectionNumberString,
//                let selectionNumber = Int(selectionNumberString) ,
//                trustedPhoneNumbers.indices.contains(selectionNumber - 1)
//            else {
//                throw AuthenticationError.invalidPhoneNumberIndex(min: 1, max: trustedPhoneNumbers.count, given: possibleSelectionNumberString)
//            }
//
//            return trustedPhoneNumbers[selectionNumber - 1]
//        }
//        .publisher
//        .catch { error -> AnyPublisher<AuthOptionsResponse.TrustedPhoneNumber, Swift.Error> in
//            guard case AuthenticationError.invalidPhoneNumberIndex = error else { 
//                return Fail<AuthOptionsResponse.TrustedPhoneNumber, Swift.Error>(error: error).eraseToAnyPublisher() 
//            }
//            Current.logging.log("\(error.localizedDescription)\n")
//            return self.selectPhoneNumberInteractively(from: trustedPhoneNumbers)
//        }
//        .eraseToAnyPublisher()
//    }
//    
//    func promptForSMSSecurityCode(length: Int, for trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber) -> SecurityCode {
//        let code = Current.shell.readLine("Enter the \(length) digit code sent to \(trustedPhoneNumber.numberWithDialCode): ") ?? ""
//        return .sms(code: code, phoneNumberId: trustedPhoneNumber.id)
//    }
    
//    func handleWithPhoneNumberSelection(codeLength: Int, trustedPhoneNumbers: [AuthOptionsResponse.TrustedPhoneNumber]?, serviceKey: String, sessionID: String, scnt: String) -> AnyPublisher<AuthenticationState, Error> {
//        // I don't think this should ever be nil or empty, because 2FA requires at least one trusted phone number,
//        // but if it is nil or empty it's better to inform the user so they can try to address it instead of crashing.
//        guard let trustedPhoneNumbers = trustedPhoneNumbers, trustedPhoneNumbers.isEmpty == false else {
//            return Fail(error: AuthenticationError.noTrustedPhoneNumbers)
//                .eraseToAnyPublisher()
//        }
//        
//        return selectPhoneNumberInteractively(from: trustedPhoneNumbers)
//            .flatMap { trustedPhoneNumber in
//                Current.network.dataTask(with: try URLRequest.requestSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, trustedPhoneID: trustedPhoneNumber.id))
//                    .map { _ in
//                        self.promptForSMSSecurityCode(length: codeLength, for: trustedPhoneNumber)
//                    }
//            }
//            .flatMap { code in
//                Current.network.dataTask(with: try URLRequest.submitSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, code: code))
//                    .validateSecurityCodeResponse()
//            }
//            .flatMap { (data, response) -> AnyPublisher<AuthenticationState, Error> in
//                self.updateSession(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
//            }
//            .eraseToAnyPublisher()
//    }
    
    func submit2FACode(_ code: String, sessionData: AppleSessionData) {
        client.submitSecurityCode(code, sessionData: sessionData)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case let .failure(error):
                        self.error = AlertContent(title: "Error logging in", message: error.legibleLocalizedDescription)
                    case .finished:
                        if case .authenticated = self.authenticationState {
                            self.presentingSignInAlert = false
                            self.secondFactorSessionData = nil
                        }
                    }
                },
                receiveValue: { authenticationState in
                    self.authenticationState = authenticationState
                }
            )
            .store(in: &cancellables)
    }
    
    public func update() -> AnyPublisher<[Xcode], Error> {
//        return firstly { () -> Promise<Void> in
//            validateSession()
//        }
//        .then { () -> Promise<[Xcode]> in
//            self.list.update()
//        }
        Just<[Xcode]>([])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    private func updateAllVersions() {
        let installedXcodes = Current.files.installedXcodes(Path.root/"Applications")
        var allXcodeVersions = list.availableXcodes.map { $0.version }
        for installedXcode in installedXcodes {
            // If an installed version isn't listed online, add the installed version
            if !allXcodeVersions.contains(where: { version in
                version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version)
            }) {
                allXcodeVersions.append(installedXcode.version)
            }
            // If an installed version is the same as one that's listed online which doesn't have build metadata, replace it with the installed version with build metadata
            else if let index = allXcodeVersions.firstIndex(where: { version in
                version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version) &&
                version.buildMetadataIdentifiers.isEmpty
            }) {
                allXcodeVersions[index] = installedXcode.version
            }
        }

        allVersions = allXcodeVersions
            .sorted(by: >)
            .map { xcodeVersion in
                let installedXcode = installedXcodes.first(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) })
                return XcodeVersion(
                    title: xcodeVersion.xcodeDescription, 
                    installState: installedXcodes.contains(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) }) ? .installed : .notInstalled,
                    selected: installedXcode?.path.string.contains("11.4.1") == true, 
                    path: installedXcode?.path.string
                )
            }
    }
    
    func install(id: String) {
        // TODO:
    }
    
    func uninstall(id: String) {
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version.xcodeDescription == id }) else { return }
        // TODO: would be nice to have a version of this method that just took the InstalledXcode
        installer.uninstallXcode(installedXcode.version.xcodeDescription, destination: Path.root/"Applications")
            .done {
                
            }
            .catch { error in
            
            }
    }
    
    func reveal(id: String) {
        // TODO: show error if not
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version.xcodeDescription == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installedXcode.path.url])
    }

    func select(id: String) {
        // TODO:
    }
}
