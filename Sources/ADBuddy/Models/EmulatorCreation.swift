import Foundation

struct EmulatorHardwareProfile: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let manufacturer: String?
    let tag: String?

    var hardwareType: EmulatorHardwareType {
        let tag = tag ?? ""
        if tag.hasPrefix("android-automotive") { return .automotive }
        if tag == "android-tv" || tag == "google-tv" { return .tv }
        if tag.hasPrefix("android-wear") { return .wearOS }
        if tag == "android-desktop" { return .desktop }
        if tag == "android-xr" { return .xr }
        if tag == "ai-glasses" { return .glasses }
        if !tag.isEmpty { return .other }
        let label = "\(id) \(name)".lowercased()
        if label.contains("fold") || label.contains("rollable") { return .foldable }
        // avdmanager's catalog omits a phone/tablet tag. Cover named SDK tablet
        // profiles as well as generic profiles that identify themselves as tablets.
        if label.contains("tablet") || ["Nexus 7", "Nexus 7 2013", "Nexus 9", "Nexus 10", "pixel_c"].contains(id) { return .tablet }
        if label.contains("freeform") || id == "resizable" { return .other }
        return .phone
    }
}

enum EmulatorHardwareType: String, CaseIterable, Identifiable, Sendable {
    case phone = "Phone"
    case tablet = "Tablet"
    case foldable = "Foldable"
    case tv = "TV"
    case automotive = "Automotive"
    case wearOS = "Wear OS"
    case desktop = "Desktop"
    case xr = "XR"
    case glasses = "Glasses"
    case other = "Other"

    var id: String { rawValue }
}

struct EmulatorSystemImage: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let platform: String
    let apiLevel: Int?
    let tag: String
    let abi: String
    let description: String
    let installed: Bool

    var title: String {
        "\(platform.replacingOccurrences(of: "android-", with: "API ")) · \(description)\(installed ? " · Installed" : " · Download")"
    }
}

struct EmulatorHelperVersion: Decodable, Sendable {
    let name: String
    let version: String
    let capabilities: [String]?
}

struct EmulatorCreationRequest: Sendable {
    let name: String
    let profile: EmulatorHardwareProfile
    let image: EmulatorSystemImage
    let storageGB: Int

    var arguments: [String] {
        ["create", name, "--profile", profile.id, "--image", image.id, "--storage-size", "\(storageGB)G"]
    }

    func validate(existingNames: Set<String>) throws {
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$", options: .regularExpression) != nil else {
            throw EmulatorCreationError("Use 1–80 letters, numbers, underscores, dots or hyphens; start with a letter or number.")
        }
        guard !existingNames.contains(name) else {
            throw EmulatorCreationError("An emulator named \(name) already exists. Choose another name.")
        }
        guard (1...1024).contains(storageGB) else {
            throw EmulatorCreationError("Internal storage must be between 1 and 1024 GB.")
        }
    }
}

struct EmulatorCreationError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum EmulatorImageSelection {
    static var hostABI: String {
        #if arch(arm64)
        "arm64-v8a"
        #else
        "x86_64"
        #endif
    }

    static func images(_ images: [EmulatorSystemImage], for profile: EmulatorHardwareProfile?, abi: String = hostABI) -> [EmulatorSystemImage] {
        guard let profile else { return [] }
        return images.filter { image in
            guard image.abi == abi else { return false }
            switch profile.tag {
            case "android-tv", "google-tv": return ["android-tv", "google-tv"].contains(image.tag)
            case nil, "":
                guard image.tag == "default" || image.tag.hasPrefix("google_apis") else { return false }
                let tabletImage = image.tag.contains("tablet") || image.description.localizedCaseInsensitiveContains("tablet")
                return !tabletImage || profile.hardwareType == .tablet
            default: return profile.tag == image.tag
            }
        }.sorted {
            if $0.installed != $1.installed { return $0.installed }
            if $0.apiLevel != $1.apiLevel { return ($0.apiLevel ?? -1) > ($1.apiLevel ?? -1) }
            return $0.id.localizedStandardCompare($1.id) == .orderedDescending
        }
    }
}
