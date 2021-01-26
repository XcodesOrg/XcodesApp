import SwiftUI

struct AboutView: View {
    let showAcknowledgementsWindow: () -> Void
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    
    var body: some View {
        HStack {
            Image(nsImage: NSApp.applicationIconImage)
            
            VStack(alignment: .leading) {
                Text(Bundle.main.bundleName!)
                    .font(.largeTitle)
                
                Text("Version \(Bundle.main.shortVersion!) (\(Bundle.main.version!))")
                
                Color.clear
                    .frame(width: 300, height: 16)
                
                HStack(spacing: 32) {
                    Button(action: {
                        openURL(URL(string: "https://github.com/RobotsAndPencils/XcodesApp/")!)
                    }) {
                        Label("GitHub Repo", systemImage: "link")
                    }
                    .buttonStyle(LinkButtonStyle())
                    
                    Button(action: showAcknowledgementsWindow) {
                        Label("Acknowledgements", systemImage: "doc")
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                
                Text(Bundle.main.humanReadableCopyright!)
                    .font(.footnote)
            }
        }
        .padding()
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView(showAcknowledgementsWindow: {})
    }
}
