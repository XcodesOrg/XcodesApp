import SwiftUI

struct SignInSMSView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var code: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Enter the \(6) digit code sent to \("phone number"): ")
            
            HStack {
                TextField("\(6) digit code", text: $code)
            }
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                Spacer()
                Button("Continue", action: {})
            }
        }
        .padding()
    }
}

struct SignInSMSView_Previews: PreviewProvider {
    static var previews: some View {
        SignInSMSView(isPresented: .constant(true))
            .environmentObject(AppState())
    }
}
