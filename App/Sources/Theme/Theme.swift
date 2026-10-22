import SwiftUI
import UIKit

/// The palette of Asabunko. It comes from ZettaStream, with warm tones in place of black and white.
/// Each colour has a dark form, warm charcoal, and a light form, paper.
enum Palette {
    static let background = dynamic(dark: 0x17130F, light: 0xF6F0E4)
    static let surface = dynamic(dark: 0x211C17, light: 0xFBF7EE)
    static let surfaceHigh = dynamic(dark: 0x2C251F, light: 0xEFE6D6)
    static let outline = dynamic(dark: 0x3A3129, light: 0xE2D6C2)
    static let accent = dynamic(dark: 0xE8A87C, light: 0xB8643A)
    static let onAccent = dynamic(dark: 0x2A1A10, light: 0xFFF8EE)
    static let textPrimary = dynamic(dark: 0xF3EADF, light: 0x2B231C)
    static let textSecondary = dynamic(dark: 0xA89B8C, light: 0x7A6B5B)
    static let danger = dynamic(dark: 0xE5746A, light: 0xB23A30)
    /// The space around a page in the reader. It is darker than the background, so that the page stands out.
    static let readerBackground = dynamic(dark: 0x0F0C0A, light: 0xEDE5D6)

    static func uiColor(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: uiColor(dark: dark, light: light))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The corner radius of every card, button, and cover. It is softer than the 8 points of ZettaStream.
let corner: CGFloat = 14

/// The space at the left and the right of the content of a screen.
let gutter: CGFloat = 18

/// Karla, the font of ZettaStream, under the SIL Open Font License.
/// One variable file gives each weight, so the weight goes to the `wght` axis.
enum Karla {
    private static let weightAxis = 0x7767_6874

    /// The size follows Dynamic Type: SwiftUI scales it with `style` each time the setting changes.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom("Karla-Regular", size: size, relativeTo: style).weight(weight)
    }

    static func uiFont(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: "Karla-Regular",
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [weightAxis: weight.axisValue],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

private extension Font.Weight {
    var axisValue: CGFloat {
        switch self {
        case .ultraLight, .thin: 200
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy, .black: 800
        default: 400
        }
    }
}

/// The look that the user chooses in Settings.
enum Appearance: String, CaseIterable, Identifiable {
    case system, dark, paper

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "Same as the device"
        case .dark: "Warm dark"
        case .paper: "Paper"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .paper: .light
        }
    }

    static let key = "appearance"
}

/// The look of every screen and every sheet: the warm background and the chosen appearance.
private struct AsaScreen: ViewModifier {
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    func body(content: Content) -> some View {
        content
            .background(Palette.background.ignoresSafeArea())
            .foregroundStyle(Palette.textPrimary)
            .tint(Palette.accent)
            .preferredColorScheme(appearance.colorScheme)
    }
}

extension View {
    func asaScreen() -> some View {
        modifier(AsaScreen())
    }

    /// A card with a soft fill and a thin outline.
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Palette.outline, lineWidth: 0.5))
    }

    /// A form with the colours of the app in place of the grey of the system.
    func asaForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .font(Karla.font(16))
            .listRowBackground(Palette.surface)
    }
}

/// The main button: a soft pill in the accent colour.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Karla.font(16, .bold))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .foregroundStyle(Palette.onAccent)
            .background(Palette.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
