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
                
                Text(String(format: localizeString("VersionWithBuild"), Bundle.main.shortVersion!, Bundle.main.version!))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                
                Divider()
                    .frame(width: 300, height: 0)
                    .opacity(0.125)
                HStack(spacing: 32) {
                    Button(action: {
                        openURL(URL(string: "https://github.com/RobotsAndPencils/XcodesApp/")!)
                    }) {
                        Label("GithubRepo", systemImage: "link")
                    }
                    .buttonStyle(LinkButtonStyle())
                    
                    Button(action: showAcknowledgementsWindow) {
                        Label("Acknowledgements", systemImage: "doc")
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                
                Divider()
                    .frame(width: 300, height: 0)
                    .opacity(0.5)
                
                Label("UnxipExperiment", systemImage: "lightbulb")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                HStack(spacing: 32) {
                    Link(destination: URL(
                        string: "https://github.com/saagarjha/unxip/"
                    )!,
                    label: {
                        Label("GithubRepo", systemImage: "link")
                    })
                    
                    Link(destination: URL(
                        string: "https://github.com/saagarjha/unxip/blob/main/LICENSE"
                    )!,
                    label: {
                        Label("License", systemImage: "link")
                    })
                    .buttonStyle(.link)
                }
                
                Divider()
                    .frame(width: 300, height: 0)
                Text(Bundle.main.humanReadableCopyright!)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
