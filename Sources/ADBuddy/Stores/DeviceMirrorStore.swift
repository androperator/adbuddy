import AppKit
import Observation

@MainActor
@Observable
final class DeviceMirrorStore {
    private(set) var activeSerials: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var processIdentifiers: [String: Int32] = [:]
    @ObservationIgnored private var isShuttingDown = false
    private let backend: any DeviceMirroring
    private let activate: (Int32) -> Void
    private let reportFailure: (String) -> Void

    init(
        backend: any DeviceMirroring = ScrcpyMirroring(),
        activate: @escaping (Int32) -> Void = { pid in
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        },
        reportFailure: @escaping (String) -> Void = { message in
            let alert = NSAlert()
            alert.messageText = "Could Not Mirror Device"
            alert.informativeText = message
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    ) {
        self.backend = backend
        self.activate = activate
        self.reportFailure = reportFailure
    }

    func open(device: AndroidDevice, adbPath: String?) {
        guard !isShuttingDown else { return }
        if activeSerials.contains(device.serial) {
            if let pid = processIdentifiers[device.serial] { activate(pid) }
            return
        }
        guard device.isUsable, let adbPath else {
            reportFailure("\(device.displayName) is unavailable. Check its ADB connection and authorization.")
            return
        }
        activeSerials.insert(device.serial)
        AppLogger.mirroring.info("Opening device mirror")
        tasks[device.serial] = Task { [weak self, backend] in
            let result = await backend.mirror(device: device, adbPath: adbPath) { [weak self] pid in
                self?.processIdentifiers[device.serial] = pid
            }
            guard let self else { return }
            activeSerials.remove(device.serial)
            processIdentifiers[device.serial] = nil
            tasks[device.serial] = nil
            guard !result.wasCancelled, !isShuttingDown else { return }
            if result.succeeded {
                AppLogger.mirroring.info("Device mirror closed")
            } else {
                let detail = result.failureDescription
                    ?? String(decoding: result.standardError.suffix(4_000), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.mirroring.error("Device mirror failed: \(detail, privacy: .public)")
                reportFailure("\(device.displayName): mirroring ended. Check the device connection and try again.\n\n\(detail)")
            }
        }
    }

    func stopAll() async {
        isShuttingDown = true
        let pending = Array(tasks.values)
        for task in pending { task.cancel() }
        for task in pending { await task.value }
    }
}
