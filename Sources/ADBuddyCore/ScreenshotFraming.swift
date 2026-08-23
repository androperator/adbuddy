import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ScreenshotFramingOptions: Equatable, Sendable {
    public static let disabled = ScreenshotFramingOptions(
        addsFrame: false,
        alsoSavesOriginal: false,
        overlaysDeviceDetails: false
    )

    public let addsFrame: Bool
    public let alsoSavesOriginal: Bool
    public let overlaysDeviceDetails: Bool

    public init(
        addsFrame: Bool,
        alsoSavesOriginal: Bool,
        overlaysDeviceDetails: Bool = false
    ) {
        self.addsFrame = addsFrame
        self.alsoSavesOriginal = addsFrame && alsoSavesOriginal
        self.overlaysDeviceDetails = overlaysDeviceDetails
    }
}

struct ScreenshotDeviceDetailsOverlayRenderer {
    static func overlay(
        deviceDetails: AndroidDeviceDetails,
        on screenshotData: Data
    ) -> Data? {
        guard let screenshot = PNGImageCodec.image(from: screenshotData),
              let context = ImageCanvas.makeContext(width: screenshot.width, height: screenshot.height) else {
            return nil
        }

        context.draw(screenshot, in: CGRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height))

        let shortestSide = CGFloat(min(screenshot.width, screenshot.height))
        let outerMargin: CGFloat = 4
        let labelPadding = max(10, shortestSide * 0.012)
        let fontSize = max(20, shortestSide * 0.032)
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("HelveticaNeue-Medium" as CFString, fontSize, nil)
        let text = NSAttributedString(
            string: deviceDetails.screenshotOverlayText,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        let textBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let labelRect = CGRect(
            x: outerMargin,
            y: CGFloat(screenshot.height) - outerMargin - textBounds.height - labelPadding * 2,
            width: textBounds.width + labelPadding * 2,
            height: textBounds.height + labelPadding * 2
        )

        context.setFillColor(CGColor(gray: 0, alpha: 0.7))
        context.addPath(CGPath(
            roundedRect: labelRect,
            cornerWidth: labelPadding,
            cornerHeight: labelPadding,
            transform: nil
        ))
        context.fillPath()
        context.textPosition = CGPoint(
            x: labelRect.minX + labelPadding - textBounds.origin.x,
            y: labelRect.minY + labelPadding - textBounds.origin.y
        )
        CTLineDraw(line, context)

        guard let output = context.makeImage() else {
            return nil
        }
        return PNGImageCodec.data(from: output)
    }
}

public struct ScreenshotCaptureOutput: Equatable, Sendable {
    public let primaryFileURL: URL
    public let originalFileURL: URL?

    public init(primaryFileURL: URL, originalFileURL: URL?) {
        self.primaryFileURL = primaryFileURL
        self.originalFileURL = originalFileURL
    }

    public var savedFileURLs: [URL] {
        if let originalFileURL {
            [originalFileURL, primaryFileURL]
        } else {
            [primaryFileURL]
        }
    }
}

struct ScreenshotFrameRenderer: Sendable {
    private let adbPath: String
    private let sdkRootURL: URL?
    private let processRunner: any ProcessRunning

    init(
        adbPath: String,
        sdkRootPath: String?,
        processRunner: any ProcessRunning
    ) {
        self.adbPath = adbPath
        sdkRootURL = sdkRootPath.map(URL.init(fileURLWithPath:))
        self.processRunner = processRunner
    }

    func framedPNG(from screenshotData: Data, for device: AndroidDevice) async -> Data? {
        guard let screenshot = PNGImageCodec.image(from: screenshotData) else {
            return nil
        }

        if device.kind == .emulator,
           let sdkRootURL,
           let frameLayout = await AndroidSDKSkinResolver(
               adbPath: adbPath,
               sdkRootURL: sdkRootURL,
               processRunner: processRunner
           ).matchingLayout(for: device, screenshot: screenshot),
           let framedImage = AndroidSDKSkinFrameRenderer.render(
               screenshot,
               using: frameLayout
           ),
           let framedData = PNGImageCodec.data(from: framedImage) {
            AppLogger.screenshot.debug("Applied an Android SDK emulator frame")
            return framedData
        }

        guard let genericFrame = GenericScreenshotFrameRenderer.render(screenshot) else {
            return nil
        }
        AppLogger.screenshot.debug("Applied a generic screenshot frame")
        return PNGImageCodec.data(from: genericFrame)
    }
}

