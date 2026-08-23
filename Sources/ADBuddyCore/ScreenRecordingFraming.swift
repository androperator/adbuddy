@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import Foundation
@preconcurrency import QuartzCore

public struct ScreenRecordingFramingOptions: Equatable, Sendable {
    public static let disabled = ScreenRecordingFramingOptions(
        addsFrame: false,
        overlaysDeviceDetails: false
    )

    public let addsFrame: Bool
    public let overlaysDeviceDetails: Bool

    public init(addsFrame: Bool, overlaysDeviceDetails: Bool = false) {
        self.addsFrame = addsFrame
        self.overlaysDeviceDetails = overlaysDeviceDetails
    }
}

public enum ScreenRecordingFramingResult: Equatable, Sendable {
    case success
    case failure(String)
    case cancelled
}

public protocol ScreenRecordingFraming: Sendable {
    func frame(
        recordingAt inputURL: URL,
        outputURL: URL,
        device: AndroidDevice,
        overlaysDeviceDetails: Bool
    ) async -> ScreenRecordingFramingResult
}

struct ScreenRecordingFrameGeometry: Equatable {
    let canvasSize: CGSize
    let videoRect: CGRect
    let screenCornerRadius: CGFloat

    static func generic(for videoSize: CGSize) -> ScreenRecordingFrameGeometry? {
        guard videoSize.width > 0, videoSize.height > 0 else {
            return nil
        }

        let bezel = max(20, Int((min(videoSize.width, videoSize.height) * 0.045).rounded()))
        let canvasSize = CGSize(
            width: evenRounded(videoSize.width + CGFloat(bezel * 2)),
            height: evenRounded(videoSize.height + CGFloat(bezel * 2))
        )
        let outerCornerRadius = CGFloat(max(bezel * 2, 28))
        let topLeftDisplayRect = CGRect(
            x: CGFloat(bezel),
            y: CGFloat(bezel),
            width: videoSize.width,
            height: videoSize.height
        )
        return ScreenRecordingFrameGeometry(
            canvasSize: canvasSize,
            videoRect: bottomLeftRect(forTopLeftRect: topLeftDisplayRect, canvasHeight: canvasSize.height),
            screenCornerRadius: max(0, outerCornerRadius - CGFloat(bezel))
        )
    }

    static func sdk(
        layout: AndroidSDKSkinFrameLayout,
        videoSize: CGSize
    ) -> (geometry: ScreenRecordingFrameGeometry, scale: CGFloat)? {
        guard videoSize.width > 0,
              videoSize.height > 0,
              layout.displayRect.width > 0,
              layout.displayRect.height > 0 else {
            return nil
        }

        let scaleX = videoSize.width / layout.displayRect.width
        let scaleY = videoSize.height / layout.displayRect.height
        guard abs(scaleX - scaleY) < 0.002 else {
            return nil
        }

        let canvasSize = CGSize(
            width: evenRounded(layout.canvasSize.width * scaleX),
            height: evenRounded(layout.canvasSize.height * scaleX)
        )
        let topLeftDisplayRect = CGRect(
            x: layout.displayRect.origin.x * scaleX,
            y: layout.displayRect.origin.y * scaleX,
            width: videoSize.width,
            height: videoSize.height
        )
        return (
            ScreenRecordingFrameGeometry(
                canvasSize: canvasSize,
                videoRect: bottomLeftRect(
                    forTopLeftRect: topLeftDisplayRect,
                    canvasHeight: canvasSize.height
                ),
                screenCornerRadius: layout.displayCornerRadius * scaleX
            ),
            scaleX
        )
    }

    private static func bottomLeftRect(forTopLeftRect rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: canvasHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func evenRounded(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded(.up)))
        return CGFloat(rounded.isMultiple(of: 2) ? rounded : rounded + 1)
    }
}

struct ScreenRecordingVideoCompositionConfiguration: Equatable {
    let renderSize: CGSize
    let videoRect: CGRect
    let videoTransform: CGAffineTransform
    let frameDuration: CMTime

