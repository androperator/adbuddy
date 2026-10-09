import Foundation

struct EmulatorHelperConfiguration: Sendable {
    let helperPath: String
    let nodePath: String
    let javaHome: String
}

struct EmulatorHelperInvocation: Sendable {
    let node: String
    let script: String
    let environment: [String: String]

    static func resolve(
        configuration: EmulatorHelperConfiguration,
        sdk: AndroidSDK,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL
    ) throws -> Self {
        let files = FileManager.default
        func expanded(_ path: String) -> String { (path as NSString).expandingTildeInPath }
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let explicitNode = configuration.nodePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = explicitNode.isEmpty
            ? bundleURL.appendingPathComponent("Contents/MacOS/node-\(architecture)").path
            : expanded(explicitNode)
        guard files.isExecutableFile(atPath: node) else {
            throw EmulatorCreationError("Node executable is missing or not executable: \(node). Clear the Node override in Settings → Emulators to use the bundled runtime, or reinstall ADBuddy if the bundled runtime is missing.")
        }
        let override = configuration.helperPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var script = override.isEmpty
            ? bundleURL.appendingPathComponent("Contents/Resources/Emulator/package/dist/cli.js").path
            : expanded(override)
        var isDirectory: ObjCBool = false
        if files.fileExists(atPath: script, isDirectory: &isDirectory), isDirectory.boolValue {
            script = URL(fileURLWithPath: script).appendingPathComponent("dist/cli.js").path
        }
        guard files.isReadableFile(atPath: script) else {
            throw EmulatorCreationError("Emulator helper is missing or unbuilt: \(script). Build the selected checkout, clear the helper override in Settings → Emulators, or reinstall ADBuddy if the bundled helper is missing.")
        }
        var childEnvironment = environment
        // The helper only understands ANDROID_AVD_HOME; SDK tools also honor ANDROID_USER_HOME.
        if (environment["ANDROID_AVD_HOME"] ?? "").isEmpty,
           let userHome = environment["ANDROID_USER_HOME"], !userHome.isEmpty {
            childEnvironment["ANDROID_AVD_HOME"] = URL(fileURLWithPath: userHome)
                .appendingPathComponent("avd", isDirectory: true).path
        }
        childEnvironment["PATH"] = ([URL(fileURLWithPath: node).deletingLastPathComponent().path] + directories + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        childEnvironment["ANDROID_HOME"] = sdk.rootPath
        childEnvironment["ANDROID_SDK_ROOT"] = sdk.rootPath
        childEnvironment["ADB_PATH"] = sdk.adbPath
        childEnvironment["EMULATOR_PATH"] = "\(sdk.rootPath)/emulator/emulator"
        childEnvironment["SDKMANAGER_PATH"] = "\(sdk.rootPath)/cmdline-tools/latest/bin/sdkmanager"
        childEnvironment["AVDMANAGER_PATH"] = "\(sdk.rootPath)/cmdline-tools/latest/bin/avdmanager"
        let java = configuration.javaHome.trimmingCharacters(in: .whitespacesAndNewlines)
        if !java.isEmpty {
            childEnvironment["JAVA_HOME"] = expanded(java)
        } else if childEnvironment["JAVA_HOME"] == nil {
            let bundledJava = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
            if files.isExecutableFile(atPath: "\(bundledJava)/bin/java") { childEnvironment["JAVA_HOME"] = bundledJava }
        }
        return Self(node: node, script: URL(fileURLWithPath: script).resolvingSymlinksInPath().path, environment: childEnvironment)
    }
}

struct EmulatorCreationService: Sendable {
    typealias Execute = @Sendable (String, [String], [String: String]) async -> ProcessResult
    let invocation: EmulatorHelperInvocation
    private let execute: Execute

    init(invocation: EmulatorHelperInvocation, execute: @escaping Execute = { executable, arguments, environment in
        await ProcessRunner().run(executablePath: executable, arguments: arguments, identifier: UUID().uuidString, environment: environment, onStarted: nil)
    }) {
        self.invocation = invocation
        self.execute = execute
    }

