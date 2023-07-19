import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
           
            switch Current.notificationManager.notificationStatus {
                case .shownAndAccepted:
                    Text("AccessGranted")
                        .fixedSize(horizontal: false, vertical: true)
                case .shownAndDenied:
                    Text("AccessDenied")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("NotificationSettings", action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    })
                 
                default:
                    Button("EnableNotifications", action: {
                        Current.notificationManager.requestAccess()
                    })
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
