import SwiftUI

struct LogcatWindowView: View {
    @Environment(DeviceStore.self) private var deviceStore

    let windowID: LogcatWindowID

    private var deviceName: String {
        deviceStore.devices.first(where: { $0.serial == windowID.serial })?.displayName ?? windowID.serial
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(deviceName)
                .font(.title2.weight(.semibold))

            Text(windowID.serial)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Spacer()

            ContentUnavailableView(
                "Logcat is not connected yet",
                systemImage: "text.alignleft",
                description: Text("Log streaming will appear here when it is available.")
            )

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 420, alignment: .topLeading)
        .navigationTitle("Logcat - \(deviceName)")
    }
}