    init?(
        naturalVideoSize: CGSize,
        preferredTransform: CGAffineTransform,
        frameGeometry: ScreenRecordingFrameGeometry,
        nominalFrameRate: Float
    ) {
        guard naturalVideoSize.width > 0, naturalVideoSize.height > 0 else {
            return nil
        }

        let transformedBounds = CGRect(origin: .zero, size: naturalVideoSize)
            .applying(preferredTransform)
            .standardized
        guard transformedBounds.width > 0, transformedBounds.height > 0 else {
            return nil
        }

        let scaleX = frameGeometry.videoRect.width / transformedBounds.width
        let scaleY = frameGeometry.videoRect.height / transformedBounds.height
        guard abs(scaleX - scaleY) < 0.002 else {
            return nil
        }

        func mappedPoint(_ point: CGPoint) -> CGPoint {
            let transformed = point.applying(preferredTransform)
            return CGPoint(
                x: (transformed.x - transformedBounds.minX) * scaleX + frameGeometry.videoRect.minX,
                y: (transformed.y - transformedBounds.minY) * scaleY + frameGeometry.videoRect.minY
            )
        }

        let origin = mappedPoint(.zero)
        let xAxis = mappedPoint(CGPoint(x: 1, y: 0))
        let yAxis = mappedPoint(CGPoint(x: 0, y: 1))

        renderSize = frameGeometry.canvasSize
        videoRect = frameGeometry.videoRect
        videoTransform = CGAffineTransform(
            a: xAxis.x - origin.x,
            b: xAxis.y - origin.y,
            c: yAxis.x - origin.x,
            d: yAxis.y - origin.y,
            tx: origin.x,
            ty: origin.y
        )
        let frameRate = max(1, min(60, Int(nominalFrameRate.rounded())))
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }
}

public struct AVFoundationScreenRecordingFramer: ScreenRecordingFraming, @unchecked Sendable {
    private let adbPath: String
    private let sdkRootURL: URL?
    private let processRunner: any ProcessRunning

    public init(
        adbPath: String,
        sdkRootPath: String?,
        processRunner: any ProcessRunning
    ) {
        self.adbPath = adbPath
        sdkRootURL = sdkRootPath.map(URL.init(fileURLWithPath:))
        self.processRunner = processRunner
    }

    public func frame(
        recordingAt inputURL: URL,
        outputURL: URL,
        device: AndroidDevice,
        overlaysDeviceDetails: Bool
    ) async -> ScreenRecordingFramingResult {
        guard !Task.isCancelled else {
            return .cancelled
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            return .failure("A framed recording already exists at \(outputURL.lastPathComponent).")
        }

        let asset = AVURLAsset(url: inputURL)
        do {
            let deviceDetails: AndroidDeviceDetails?
            if overlaysDeviceDetails {
                guard let resolvedDeviceDetails = await AndroidDeviceDetailsService(
                    adbPath: adbPath,
                    processRunner: processRunner
                ).details(for: device) else {
                    return .failure("Could not read the Android version and API level for the overlay.")
                }
                deviceDetails = resolvedDeviceDetails
            } else {
                deviceDetails = nil
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                return .failure("The saved recording does not contain a video track.")
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let duration = try await asset.load(.duration)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            guard duration.isValid, duration > .zero else {
                return .failure("The saved recording has no playable duration.")
            }

            let videoSize = orientedSize(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform
            )
            guard let selectedFrameDescriptor = await frameDescriptor(
                for: device,
                videoSize: videoSize
            ) else {
                return .failure("Could not prepare a device frame for the saved recording.")
            }

            let compositionSetup = compositionSetup(
                videoTrack: videoTrack,
                duration: duration,
                naturalVideoSize: naturalSize,
                preferredTransform: preferredTransform,
                nominalFrameRate: nominalFrameRate,
                frameDescriptor: selectedFrameDescriptor,
                deviceDetails: deviceDetails
            ) ?? genericCompositionSetup(
                videoTrack: videoTrack,
                duration: duration,
                naturalVideoSize: naturalSize,
                preferredTransform: preferredTransform,
                nominalFrameRate: nominalFrameRate,
                videoSize: videoSize,
                deviceDetails: deviceDetails
            )
            guard let compositionSetup else {
                return .failure("Could not prepare a device frame for the saved recording.")
            }

            let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(
                ".adbuddy-framed-\(UUID().uuidString).partial.mp4"
            )
            defer {
                try? FileManager.default.removeItem(at: temporaryURL)
            }

            let exportResult = await export(
                asset: asset,
                videoComposition: compositionSetup,
                temporaryURL: temporaryURL
            )
            switch exportResult {
            case .success:
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
                    return .success
                } catch {
                    return .failure("Could not save the framed recording: \(error.localizedDescription)")
                }
            case .failure(let message):
                return .failure(message)
            case .cancelled:
                return .cancelled
            }
        } catch {
            return .failure("Could not read the saved recording: \(error.localizedDescription)")
        }
    }

