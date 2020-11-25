import SwiftUI

struct SignInPhoneListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    var phoneNumbers: [String]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Select a trusted phone number to receive a code via SMS: ")
            
            List(phoneNumbers, id: \.self) {
                Text($0)
            }
            .frame(height: 200)
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                Spacer()
                Button("Continue", action: {})
            }
        }
        .padding()
    }
}

struct SignInPhoneListView_Previews: PreviewProvider {
    static var previews: some View {
        SignInPhoneListView(isPresented: .constant(true), phoneNumbers: ["123-456-7890"])
    }
}
