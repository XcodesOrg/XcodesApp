import SwiftUI

struct SignedInView: View {
    @EnvironmentObject var appState: AppState

    private var username: String {
        appState.savedUsername ?? ""
    }

    var body: some View {
        HStack(alignment:.top, spacing: 10) {
            Text(username)
            Button("Sign Out", action: appState.signOut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SignedInView_Previews: PreviewProvider {
    static var previews: some View {
        SignedInView()
            .previewLayout(.sizeThatFits)
    }
}
