import SwiftUI

struct EmulatorMenuContent: View {
    @Environment(EmulatorStore.self) private var emulatorStore

    var body: some View {
        switch emulatorStore.status {
        case .loading:
            Text("Loading Android Emulators")
        case .ready:
            if emulatorStore.virtualDevices.isEmpty {
                Text("No Android Virtual Devices")
            } else {
                ForEach(emulatorStore.virtualDevices) { virtualDevice in
                    Button(virtualDevice.name) {
                        AppLogger.emulator.info("Android Emulator selected from launcher menu")
                        emulatorStore.start(virtualDevice)
                    }
                }
            }

            Divider()

            Button("Refresh Emulator List") {
                emulatorStore.refreshVirtualDevices()
            }
        case .unavailable(let failure):
            Text(failure.title)

            Divider()

            Button("Retry") {
                emulatorStore.refreshVirtualDevices()
            }
        }
    }
}