private actor AndroidSDKSkinIndexCache {
    static let shared = AndroidSDKSkinIndexCache()

    private var cachedIndexes: [String: CachedSkinIndex] = [:]

    func index(for sdkRootURL: URL) -> AndroidSDKSkinIndex {
        let skinsDirectoryURL = sdkRootURL.appendingPathComponent("skins", isDirectory: true)
        let modificationDate = (try? FileManager.default.attributesOfItem(
            atPath: skinsDirectoryURL.path
        ))?[.modificationDate] as? Date

        if let cachedIndex = cachedIndexes[skinsDirectoryURL.path],
           cachedIndex.modificationDate == modificationDate {
            return cachedIndex.index
        }

        let index = AndroidSDKSkinIndex.load(from: sdkRootURL)
        cachedIndexes[skinsDirectoryURL.path] = CachedSkinIndex(
            modificationDate: modificationDate,
            index: index
        )
        return index
    }
}

private struct CachedSkinIndex {
    let modificationDate: Date?
    let index: AndroidSDKSkinIndex
}

private struct AndroidSDKSkinResolver: Sendable {
    let adbPath: String
    let sdkRootURL: URL
    let processRunner: any ProcessRunning

    func matchingLayout(
        for device: AndroidDevice,
        screenshot: CGImage
    ) async -> AndroidSDKSkinFrameLayout? {
        let avdPathResult = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "emu", "avd", "path"]
        )
        guard avdPathResult.succeeded,
              let avdDirectoryPath = AndroidEmulatorConsoleParser.firstValue(
                  from: String(decoding: avdPathResult.standardOutput, as: UTF8.self)
              ) else {
            return nil
        }

        let configuration = AndroidEmulatorAVDConfiguration.load(
            from: URL(fileURLWithPath: avdDirectoryPath, isDirectory: true)
                .appendingPathComponent("config.ini")
        )
        let preferredSkinIdentifiers = configuration.preferredSkinIdentifiers
        let index = await AndroidSDKSkinIndexCache.shared.index(for: sdkRootURL)
        return index.bestLayout(
            forScreenshotWidth: screenshot.width,
            height: screenshot.height,
            preferredSkinIdentifiers: preferredSkinIdentifiers
        )
    }
}

private struct AndroidEmulatorAVDConfiguration {
    let values: [String: String]

    static func load(from fileURL: URL) -> AndroidEmulatorAVDConfiguration {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return AndroidEmulatorAVDConfiguration(values: [:])
        }

        var values: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else {
                continue
            }
            values[key] = value
        }

        return AndroidEmulatorAVDConfiguration(values: values)
    }

    var preferredSkinIdentifiers: [String] {
        [values["skin.path"], values["skin.name"]]
            .compactMap { $0 }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}

private struct AndroidSDKSkinIndex: Sendable {
    let layouts: [AndroidSDKSkinFrameLayout]

    static func load(from sdkRootURL: URL) -> AndroidSDKSkinIndex {
        let skinsDirectoryURL = sdkRootURL.appendingPathComponent("skins", isDirectory: true)
        guard let skinDirectoryURLs = try? FileManager.default.contentsOfDirectory(
            at: skinsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return AndroidSDKSkinIndex(layouts: [])
        }

        let layouts = skinDirectoryURLs.flatMap { skinDirectoryURL -> [AndroidSDKSkinFrameLayout] in
            guard (try? skinDirectoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return []
            }

            let layoutURL = skinDirectoryURL.appendingPathComponent("layout")
            guard let layoutContents = try? String(contentsOf: layoutURL, encoding: .utf8) else {
                return []
            }

            return AndroidSDKSkinLayoutParser.parse(
                layoutContents,
                skinIdentifier: skinDirectoryURL.lastPathComponent,
                skinDirectoryURL: skinDirectoryURL
            )
        }

        return AndroidSDKSkinIndex(layouts: layouts)
    }

