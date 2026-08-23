import SwiftUI
import UniformTypeIdentifiers

private struct APKDropTarget: ViewModifier {
    let isEnabled: Bool
    let receiveAPK: (URL) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard isEnabled,
                      let provider = providers.first else {
                    return false
                }

                _ = provider.loadObject(ofClass: URL.self) { fileURL, _ in
                    guard let fileURL, fileURL.isFileURL else {
                        return
                    }
                    Task { @MainActor in
                        receiveAPK(fileURL)
                    }
                }
                return true
            }
    }
}

extension View {
    func apkDropTarget(
        isEnabled: Bool,
        receiveAPK: @escaping (URL) -> Void
    ) -> some View {
        modifier(APKDropTarget(isEnabled: isEnabled, receiveAPK: receiveAPK))
    }
}
