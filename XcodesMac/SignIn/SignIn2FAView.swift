import SwiftUI
import AppleAPI

struct SignIn2FAView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var code: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Enter the \(6) digit code from one of your trusted devices:")
            
            HStack {
                TextField("\(6) digit code", text: $code)
            }
            
            HStack {
                Button("Cancel", action: { isPresented = false  })
                Button("Send SMS", action: {})
                Spacer()
                Button("Continue", action: {})
            }
        }
        .padding()
    }
}

struct SignIn2FAView_Previews: PreviewProvider {
    static var previews: some View {
        SignIn2FAView(isPresented: .constant(true))
            .environmentObject(AppState())
    }
}
