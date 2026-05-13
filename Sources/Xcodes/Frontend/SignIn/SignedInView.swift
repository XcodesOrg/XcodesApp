import SwiftUI

struct SignedInView: View {
    let authenticationStore: AuthenticationStore

    private var username: String {
        authenticationStore.savedUsername ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(username)
            Button("Sign Out", action: authenticationStore.signOut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SignedInView_Previews: PreviewProvider {
    static var previews: some View {
        SignedInView(authenticationStore: AuthenticationStore())
            .previewLayout(.sizeThatFits)
    }
}
