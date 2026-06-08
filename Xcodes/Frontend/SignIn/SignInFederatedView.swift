import SwiftUI
import XcodesLoginKit

struct SignInFederatedView: View {
    @EnvironmentObject var appState: AppState
    let federationResponse: FederationResponse
    @State private var callbackURLString = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SignInWithApple")
                .bold()
                .padding(.vertical)

            Text("This Apple ID uses federated authentication via \(organizationName).")
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Browser") {
                if let idpURL = federationResponse.idpURL {
                    NSWorkspace.shared.open(idpURL)
                }
            }
            .disabled(federationResponse.idpURL == nil)

            TextField("Paste redirected URL", text: $callbackURLString)

            if appState.authError != nil {
                Text(appState.authError?.legibleLocalizedDescription ?? "")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    appState.authError = nil
                    appState.presentedSheet = nil
                }
                .keyboardShortcut(.cancelAction)

                ProgressButton(
                    isInProgress: appState.isProcessingAuthRequest,
                    action: { appState.submitFederatedAuthenticationCallback(callbackURLString) },
                    label: {
                        Text("Next")
                    }
                )
                .disabled(callbackURLString.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .frame(height: 25)
        }
        .padding()
    }

    private var organizationName: String {
        let orgName = federationResponse.federatedAuthIntro?.orgName ?? "your organization"
        if let idpName = federationResponse.federatedAuthIntro?.idpName {
            return "\(orgName) (\(idpName))"
        }
        return orgName
    }
}

struct SignInFederatedView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        SignInFederatedView(
            federationResponse: FederationResponse(
                federated: true,
                federatedIdpRequest: FederatedIdpRequest(
                    idPUrl: "https://login.microsoftonline.com/test-tenant/oauth2/authorize",
                    requestParams: ["login_hint": "test@example.com"],
                    httpMethod: "GET"
                ),
                federatedAuthIntro: FederatedAuthIntro(
                    orgName: "Test Corp",
                    idpName: "Microsoft Entra",
                    idpUrl: nil,
                    orgType: nil,
                    accountManagementUrl: nil
                )
            )
        )
        .environmentObject(AppState())
        .previewLayout(.sizeThatFits)
    }
}
