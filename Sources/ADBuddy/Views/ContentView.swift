import SwiftUI

struct ContentView: View {
    var body: some View {
        ContentUnavailableView(
            "Preparing ADBuddy",
            systemImage: "camera",
            description: Text("Android device discovery will appear here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
