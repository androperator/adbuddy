import XCTest
@testable import ADBuddyCore

final class AndroidDeviceDisplayParserTests: XCTestCase {
    func testReadsBothFoldableScreensIncludingThePoweredOffCover() {
        let output = """
          DisplayDeviceInfo{"Built-in Screen": uniqueId="local:1", 1080 x 2364, modeId 2, supportedModes [{width=1080, height=2364}], density 390, 390.0 x 390.0 dpi, type INTERNAL, state OFF}
          DisplayDeviceInfo{"Built-in Screen": uniqueId="local:0", 2076 x 2152, modeId 1, supportedModes [{width=2076, height=2152}], density 390, 390.0 x 390.0 dpi, type INTERNAL, state ON}
        """
        let displays = AndroidDeviceDisplayParser.parse(output)
        XCTAssertEqual(displays.map(\.id), ["local:0", "local:1"])
        XCTAssertEqual(displays.first?.screen.dpSize, AndroidDisplaySize(width: 852, height: 883))
        XCTAssertEqual(displays.last?.screen.dpSize, AndroidDisplaySize(width: 443, height: 970))
        XCTAssertEqual(displays.last?.screen.physicalPixelSize, AndroidDisplaySize(width: 1080, height: 2364))
    }

    func testIgnoresExternalMalformedAndRepeatedDisplays() {
        let internalDisplay = "DisplayDeviceInfo{\"Screen\": uniqueId=\"local:0\", 1080 x 2400, modeId 1, density 420, type INTERNAL, state ON}"
        let output = [
            internalDisplay, internalDisplay,
            internalDisplay.replacingOccurrences(of: "type INTERNAL", with: "type EXTERNAL"),
            internalDisplay.replacingOccurrences(of: "density 420", with: "density 0").replacingOccurrences(of: "local:0", with: "local:2"),
            "DisplayDeviceInfo{unrecognized format}",
        ].joined(separator: "\n")
        XCTAssertEqual(AndroidDeviceDisplayParser.parse(output).count, 1)
        XCTAssertTrue(AndroidDeviceDisplayParser.parse("Permission denied").isEmpty)
    }
}