    func bestLayout(
        forScreenshotWidth screenshotWidth: Int,
        height screenshotHeight: Int,
        preferredSkinIdentifiers: [String]
    ) -> AndroidSDKSkinFrameLayout? {
        let compatibleLayouts = layouts.filter {
            $0.isCompatible(screenshotWidth: screenshotWidth, height: screenshotHeight)
        }
        guard !compatibleLayouts.isEmpty else {
            return nil
        }

        let preferredIdentifierSet = Set(preferredSkinIdentifiers)
        let scoredLayouts = compatibleLayouts.map { layout in
            (layout, layout.matchScore(
                screenshotWidth: screenshotWidth,
                height: screenshotHeight,
                preferredSkinIdentifiers: preferredIdentifierSet
            ))
        }
        guard let highestScore = scoredLayouts.map(\.1).max() else {
            return nil
        }

        let bestLayouts = scoredLayouts.filter { $0.1 == highestScore }.map(\.0)
        guard bestLayouts.count == 1 else {
            return nil
        }
        return bestLayouts[0]
    }
}

private struct AndroidSDKSkinFrameLayout: Sendable {
    let skinIdentifier: String
    let canvasSize: CGSize
    let displayRect: CGRect
    let displayCornerRadius: CGFloat
    let backdropImageURLs: [PositionedSkinAsset]
    let displayMaskImageURLs: [PositionedSkinAsset]
    let overlayImageURLs: [PositionedSkinAsset]
    let frameOverlayImageURLs: [PositionedSkinAsset]

    func isCompatible(screenshotWidth: Int, height screenshotHeight: Int) -> Bool {
        guard screenshotWidth > 0, screenshotHeight > 0 else {
            return false
        }

        let screenshotAspectRatio = Double(screenshotWidth) / Double(screenshotHeight)
        let displayAspectRatio = Double(displayRect.width / displayRect.height)
        return abs(screenshotAspectRatio - displayAspectRatio) < 0.002
    }

    func matchScore(
        screenshotWidth: Int,
        height screenshotHeight: Int,
        preferredSkinIdentifiers: Set<String>
    ) -> Int {
        var score = 0
        if preferredSkinIdentifiers.contains(skinIdentifier) {
            score += 10_000
        }
        if screenshotWidth == Int(displayRect.width), screenshotHeight == Int(displayRect.height) {
            score += 1_000
        }
        return score
    }
}

