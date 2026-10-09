import Foundation
import Observation

@MainActor
@Observable
final class EmulatorCreationStore {
    var name = ""
    var hardwareType: EmulatorHardwareType = .phone
    var profileID = ""
    var imageID = ""
    var storageGB = "24"
    var startAfterCreation = true
    private(set) var profiles: [EmulatorHardwareProfile] = []
    private(set) var images: [EmulatorSystemImage] = []
    private(set) var isBusy = false
    private(set) var activity = ""
    private(set) var errorMessage: String?
    private(set) var helperDescription: String?
    private(set) var createdName: String?
    private(set) var includesDownloads = false
    private var service: EmulatorCreationService?

    var availableHardwareTypes: [EmulatorHardwareType] {
        EmulatorHardwareType.allCases.filter { type in profiles.contains { $0.hardwareType == type } }
    }
    var availableProfiles: [EmulatorHardwareProfile] { profiles.filter { $0.hardwareType == hardwareType } }
    var selectedProfile: EmulatorHardwareProfile? { availableProfiles.first { $0.id == profileID } }
    private var suggestedName = ""

    func selectHardwareType() {
        if !availableProfiles.contains(where: { $0.id == profileID }) {
            profileID = availableProfiles.first(where: { $0.id == "pixel_7" })?.id ?? availableProfiles.first?.id ?? ""
        }
        selectProfile()
    }
    var availableImages: [EmulatorSystemImage] { EmulatorImageSelection.images(images, for: selectedProfile) }
    var selectedImage: EmulatorSystemImage? { availableImages.first { $0.id == imageID } }

    func validationMessage(existingNames: Set<String>) -> String? {
        guard let profile = selectedProfile, let image = selectedImage else { return "Choose a hardware profile and an image." }
        do {
            try EmulatorCreationRequest(name: name, profile: profile, image: image, storageGB: Int(storageGB) ?? 0).validate(existingNames: existingNames)
            return nil
        } catch { return error.localizedDescription }
    }

    func selectProfile() {
        if !availableImages.contains(where: { $0.id == imageID }) { imageID = availableImages.first?.id ?? "" }
        let shouldSuggest = name.isEmpty || name == suggestedName
        suggestedName = profileID.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "_", options: .regularExpression) + "_Dev"
        if shouldSuggest { name = profileID.isEmpty ? "" : suggestedName }
    }

    func load(configuration: EmulatorHelperConfiguration, sdk: AndroidSDK?) async {
        guard !isBusy else { return }
        isBusy = true
        activity = "Finding emulator tools and installed images…"
        errorMessage = nil
        service = nil
        profiles = []
        images = []
        helperDescription = nil
        includesDownloads = false
        defer { isBusy = false }
        do {
            guard let sdk else { throw EmulatorCreationError("Install an Android SDK with ADB before creating an emulator.") }
            let invocation = try EmulatorHelperInvocation.resolve(configuration: configuration, sdk: sdk)
            let candidate = EmulatorCreationService(invocation: invocation)
            let version = try await candidate.check()
            helperDescription = "@androperator/emulator \(version.version) · \(invocation.script)"
            profiles = try await candidate.profiles()
            images = try await candidate.images(includeDownloads: false)
            service = candidate
            if !availableHardwareTypes.contains(hardwareType) { hardwareType = availableHardwareTypes.first ?? .phone }
            selectHardwareType()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadDownloadableImages() async {
        guard !isBusy, let service else { return }
        isBusy = true
        activity = "Loading downloadable images…"
        errorMessage = nil
        defer { isBusy = false }
        do {
            images = try await service.images(includeDownloads: true)
            includesDownloads = true
            selectProfile()
        } catch { errorMessage = error.localizedDescription }
    }

    func create(existingNames: Set<String>, didCreate: (String?, Bool) -> Void) async {
        guard !isBusy, createdName == nil, let service, let profile = selectedProfile, let image = selectedImage else { return }
        if let message = validationMessage(existingNames: existingNames) { errorMessage = message; return }
        isBusy = true
        errorMessage = nil
        activity = image.installed ? "Creating emulator…" : "Downloading image and creating emulator… This may take several minutes."
        defer { isBusy = false }
        do {
            let request = EmulatorCreationRequest(name: name, profile: profile, image: image, storageGB: Int(storageGB) ?? 0)
            try await service.create(request)
            createdName = name
            didCreate(name, startAfterCreation)
        } catch {
            errorMessage = error.localizedDescription
            didCreate(nil, false) // Reconcile partial creation rather than assuming failure left nothing behind.
            AppLogger.emulator.error("Emulator creation failed")
        }
    }
}
