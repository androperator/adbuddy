import AppKit

@MainActor
enum ADBuddyAboutPanel {
    static func present() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ADBuddy",
            .credits: credits
        ])
    }

    private static let credits: NSAttributedString = {
        let value = NSMutableAttributedString(string: "Written by ")
        value.append(
            NSAttributedString(
                string: "@chrismlacy",
                attributes: [
                    .link: URL(string: "https://x.com/chrismlacy")!,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            )
        )
        return value
    }()
}
