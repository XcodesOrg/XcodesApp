import SwiftUI

struct AboutView: View {
    @SwiftUI.Environment(\.openWindow) private var openWindow
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction

    var body: some View {
        HStack {
            Image("xcode")
                .resizable()
                .frame(width: 128, height: 128)

            VStack(alignment: .leading) {
                Text(Bundle.main.bundleName!)
                    .font(.largeTitle)

                Text("Version \(Bundle.main.shortVersion!) (\(Bundle.main.version!))")

                HStack(spacing: 32) {
                    Button(action: {
                        openURL(URL(string: "https://github.com/RobotsAndPencils/XcodesApp/")!)
                    }, label: {
                        Label("GithubRepo", systemImage: "link")
                    })
                    .buttonStyle(LinkButtonStyle())

                    Button(action: { openWindow(id: "acknowledgements") }, label: {
                        Label("Acknowledgements", systemImage: "doc")
                    })
                    .buttonStyle(LinkButtonStyle())
                }
                Color.clear
                    .frame(width: 300, height: 0)
                Label("UnxipExperiment", systemImage: "lightbulb")
                HStack(spacing: 32) {
                    Button(action: {
                        openURL(URL(string: "https://github.com/saagarjha/unxip/")!)
                    }, label: {
                        Label("GithubRepo", systemImage: "link")
                    })
                    .buttonStyle(LinkButtonStyle())

                    Button(action: {
                        openURL(URL(string: "https://github.com/saagarjha/unxip/blob/main/LICENSE")!)
                    }, label: {
                        Label("License", systemImage: "link")
                    })
                    .buttonStyle(LinkButtonStyle())
                }
                HStack {
                    Text(Bundle.main.humanReadableCopyright!)
                        .font(.footnote)
                    Button(action: {
                        openURL(URL(string: "https://opencollective.com/xcodesapp")!)
                    }, label: {
                        HStack {
                            Image(systemName: "heart.circle")
                            Text("Support.Xcodes")
                        }
                    })
                }
            }
        }
        .padding()
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