    private func frameDescriptor(
        for device: AndroidDevice,
        videoSize: CGSize
    ) async -> RecordingFrameDescriptor? {
        if device.kind == .emulator,
           let sdkRootURL,
           let layout = await AndroidSDKSkinResolver(
               adbPath: adbPath,
               sdkRootURL: sdkRootURL,
               processRunner: processRunner
           ).matchingLayout(
               for: device,
               displayWidth: Int(videoSize.width.rounded()),
               displayHeight: Int(videoSize.height.rounded())
           ),
           let sdkGeometry = ScreenRecordingFrameGeometry.sdk(layout: layout, videoSize: videoSize) {
            return RecordingFrameDescriptor(
                geometry: sdkGeometry.geometry,
                style: .sdk(layout: layout, scale: sdkGeometry.scale)
            )
        }

        guard let geometry = ScreenRecordingFrameGeometry.generic(for: videoSize) else {
            return nil
        }
        return RecordingFrameDescriptor(geometry: geometry, style: .generic)
    }

    private func videoComposition(
        videoTrack: AVAssetTrack,
        duration: CMTime,
        configuration: ScreenRecordingVideoCompositionConfiguration,
        frameDescriptor: RecordingFrameDescriptor,
        deviceDetails: AndroidDeviceDetails?
    ) -> AVMutableVideoComposition? {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(configuration.videoTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = configuration.renderSize
        composition.frameDuration = configuration.frameDuration

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: configuration.renderSize)
        parentLayer.backgroundColor = CGColor(gray: 0, alpha: 1)

        switch frameDescriptor.style {
        case .generic:
            let frameLayer = CAShapeLayer()
            frameLayer.frame = parentLayer.bounds
            frameLayer.path = CGPath(
                roundedRect: parentLayer.bounds,
                cornerWidth: max(
                    frameDescriptor.geometry.screenCornerRadius * 2,
                    frameDescriptor.geometry.screenCornerRadius + 1
                ),
                cornerHeight: max(
                    frameDescriptor.geometry.screenCornerRadius * 2,
                    frameDescriptor.geometry.screenCornerRadius + 1
                ),
                transform: nil
            )
            frameLayer.fillColor = CGColor(gray: 0.03, alpha: 1)
            parentLayer.addSublayer(frameLayer)
        case .sdk(let layout, let scale):
            guard let backdropImage = AndroidSDKSkinFrameRenderer.backdropImage(
                using: layout,
                scale: scale
            ) else {
                return nil
            }
            let backdropLayer = CALayer()
            backdropLayer.frame = parentLayer.bounds
            backdropLayer.contents = backdropImage
            parentLayer.addSublayer(backdropLayer)
        }

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        videoLayer.mask = displayMaskLayer(
            canvasSize: configuration.renderSize,
            displayRect: configuration.videoRect,
            cornerRadius: frameDescriptor.geometry.screenCornerRadius
        )
        parentLayer.addSublayer(videoLayer)

        if case .sdk(let layout, let scale) = frameDescriptor.style,
           let overlayImage = AndroidSDKSkinFrameRenderer.overlayImage(using: layout, scale: scale) {
            let overlayLayer = CALayer()
            overlayLayer.frame = parentLayer.bounds
            overlayLayer.contents = overlayImage
            parentLayer.addSublayer(overlayLayer)
        }

        if let deviceDetails {
            guard let overlayLayer = deviceDetailsOverlayLayer(
                for: deviceDetails,
                canvasSize: configuration.renderSize
            ) else {
                return nil
            }
            parentLayer.addSublayer(overlayLayer)
        }

        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        return composition
    }

    private func compositionSetup(
        videoTrack: AVAssetTrack,
        duration: CMTime,
        naturalVideoSize: CGSize,
        preferredTransform: CGAffineTransform,
        nominalFrameRate: Float,
        frameDescriptor: RecordingFrameDescriptor,
        deviceDetails: AndroidDeviceDetails?
    ) -> AVMutableVideoComposition? {
        guard let configuration = ScreenRecordingVideoCompositionConfiguration(
            naturalVideoSize: naturalVideoSize,
            preferredTransform: preferredTransform,
            frameGeometry: frameDescriptor.geometry,
            nominalFrameRate: nominalFrameRate
        ) else {
            return nil
        }
        return videoComposition(
            videoTrack: videoTrack,
            duration: duration,
            configuration: configuration,
            frameDescriptor: frameDescriptor,
            deviceDetails: deviceDetails
        )
    }

