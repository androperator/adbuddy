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
    private(set) var isLoadingCatalog = false
    private(set) var isCreating = false
    var isReady: Bool { service != nil }
    private(set) var createdName: String?
    private(set) var catalogError: String?
    private var service: EmulatorCreationService?
    private let makeService: (EmulatorHelperConfiguration, AndroidSDK) throws -> EmulatorCreationService

    init(makeService: @escaping (EmulatorHelperConfiguration, AndroidSDK) throws -> EmulatorCreationService = {
        EmulatorCreationService(invocation: try EmulatorHelperInvocation.resolve(configuration: $0, sdk: $1))
    }) {
        self.makeService = makeService
    }

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
        catalogError = nil
        defer { isBusy = false }
        do {
            guard let sdk else { throw EmulatorCreationError("Install an Android SDK with ADB before creating an emulator.") }
            let candidate = try makeService(configuration, sdk)
            _ = try await candidate.check()
            profiles = try await candidate.profiles()
            images = try await candidate.images(includeDownloads: false)
            service = candidate
            if !availableHardwareTypes.contains(hardwareType) { hardwareType = availableHardwareTypes.first ?? .phone }
            selectHardwareType()
            await fetchFullCatalog(using: candidate)
        } catch { errorMessage = error.localizedDescription }
    }

    func loadDownloadableImages() async {
        guard !isBusy, let service else { return }
        isBusy = true
        defer { isBusy = false }
        await fetchFullCatalog(using: service)
    }

    private func fetchFullCatalog(using service: EmulatorCreationService) async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        activity = "Loading available images…"
        catalogError = nil
        do {
            let catalog = try await service.images(includeDownloads: true)
            // Retain installed choices even if the remote catalog omits them.
            let installed = images.filter(\.installed)
            let installedIDs = Set(installed.map(\.id))
            images = installed + catalog.filter { !installedIDs.contains($0.id) }
            selectProfile()
        } catch {
            catalogError = "Could not load downloadable images. Installed images are still available. " + error.localizedDescription
        }
    }

    func create(existingNames: Set<String>, didCreate: (String?, Bool) -> Void) async {
        guard !isBusy, createdName == nil, let service, let profile = selectedProfile, let image = selectedImage else { return }
        if let message = validationMessage(existingNames: existingNames) { errorMessage = message; return }
        isBusy = true
        errorMessage = nil
        isCreating = true
        defer { isCreating = false }
        activity = image.installed ? "Creating emulator…" : "Downloading image and creating emulator…"
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
