import AppKit
import CoreText

enum BundledFonts {
    static func register() {
        let fonts = [
            ("Fonts/JetBrainsMono", "JetBrainsMono-Regular"),
            ("Fonts/JetBrainsMono", "JetBrainsMono-Bold"),
            ("Fonts/JetBrainsMono", "JetBrainsMono-Italic"),
            ("Fonts/UbuntuMono", "UbuntuMono-Regular"),
            ("Fonts/UbuntuMono", "UbuntuMono-Bold"),
            ("Fonts/UbuntuMono", "UbuntuMono-Italic")
        ]

        for (directory, name) in fonts {
            guard let url = Bundle.main.url(
                forResource: name,
                withExtension: "ttf",
                subdirectory: directory
            ) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
