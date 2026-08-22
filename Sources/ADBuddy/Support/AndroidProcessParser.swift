import Foundation

enum AndroidProcessParser {
    static func parse(_ output: String) -> [AndroidRunningProcess] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let columns = rawLine.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: \.isWhitespace
            )
            guard columns.count == 3,
                  let userID = Int(columns[0]),
                  let processID = Int(columns[1]) else {
                return nil
            }

            return AndroidRunningProcess(
                userID: userID,
                processID: processID,
                name: String(columns[2])
            )
        }
    }
}

enum AndroidPackageUserIDParser {
    static func parse(packageID: String, output: String) -> Int? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.hasPrefix("package:\(packageID) ") else {
                continue
            }

            for component in line.split(whereSeparator: \.isWhitespace) {
                guard component.hasPrefix("uid:") else {
                    continue
                }
                return Int(component.dropFirst("uid:".count))
            }
        }

        return nil
    }
}
