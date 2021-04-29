import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
           
            switch Current.notificationManager.notificationStatus {
                case .shownAndAccepted:
                    Text("Access Granted. You will receive notifications from Xcodes.")
                        .fixedSize(horizontal: false, vertical: true)
                case .shownAndDenied:
                    Text("⚠️ Access Denied ⚠️\n\nPlease open your Notification Settings and select Xcodes if you wish to allow access.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Notification Settings", action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    })
                 
                default:
                    Button("Enable Notifications", action: {
                        Current.notificationManager.requestAccess()
                    }
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NotificationsView()
        }
    }
}
