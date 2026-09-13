import AppKit
import SwiftUI

extension Font {
    static func jetBrainsMono(size: CGFloat) -> Font {
        Font(NSFont.jetBrainsMono(size: size))
    }
}

extension NSFont {
    static func jetBrainsMono(size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont(name: "UbuntuMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
