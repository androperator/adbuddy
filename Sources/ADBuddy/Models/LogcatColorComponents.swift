import AppKit
import SwiftUI

struct LogcatColorComponents: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        precondition(Self.areValid(red: red, green: green, blue: blue, alpha: alpha))
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(color: Color) {
        let color = NSColor(color)
        guard let convertedColor = color.usingColorSpace(.sRGB) else {
            return nil
        }

        let red = Double(convertedColor.redComponent)
        let green = Double(convertedColor.greenComponent)
        let blue = Double(convertedColor.blueComponent)
        let alpha = Double(convertedColor.alphaComponent)
        guard Self.areValid(red: red, green: green, blue: blue, alpha: alpha) else {
            return nil
        }

        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let alpha = try container.decode(Double.self, forKey: .alpha)
        guard Self.areValid(red: red, green: green, blue: blue, alpha: alpha) else {
            throw DecodingError.dataCorruptedError(
                forKey: .red,
                in: container,
                debugDescription: "Logcat color components must be finite values between zero and one."
            )
        }

        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    private static func areValid(red: Double, green: Double, blue: Double, alpha: Double) -> Bool {
        [red, green, blue, alpha].allSatisfy { value in
            value.isFinite && (0...1).contains(value)
        }
    }
}

extension LogcatPriority {
    var displayName: String {
        switch self {
        case .verbose:
            "Verbose"
        case .debug:
            "Debug"
        case .info:
            "Info"
        case .warn:
            "Warn"
        case .error:
            "Error"
        case .assert:
            "Assert"
        }
    }

    static let defaultColors: [LogcatPriority: LogcatColorComponents] = [
        .verbose: LogcatColorComponents(red: 0.48, green: 0.49, blue: 0.51),
        .debug: LogcatColorComponents(red: 0.22, green: 0.60, blue: 0.88),
        .info: LogcatColorComponents(red: 0.24, green: 0.67, blue: 0.39),
        .warn: LogcatColorComponents(red: 0.76, green: 0.52, blue: 0.13),
        .error: LogcatColorComponents(red: 0.84, green: 0.25, blue: 0.24),
        .assert: LogcatColorComponents(red: 0.55, green: 0.10, blue: 0.12)
    ]
}
