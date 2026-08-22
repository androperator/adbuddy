import Foundation
import SwiftUI

public struct AndroidDevice: Equatable, Identifiable, Sendable {
    public let serial: String
    public let displayName: String
    public let connectionState: DeviceConnectionState
    public let kind: AndroidDeviceKind
    public let model: String?
    public let product: String?
    public let deviceCodeName: String?
    public let transportID: String?

    public init(
        serial: String,
        displayName: String,
        connectionState: DeviceConnectionState,
        kind: AndroidDeviceKind,
        model: String?,
        product: String?,
        deviceCodeName: String?,
        transportID: String?
    ) {
        self.serial = serial
        self.displayName = displayName
        self.connectionState = connectionState
        self.kind = kind
        self.model = model
        self.product = product
        self.deviceCodeName = deviceCodeName
        self.transportID = transportID
    }

    public var id: String {
        serial
    }

    public var isUsable: Bool {
        connectionState.isUsable
    }

    public var menuTitle: String {
        displayName.count <= 30 ? displayName : String(displayName.prefix(27)) + "..."
    }
}

public enum AndroidDeviceKind: Equatable, Sendable {
    case physical
    case emulator

    public var symbolName: String {
        switch self {
        case .physical:
            "cable.connector"
        case .emulator:
            "laptopcomputer"
        }
    }
}

public enum DeviceConnectionState: Equatable, Sendable {
    case connected
    case unauthorized
    case offline
    case bootloader
    case recovery
    case sideload
    case unknown(String)

    public init(adbValue: String) {
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

    public var isUsable: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    public var displayName: String {
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

    public var tint: Color {
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
