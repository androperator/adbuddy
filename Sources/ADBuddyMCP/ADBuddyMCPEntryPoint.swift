import Foundation

@main
struct ADBuddyMCP {
    static func main() async {
        guard Array(CommandLine.arguments.dropFirst()) == ["serve"] else {
            FileHandle.standardError.write(Data("usage: adbuddy-mcp serve\n".utf8))
            return
        }

        await ADBuddyMCPServer().run()
    }
}
