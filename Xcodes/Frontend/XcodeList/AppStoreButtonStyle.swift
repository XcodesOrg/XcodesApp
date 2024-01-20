import SwiftUI

struct AppStoreButtonStyle: ButtonStyle {
    var primary: Bool
    var highlighted: Bool
    
    private struct AppStoreButton: View {
        @SwiftUI.Environment(\.isEnabled) var isEnabled
        var configuration: ButtonStyle.Configuration
        var primary: Bool
        var highlighted: Bool
        
        var textColor: Color {
            if isEnabled {
                if primary {
                    if highlighted {
                        return Color.accentColor
                    }
                    else {
                        return Color.white
                    }
                }
                else {
                    return Color.accentColor
                }
            } else {
                if primary {
                    if highlighted {
                        return Color(.disabledControlTextColor)
                    }
                    else {
                        return Color.white
                    }
                }
                else {
                    if highlighted {
                        return Color.white
                    }
                    else {
                        return Color(.disabledControlTextColor)
                    }
                }
            }
        }
        
        func background(isPressed: Bool) -> some View {
            Group {
                if isEnabled {
                    if primary {
                        Capsule()
                            .fill(
                                highlighted ?
                                    Color.white :
                                    Color.accentColor
                            )
                            .brightness(isPressed ? -0.25 : 0)
                    } else {
                        Capsule()
                            .fill(
                                Color(NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
                            )
                            .brightness(isPressed ? -0.25 : 0)
                    }
                } else {
                    if primary {
                        Capsule()
                            .fill(
                                highlighted ?
                                    Color.white :
                                    Color(.disabledControlTextColor)
                            )
                            .brightness(isPressed ? -0.25 : 0)
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        var body: some View {
            configuration.label
                .font(Font.caption.weight(.bold))
                .foregroundColor(textColor)
                .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .frame(minWidth: 65)
                .background(background(isPressed: configuration.isPressed))
                .padding(1)
        }
    }
    
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        AppStoreButton(configuration: configuration, primary: primary, highlighted: highlighted)
    }
}

struct AppStoreButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach([ColorScheme.light, .dark], id: \.self) { colorScheme in
                Group {
                    Button("OPEN".hideInLocalizations, action: {})
                        .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: false))
                        .padding()
                        .background(Color(.textBackgroundColor))
                        .previewDisplayName("Primary")
                    Button("OPEN".hideInLocalizations, action: {})
                        .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: true))
                        .padding()
                        .background(Color(.controlAccentColor))
                        .previewDisplayName("Primary, Highlighted")
                    Button("OPEN".hideInLocalizations, action: {})
                        .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: false))
                        .padding()
                        .disabled(true)
                        .background(Color(.textBackgroundColor))
                        .previewDisplayName("Primary, Disabled")
                    Button("INSTALL".hideInLocalizations, action: {})
                        .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
                        .padding()
                        .background(Color(.textBackgroundColor))
                        .previewDisplayName("Secondary")
                    Button("INSTALL".hideInLocalizations, action: {})
                        .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: true))
                        .padding()
                        .background(Color(.controlAccentColor))
                        .previewDisplayName("Secondary, Highlighted")
                    Button("INSTALL".hideInLocalizations, action: {})
                        .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
                        .padding()
                        .disabled(true)
                        .background(Color(.textBackgroundColor))
                        .previewDisplayName("Secondary, Disabled")
                }
                .environment(\.colorScheme, colorScheme)
            }
        }
    }
}