private enum AndroidSDKSkinLayoutParser {
    static func parse(
        _ contents: String,
        skinIdentifier: String,
        skinDirectoryURL: URL
    ) -> [AndroidSDKSkinFrameLayout] {
        let document = SkinLayoutDocument(contents: contents)
        guard let parts = document.root.firstChild(named: "parts"),
              let devicePart = parts.firstChild(named: "device"),
              let display = devicePart.firstChild(named: "display"),
              let displayWidth = display.integerValue(for: "width"),
              let displayHeight = display.integerValue(for: "height"),
              let layouts = document.root.firstChild(named: "layouts") else {
            return []
        }

        let displayOffsetX = display.integerValue(for: "x") ?? 0
        let displayOffsetY = display.integerValue(for: "y") ?? 0
        let displayCornerRadius = CGFloat(display.integerValue(for: "corner_radius") ?? 0)

        return layouts.children.compactMap { layout in
            guard let canvasWidth = layout.integerValue(for: "width"),
                  let canvasHeight = layout.integerValue(for: "height"),
                  let devicePlacement = layout.children.first(where: {
                      $0.stringValue(for: "name") == "device"
                  }),
                  (devicePlacement.integerValue(for: "rotation") ?? 0) == 0,
                  let framePlacement = layout.children.first(where: {
                      guard let name = $0.stringValue(for: "name") else {
                          return false
                      }
                      return name != "device" && parts.firstChild(named: name) != nil
                  }),
                  let framePartName = framePlacement.stringValue(for: "name"),
                  let framePart = parts.firstChild(named: framePartName) else {
                return nil
            }

            let deviceX = devicePlacement.integerValue(for: "x") ?? 0
            let deviceY = devicePlacement.integerValue(for: "y") ?? 0
            let frameX = framePlacement.integerValue(for: "x") ?? 0
            let frameY = framePlacement.integerValue(for: "y") ?? 0
            let displayRect = CGRect(
                x: deviceX + displayOffsetX,
                y: deviceY + displayOffsetY,
                width: displayWidth,
                height: displayHeight
            )

            let backdropImageURLs = imageURLs(
                in: framePart.firstChild(named: "background"),
                assetKey: "image",
                skinDirectoryURL: skinDirectoryURL
            )
            let displayMaskImageURLs = imageURLs(
                in: framePart.firstChild(named: "foreground"),
                assetKey: "mask",
                skinDirectoryURL: skinDirectoryURL
            )
            let overlayImageURLs = displayMaskImageURLs + imageURLs(
                in: framePart.firstChild(named: "foreground"),
                assetKey: "image",
                skinDirectoryURL: skinDirectoryURL
            )
            let frameOverlayImageURLs = imageURLs(
                in: framePart.firstChild(named: "onion"),
                assetKey: "image",
                skinDirectoryURL: skinDirectoryURL
            )

            guard !backdropImageURLs.isEmpty else {
                return nil
            }

            return AndroidSDKSkinFrameLayout(
                skinIdentifier: skinIdentifier,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
                displayRect: displayRect,
                displayCornerRadius: displayCornerRadius,
                backdropImageURLs: backdropImageURLs.map { imageURL in
                    imageURL.withPlacement(x: frameX, y: frameY)
                },
                displayMaskImageURLs: displayMaskImageURLs.map { imageURL in
                    imageURL.withPlacement(x: Int(displayRect.origin.x), y: Int(displayRect.origin.y))
                },
                overlayImageURLs: overlayImageURLs.map { imageURL in
                    imageURL.withPlacement(x: Int(displayRect.origin.x), y: Int(displayRect.origin.y))
                },
                frameOverlayImageURLs: frameOverlayImageURLs.map { imageURL in
                    imageURL.withPlacement(x: frameX, y: frameY)
                }
            )
        }
    }

    private static func imageURLs(
        in node: SkinLayoutNode?,
        assetKey: String,
        skinDirectoryURL: URL
    ) -> [URL] {
        guard let assetName = node?.stringValue(for: assetKey), !assetName.isEmpty else {
            return []
        }

        let assetURL = skinDirectoryURL.appendingPathComponent(assetName)
        return FileManager.default.fileExists(atPath: assetURL.path) ? [assetURL] : []
    }
}

private struct SkinLayoutDocument {
    let root: SkinLayoutNode

    init(contents: String) {
        var parser = SkinLayoutParser(tokens: SkinLayoutLexer.tokens(in: contents))
        root = SkinLayoutNode(name: "root", value: nil, children: parser.parseNodes())
    }
}

private struct SkinLayoutParser {
    private var tokens: [String]
    private var index = 0

    init(tokens: [String]) {
        self.tokens = tokens
    }

    mutating func parseNodes(untilClosingBrace: Bool = false) -> [SkinLayoutNode] {
        var nodes: [SkinLayoutNode] = []

        while index < tokens.count {
            if untilClosingBrace, tokens[index] == "}" {
                index += 1
                break
            }

            let name = tokens[index]
            index += 1
            guard index < tokens.count else {
                break
            }

            if tokens[index] == "{" {
                index += 1
                nodes.append(SkinLayoutNode(
                    name: name,
                    value: nil,
                    children: parseNodes(untilClosingBrace: true)
                ))
            } else {
                let value = tokens[index]
                index += 1
                nodes.append(SkinLayoutNode(name: name, value: value, children: []))
            }
        }

        return nodes
    }
}

