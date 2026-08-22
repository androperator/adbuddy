import Foundation

struct AndroidRunningProcess: Equatable, Sendable {
    let userID: Int
    let processID: Int
    let name: String

    var applicationID: String? {
        let packageCandidate = name.split(separator: ":", maxSplits: 1).first.map(String.init) ?? name
        let components = packageCandidate.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count > 1,
              components.allSatisfy({ component in
                  !component.isEmpty && component.allSatisfy { character in
                      character.isLetter || character.isNumber || character == "_"
                  }
              }) else {
            return nil
        }
        return packageCandidate
    }
}

enum LogcatStreamScope: Equatable, Sendable {
    case allApplications
    case userID(Int)
}

enum LogcatApplicationScope: Equatable, Sendable {
    case allApplications
    case userID(Int, isWaitingForProcess: Bool)
    case processIDs(Set<Int>)
    case waitingForProcess

    static func resolve(
        packageID: String,
        packageUserID: Int?,
        processes: [AndroidRunningProcess],
        prefersUserIDFiltering: Bool
    ) -> LogcatApplicationScope {
        let matchingProcesses = processes.filter {
            $0.name == packageID || $0.name.hasPrefix("\(packageID):")
        }

        guard !matchingProcesses.isEmpty else {
            if prefersUserIDFiltering, let packageUserID {
                return .userID(packageUserID, isWaitingForProcess: true)
            }
            return .waitingForProcess
        }

        if prefersUserIDFiltering,
           let packageUserID,
           matchingProcesses.allSatisfy({ $0.userID == packageUserID }) {
            return .userID(packageUserID, isWaitingForProcess: false)
        }

        return .processIDs(Set(matchingProcesses.map(\.processID)))
    }

    var streamScope: LogcatStreamScope {
        switch self {
        case .allApplications, .processIDs, .waitingForProcess:
            .allApplications
        case .userID(let userID, _):
            .userID(userID)
        }
    }

    var isWaitingForProcess: Bool {
        switch self {
        case .userID(_, let isWaitingForProcess):
            isWaitingForProcess
        case .waitingForProcess:
            true
        case .allApplications, .processIDs:
            false
        }
    }

    func includes(_ entry: LogcatEntry) -> Bool {
        switch self {
        case .allApplications, .userID:
            true
        case .processIDs(let processIDs):
            processIDs.contains(entry.processID)
        case .waitingForProcess:
            false
        }
    }
}
