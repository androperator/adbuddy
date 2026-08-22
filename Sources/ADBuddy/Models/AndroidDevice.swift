import Foundation
import SwiftUI

struct AndroidDevice: Equatable, Identifiable, Sendable {
    let serial: String
    let displayName: String
    let connectionState: DeviceConnectionState
    let kind: AndroidDeviceKind
    let model: String?
    let product: String?
    let deviceCodeName: String?
    let transportID: String?

    var id: String {
        serial
    }

    var isUsable: Bool {
        connectionState.isUsable
    }

    var menuTitle: String {
        displayName.count <= 30 ? displayName : String(displayName.prefix(27)) + "..."
    }
}

enum AndroidDeviceKind: Equatable, Sendable {
    case physical
    case emulator

    var symbolName: String {
        switch self {
        case .physical:
            "cable.connector"
        case .emulator:
            "laptopcomputer"
        }
    }
}

enum DeviceConnectionState: Equatable, Sendable {
    case connected
    case unauthorized
    case offline
    case bootloader
    case recovery
    case sideload
    case unknown(String)

    init(adbValue: String) {
        switch adbValue.lowercased() {
        case "device":
            self = .connected
        case "unauthorized":
            self = .unauthorized
        case "offline":
            self = .offline
        case "bootloader":
            self = .bootloader
        case "recovery":
            self = .recovery
        case "sideload":
            self = .sideload
        default:
            self = .unknown(adbValue)
        }
    }

    var isUsable: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var displayName: String {
        switch self {
        case .connected:
            "Connected"
        case .unauthorized:
            "Unauthorized"
        case .offline:
            "Offline"
        case .bootloader:
            "Bootloader"
        case .recovery:
            "Recovery"
        case .sideload:
            "Sideload"
        case .unknown(let value):
            value.isEmpty ? "Unknown" : value.capitalized
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            .green
        case .unauthorized, .offline:
            .orange
        case .bootloader, .recovery, .sideload, .unknown:
            .secondary
        }
    }
}
