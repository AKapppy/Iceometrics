import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension Color {
    init(hex: String, fallback: Color = .accentColor) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            self = fallback
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        #if os(macOS)
        guard let color = NSColor(self)
            .usingColorSpace(.sRGB) else {
            return nil
        }

        let redValue = Int((color.redComponent * 255).rounded())
        let greenValue = Int((color.greenComponent * 255).rounded())
        let blueValue = Int((color.blueComponent * 255).rounded())
        #elseif canImport(UIKit)
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return nil
        }

        let redValue = Int((red * 255).rounded())
        let greenValue = Int((green * 255).rounded())
        let blueValue = Int((blue * 255).rounded())
        #else
        return nil
        #endif

        return String(
            format: "#%02X%02X%02X",
            redValue,
            greenValue,
            blueValue
        )
    }
}
