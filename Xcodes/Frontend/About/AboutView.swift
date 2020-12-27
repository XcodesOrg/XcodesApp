import SwiftUI

struct AboutView: View {
    let showAcknowledgementsWindow: () -> Void
    
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
                        NSWorkspace.shared.open(URL(string: "https://github.com/RobotsAndPencils/XcodesApp/")!)
                    }) {
                        Label("GitHub Repo", systemImage: "link")
                    }
                    .buttonStyle(LinkButtonStyle())
                    
                    Button(action: showAcknowledgementsWindow) {
                        Label("Acknowledgements", systemImage: "doc")
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                
                Text("Copyright © 2020 Robots and Pencils")
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
