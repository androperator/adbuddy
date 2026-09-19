import Foundation

public struct AndroidDeviceDisplay: Equatable, Sendable {
    public let id: String
    public let screen: AndroidDeviceScreen
}

/// Reads physical internal displays, excluding external monitors and virtual displays.
public enum AndroidDeviceDisplayParser {
    public static func parse(_ output: String) -> [AndroidDeviceDisplay] {
        let pattern = #"DisplayDeviceInfo\{"[^"]*": uniqueId="([^"]+)", (\d+) x (\d+),.*?, density (\d+),"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var displays: [AndroidDeviceDisplay] = []
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("DisplayDeviceInfo{"),
                  line.contains(", type INTERNAL,"),
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }
            let values = (1...4).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: line) else { return nil }
                return String(line[range])
            }
            guard values.count == 4,
                  !displays.contains(where: { $0.id == values[0] }),
                  let width = Int(values[1]), let height = Int(values[2]),
                  let density = Int(values[3]),
                  let size = AndroidDisplaySize(width: width, height: height),
                  let screen = AndroidDeviceScreen(physicalPixelSize: size, logicalDensityDPI: density) else {
                continue
            }
            displays.append(AndroidDeviceDisplay(id: values[0], screen: screen))
        }
        return displays.sorted {
            let lhs = $0.screen.physicalPixelSize
            let rhs = $1.screen.physicalPixelSize
            return Double(lhs.width) * Double(lhs.height) > Double(rhs.width) * Double(rhs.height)
        }
    }
}