private enum SkinLayoutLexer {
    static func tokens(in contents: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""

        func appendCurrentToken() {
            guard !currentToken.isEmpty else {
                return
            }
            tokens.append(currentToken)
            currentToken = ""
        }

        for scalar in contents.unicodeScalars {
            switch scalar {
            case "{", "}":
                appendCurrentToken()
                tokens.append(String(scalar))
            case " ", "\t", "\n", "\r":
                appendCurrentToken()
            default:
                currentToken.unicodeScalars.append(scalar)
            }
        }
        appendCurrentToken()
        return tokens
    }
}

private struct SkinLayoutNode {
    let name: String
    let value: String?
    let children: [SkinLayoutNode]

    func firstChild(named name: String) -> SkinLayoutNode? {
        children.first { $0.name == name }
    }

    func stringValue(for name: String) -> String? {
        firstChild(named: name)?.value
    }

    func integerValue(for name: String) -> Int? {
        stringValue(for: name).flatMap(Int.init)
    }
}

private struct PositionedSkinAsset: Sendable {
    let url: URL
    let origin: CGPoint
}

private extension URL {
    func withPlacement(x: Int, y: Int) -> PositionedSkinAsset {
        PositionedSkinAsset(url: self, origin: CGPoint(x: x, y: y))
    }
}

private enum AndroidSDKSkinFrameRenderer {
    static func render(
        _ screenshot: CGImage,
        using layout: AndroidSDKSkinFrameLayout
    ) -> CGImage? {
        let scaleX = CGFloat(screenshot.width) / layout.displayRect.width
        let scaleY = CGFloat(screenshot.height) / layout.displayRect.height
        guard abs(scaleX - scaleY) < 0.002 else {
            return nil
        }

        let canvasWidth = Int((layout.canvasSize.width * scaleX).rounded())
        let canvasHeight = Int((layout.canvasSize.height * scaleY).rounded())
        guard let context = ImageCanvas.makeContext(width: canvasWidth, height: canvasHeight) else {
            return nil
        }

        let backdropImages = layout.backdropImageURLs.compactMap(ImageCanvas.image)
        let displayMaskImages = layout.displayMaskImageURLs.compactMap(ImageCanvas.image)
        let overlayImages = layout.overlayImageURLs.compactMap(ImageCanvas.image)
        let frameOverlayImages = layout.frameOverlayImageURLs.compactMap(ImageCanvas.image)
        guard backdropImages.count == layout.backdropImageURLs.count,
              displayMaskImages.count == layout.displayMaskImageURLs.count,
              overlayImages.count == layout.overlayImageURLs.count,
              frameOverlayImages.count == layout.frameOverlayImageURLs.count else {
            return nil
        }

        for image in backdropImages {
            ImageCanvas.draw(image, in: context, scale: scaleX, canvasHeight: canvasHeight)
        }

        let displayDrawingRect = ImageCanvas.topLeftRect(
            layout.displayRect,
            scale: scaleX,
            canvasHeight: canvasHeight
        )
        context.saveGState()
        if layout.displayCornerRadius > 0 {
            let scaledCornerRadius = layout.displayCornerRadius * scaleX
            context.addPath(CGPath(
                roundedRect: displayDrawingRect,
                cornerWidth: scaledCornerRadius,
                cornerHeight: scaledCornerRadius,
                transform: nil
            ))
            context.clip()
        }
        for displayMaskImage in displayMaskImages {
            guard let screenMask = ScreenMask.make(from: displayMaskImage.image) else {
                return nil
            }
            let maskRect = ImageCanvas.topLeftRect(
                CGRect(
                    x: displayMaskImage.origin.x,
                    y: displayMaskImage.origin.y,
                    width: CGFloat(displayMaskImage.image.width),
                    height: CGFloat(displayMaskImage.image.height)
                ),
                scale: scaleX,
                canvasHeight: canvasHeight
            )
            context.clip(to: maskRect, mask: screenMask)
        }
        context.draw(screenshot, in: displayDrawingRect)
        context.restoreGState()

        for image in overlayImages {
            ImageCanvas.draw(image, in: context, scale: scaleX, canvasHeight: canvasHeight)
        }
        for image in frameOverlayImages {
            ImageCanvas.draw(image, in: context, scale: scaleX, canvasHeight: canvasHeight)
        }

        return context.makeImage()
    }
}

