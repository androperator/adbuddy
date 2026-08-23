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
            "Window unavailable"
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
        guard let avdIndex = arguments.firstIndex(of: "-avd"),
              arguments.indices.contains(arguments.index(after: avdIndex)) else {
            return nil
        }

        return String(arguments[arguments.index(after: avdIndex)])
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
