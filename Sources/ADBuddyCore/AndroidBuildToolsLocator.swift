import Foundation

public struct AndroidBuildToolsLocator: Sendable {
    private let directoryContents: @Sendable (String) -> [String]
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        directoryContents: @escaping @Sendable (String) -> [String] = { path in
            (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        },
        isExecutable: @escaping @Sendable (String) -> Bool = { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
    ) {
        self.directoryContents = directoryContents
        self.isExecutable = isExecutable
    }

    public func aapt2Path(for sdk: AndroidSDK) -> String? {
        let buildToolsDirectory = URL(fileURLWithPath: sdk.rootPath)
            .appendingPathComponent("build-tools", isDirectory: true)
            .path

        let versions = directoryContents(buildToolsDirectory).sorted {
            $0.compare($1, options: .numeric) == .orderedDescending
        }

        for version in versions {
            let aapt2Path = URL(fileURLWithPath: buildToolsDirectory)
                .appendingPathComponent(version, isDirectory: true)
                .appendingPathComponent("aapt2")
                .path
            if isExecutable(aapt2Path) {
                return aapt2Path
            }
        }

        return nil
    }
}