    func check(requiresCatalogs: Bool = true) async throws -> EmulatorHelperVersion {
        let node = await execute(invocation.node, ["--version"], invocation.environment)
        let versionText = String(decoding: node.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard node.succeeded, let major = Int(versionText.dropFirst().split(separator: ".").first ?? ""), major >= 24 else {
            throw EmulatorCreationError("The selected Node executable must be version 24 or newer. Update Settings → Emulators.")
        }
        let version: EmulatorHelperVersion = try await call(["--version"])
        guard version.name == "@androperator/emulator" else {
            throw EmulatorCreationError("The selected helper is not @androperator/emulator. Select a compatible helper or clear the override in Settings → Emulators.")
        }
        guard !requiresCatalogs || Set(version.capabilities ?? []).isSuperset(of: ["catalog.profiles", "catalog.images"]) else {
            throw EmulatorCreationError("The selected helper lacks required catalog.profiles and catalog.images capabilities. Select a catalog-capable build in Settings → Emulators or clear the override to use the bundled helper.")
        }
        AppLogger.emulator.info("Emulator helper \(version.version, privacy: .public) at \(invocation.script, privacy: .public), Node at \(invocation.node, privacy: .public)")
        return version
    }

    func profiles() async throws -> [EmulatorHardwareProfile] {
        struct Result: Decodable, Sendable { let profiles: [EmulatorHardwareProfile] }
        let result: Result = try await call(["profiles"])
        return result.profiles
    }

    func images(includeDownloads: Bool) async throws -> [EmulatorSystemImage] {
        struct Result: Decodable, Sendable { let images: [EmulatorSystemImage] }
        let result: Result = try await call(includeDownloads ? ["images"] : ["images", "--installed"])
        return result.images
    }

    func create(_ request: EmulatorCreationRequest) async throws {
        try request.validate(existingNames: [])
        struct Result: Decodable, Sendable { let name: String; let exists: Bool }
        AppLogger.emulator.info("Creating Android virtual device through emulator helper")
        let result: Result = try await call(request.arguments)
        guard result.exists, result.name == request.name else {
            throw EmulatorCreationError("The helper did not confirm the new emulator. Refresh the emulator list before retrying.")
        }
    }

    func delete(name: String) async throws {
        struct Result: Decodable, Sendable { let avdName: String; let deleted: Bool }
        let result: Result = try await call(["delete", name])
        guard result.deleted, result.avdName == name else {
            throw EmulatorCreationError("The helper did not confirm deletion. Refresh the emulator list before retrying.")
        }
    }

    func call<Value: Decodable & Sendable>(_ arguments: [String]) async throws -> Value {
        let result = await execute(invocation.node, [invocation.script] + arguments, invocation.environment)
        return try Self.decode(result)
    }

    static func decode<Value: Decodable & Sendable>(_ result: ProcessResult) throws -> Value {
        guard let envelope = try? JSONDecoder().decode(HelperEnvelope<Value>.self, from: result.standardOutput), envelope.protocolVersion == 1 else {
            let detail = result.failureDescription ?? String(decoding: result.standardError, as: UTF8.self)
            throw EmulatorCreationError("The emulator helper returned an invalid protocol response. Select a protocol version 1 helper or clear the override in Settings → Emulators. \(String(detail.prefix(1500)))")
        }
        guard result.succeeded, envelope.ok, let data = envelope.data else {
            throw EmulatorCreationError(envelope.error?.message ?? result.failureDescription ?? "The emulator helper failed. Check Settings → Emulators and retry.")
        }
        return data
    }
}

private struct HelperEnvelope<Value: Decodable>: Decodable {
    let protocolVersion: Int
    let ok: Bool
    let data: Value?
    let error: HelperFailure?
}
private struct HelperFailure: Decodable { let message: String }