    private func genericCompositionSetup(
        videoTrack: AVAssetTrack,
        duration: CMTime,
        naturalVideoSize: CGSize,
        preferredTransform: CGAffineTransform,
        nominalFrameRate: Float,
        videoSize: CGSize,
        deviceDetails: AndroidDeviceDetails?
    ) -> AVMutableVideoComposition? {
        guard let geometry = ScreenRecordingFrameGeometry.generic(for: videoSize) else {
            return nil
        }
        return compositionSetup(
            videoTrack: videoTrack,
            duration: duration,
            naturalVideoSize: naturalVideoSize,
            preferredTransform: preferredTransform,
            nominalFrameRate: nominalFrameRate,
            frameDescriptor: RecordingFrameDescriptor(geometry: geometry, style: .generic),
            deviceDetails: deviceDetails
        )
    }

    private func deviceDetailsOverlayLayer(
        for deviceDetails: AndroidDeviceDetails,
        canvasSize: CGSize
    ) -> CALayer? {
        let canvasWidth = Int(canvasSize.width.rounded())
        let canvasHeight = Int(canvasSize.height.rounded())
        guard let context = ImageCanvas.makeContext(width: canvasWidth, height: canvasHeight) else {
            return nil
        }

        let shortestSide = min(canvasSize.width, canvasSize.height)
        let outerMargin: CGFloat = 4
        let labelPadding = max(10, shortestSide * 0.012)
        let fontSize = max(20, shortestSide * 0.032)
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("HelveticaNeue-Medium" as CFString, fontSize, nil)
        let text = deviceDetails.screenshotOverlayText
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        let textBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let labelRect = CGRect(
            x: outerMargin,
            y: canvasSize.height - outerMargin - textBounds.height - labelPadding * 2,
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
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.textPosition = CGPoint(
            x: labelRect.minX + labelPadding - textBounds.origin.x,
            y: labelRect.minY + labelPadding - textBounds.origin.y
        )
        CTLineDraw(line, context)

        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: canvasSize)
        overlayLayer.contents = context.makeImage()
        return overlayLayer
    }

    private func displayMaskLayer(
        canvasSize: CGSize,
        displayRect: CGRect,
        cornerRadius: CGFloat
    ) -> CALayer {
        let maskLayer = CAShapeLayer()
        maskLayer.frame = CGRect(origin: .zero, size: canvasSize)
        maskLayer.path = CGPath(
            roundedRect: displayRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        maskLayer.fillColor = CGColor(gray: 1, alpha: 1)
        return maskLayer
    }

    private func export(
        asset: AVAsset,
        videoComposition: AVVideoComposition,
        temporaryURL: URL
    ) async -> ScreenRecordingFramingResult {
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            return .failure("macOS could not create a video export session.")
        }
        guard exportSession.supportedFileTypes.contains(.mp4) else {
            return .failure("macOS cannot export this recording as an MP4.")
        }

        exportSession.outputURL = temporaryURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = false

        let sessionBox = VideoExportSessionBox(exportSession)
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                sessionBox.session.exportAsynchronously {
                    switch sessionBox.session.status {
                    case .completed:
                        continuation.resume(returning: .success)
                    case .cancelled:
                        continuation.resume(returning: .cancelled)
                    case .failed:
                        continuation.resume(returning: .failure(
                            sessionBox.session.error?.localizedDescription
                                ?? "macOS could not export the framed recording."
                        ))
                    default:
                        continuation.resume(returning: .failure(
                            "macOS did not complete the framed recording export."
                        ))
                    }
                }
            }
        }, onCancel: {
            sessionBox.session.cancelExport()
        })
    }

    private func orientedSize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        let transformedBounds = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        return CGSize(width: transformedBounds.width, height: transformedBounds.height)
    }
}

private struct RecordingFrameDescriptor {
    let geometry: ScreenRecordingFrameGeometry
    let style: RecordingFrameStyle
}

private enum RecordingFrameStyle {
    case generic
    case sdk(layout: AndroidSDKSkinFrameLayout, scale: CGFloat)
}

private final class VideoExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
