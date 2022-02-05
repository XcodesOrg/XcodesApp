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
                Color.clear
                    .frame(width: 300, height: 0)
                Label("Unxip Experiment", systemImage: "testtube.2")
                HStack(spacing: 32) {
                    Button(action: {
                        openURL(URL(string: "https://github.com/saagarjha/unxip/")!)
                    }) {
                        Label("Github Repo", systemImage: "link")
                    }
                    .buttonStyle(LinkButtonStyle())
                    
                    Button(action: {
                        openURL(URL(string: "https://github.com/saagarjha/unxip/blob/main/LICENSE")!)
                    }) {
                        Label("License", systemImage: "link")
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
