import AppKit
import ADBuddyCore
import Foundation

enum EmulatorWindowPresentation: Equatable, Sendable {
    case standalone(processIdentifier: Int32)
    case embeddedInAndroidStudio
    case headless
    case unknown

    var detail: String {
        switch self {
        case .standalone:
            "Standalone window"
        case .embeddedInAndroidStudio:
            "Android Studio window"
        case .headless:
            "Headless"
        case .unknown:
            "Window not identified"
        }
    }

    var canRevealHostWindow: Bool {
        switch self {
        case .standalone, .embeddedInAndroidStudio:
            true
        case .headless, .unknown:
            false
        }
    }
}

struct EmulatorWindowService: Sendable {
    private let processRunner: any ProcessRunning

    init(processRunner: any ProcessRunning) {
        self.processRunner = processRunner
    }

    func discoverWindowPresentations() async -> [String: EmulatorWindowPresentation] {
        let result = await processRunner.run(
            executablePath: "/bin/ps",
            arguments: ["-axo", "pid=,command="]
        )

        guard result.succeeded else {
            AppLogger.emulator.error("Could not inspect Android Emulator host processes")
            return [:]
        }

        return EmulatorHostProcessParser.parse(
            String(decoding: result.standardOutput, as: UTF8.self)
        )
    }

    @MainActor
    static func activateStandaloneWindow(processIdentifier: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: pid_t(processIdentifier)) else {
            return false
        }

        return application.activate(options: [])
    }

    @MainActor
    static func activateAndroidStudioWindow() -> Bool {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.hasPrefix("com.google.android.studio") == true
        }) else {
            return false
        }

        return application.activate(options: [])
    }
}

enum EmulatorHostProcessParser {
    static func parse(_ output: String) -> [String: EmulatorWindowPresentation] {
        var presentations: [String: EmulatorWindowPresentation] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            let columns = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard columns.count == 2,
                  let processIdentifier = Int32(columns[0]) else {
                continue
            }

            let command = String(columns[1])
            guard command.contains("/emulator/qemu/"),
                  command.contains("qemu-system"),
                  let virtualDeviceName = virtualDeviceName(in: command) else {
                continue
            }

            presentations[virtualDeviceName] = presentation(
                for: command,
                processIdentifier: processIdentifier
            )
        }

        return presentations
    }

    private static func virtualDeviceName(in command: String) -> String? {
        let arguments = command.split(whereSeparator: \.isWhitespace)
        if let avdIndex = arguments.firstIndex(of: "-avd"),
           arguments.indices.contains(arguments.index(after: avdIndex)) {
            return String(arguments[arguments.index(after: avdIndex)])
        }

        guard let shorthand = arguments.dropFirst().first(where: { $0.hasPrefix("@") && $0.count > 1 }) else {
            return nil
        }
        return String(shorthand.dropFirst())
    }

    private static func presentation(
        for command: String,
        processIdentifier: Int32
    ) -> EmulatorWindowPresentation {
        if command.contains("-no-window") {
            return .headless
        }
        if command.contains("-qt-hide-window") {
            return .embeddedInAndroidStudio
        }
        return .standalone(processIdentifier: processIdentifier)
    }
}
