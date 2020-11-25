import SwiftUI

struct AppStoreButtonStyle: ButtonStyle {
    var installed: Bool
    var highlighted: Bool
    
    private struct AppStoreButton: View {
        var configuration: ButtonStyle.Configuration
        var installed: Bool
        var highlighted: Bool
        // This seems to magically help the highlight colors update on time
        @SwiftUI.Environment(\.isFocused) var isFocused
        
        var textColor: Color {
            if installed {
                if highlighted {
                    return Color.white
                }
                else {
                    return Color.secondary
                }
            }
            else {
                if highlighted {
                    return Color.accentColor
                }
                else {
                    return Color.white
                }
            }
        }
        
        func background(isPressed: Bool) -> some View {
            Group {
                if installed {
                    EmptyView()
                } else {
                    Capsule()
                        .fill(
                            highlighted ?
                                Color.white :
                                Color.accentColor
                        )
                        .brightness(isPressed ? -0.25 : 0)
                }
            }
        }
        var body: some View {
            configuration.label
                .font(Font.caption.weight(.medium))
                .foregroundColor(textColor)
                .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .frame(minWidth: 80)
                .background(background(isPressed: configuration.isPressed))
                .padding(1)
        }
    }
    
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        AppStoreButton(configuration: configuration, installed: installed, highlighted: highlighted)
    }
}

struct AppStoreButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Button("INSTALLED", action: {})
                .buttonStyle(AppStoreButtonStyle(installed: true, highlighted: false))
                .padding()
            Button("INSTALL", action: {})
                .buttonStyle(AppStoreButtonStyle(installed: false, highlighted: false))
                .padding()
        }
    }
}