private enum ScreenMask {
    static func make(from displayMask: CGImage) -> CGImage? {
        let width = displayMask.width
        let height = displayMask.height
        guard width > 0,
              height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(displayMask, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let maskData = context.data else {
            return nil
        }

        let sourcePixels = maskData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var screenPixels = [UInt8](repeating: 0, count: width * height)
        for pixelIndex in 0..<(width * height) {
            let alpha = sourcePixels[pixelIndex * 4 + 3]
            // CGImage masks use black for the drawable portion. Any skin-mask coverage
            // belongs to the bezel, so exclude the screenshot from that pixel entirely.
            screenPixels[pixelIndex] = alpha == 0 ? 0 : 255
        }

        guard let provider = CGDataProvider(data: Data(screenPixels) as CFData) else {
            return nil
        }
        return CGImage(
            maskWidth: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            provider: provider,
            decode: nil,
            shouldInterpolate: false
        )
    }
}

private enum GenericScreenshotFrameRenderer {
    static func render(_ screenshot: CGImage) -> CGImage? {
        let bezel = max(20, Int((Double(min(screenshot.width, screenshot.height)) * 0.045).rounded()))
        let canvasWidth = screenshot.width + bezel * 2
        let canvasHeight = screenshot.height + bezel * 2
        guard let context = ImageCanvas.makeContext(width: canvasWidth, height: canvasHeight) else {
            return nil
        }

        let outerRect = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        let screenRect = CGRect(x: bezel, y: bezel, width: screenshot.width, height: screenshot.height)
        let outerCornerRadius = CGFloat(max(bezel * 2, 28))
        let screenCornerRadius = max(0, outerCornerRadius - CGFloat(bezel))

        context.setFillColor(CGColor(gray: 0.03, alpha: 1))
        context.addPath(CGPath(
            roundedRect: outerRect,
            cornerWidth: outerCornerRadius,
            cornerHeight: outerCornerRadius,
            transform: nil
        ))
        context.fillPath()

        let screenDrawingRect = ImageCanvas.topLeftRect(
            screenRect,
            scale: 1,
            canvasHeight: canvasHeight
        )
        context.saveGState()
        context.addPath(CGPath(
            roundedRect: screenDrawingRect,
            cornerWidth: screenCornerRadius,
            cornerHeight: screenCornerRadius,
            transform: nil
        ))
        context.clip()
        context.draw(screenshot, in: screenDrawingRect)
        context.restoreGState()

        return context.makeImage()
    }
}

private enum PNGImageCodec {
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func image(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func data(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

private enum ImageCanvas {
    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else {
            return nil
        }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func image(for positionedAsset: PositionedSkinAsset) -> (image: CGImage, origin: CGPoint)? {
        guard let image = PNGImageCodec.image(from: positionedAsset.url) else {
            return nil
        }
        return (image, positionedAsset.origin)
    }

    static func draw(
        _ positionedImage: (image: CGImage, origin: CGPoint),
        in context: CGContext,
        scale: CGFloat,
        canvasHeight: Int
    ) {
        context.draw(
            positionedImage.image,
            in: topLeftRect(
                CGRect(
                    x: positionedImage.origin.x,
                    y: positionedImage.origin.y,
                    width: CGFloat(positionedImage.image.width),
                    height: CGFloat(positionedImage.image.height)
                ),
                scale: scale,
                canvasHeight: canvasHeight
            )
        )
    }

    static func topLeftRect(
        _ rect: CGRect,
        scale: CGFloat,
        canvasHeight: Int
    ) -> CGRect {
        // Android skin layouts use a top-left origin; keep the CGImage data itself unflipped.
        let scaledHeight = rect.height * scale
        return CGRect(
            x: rect.origin.x * scale,
            y: CGFloat(canvasHeight) - (rect.origin.y * scale) - scaledHeight,
            width: rect.width * scale,
            height: scaledHeight
        )
    }
}
